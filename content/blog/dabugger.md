---
{
  "title": "dabugger",
  "published": "2026-06-05",
  "author": "Mehdi Hassan",
  "tags": [ "debuggers" ],
  "series": "Write your own debugger from scratch"
}
---

# dabugger - writing my own debugger from scratch in C

#### *This article was written by a human.*

I've been working on `dabugger`, an x86-64 debugger for Linux ELF + DWARF executables. The only third party libraries I used are glibc, [zydis]() for disassembly, and [ncurses]() for the TUI. This article is a summary of my journey working on this project. The order of topics may seem atypical but this is roughly the actual implementation order. 

**Please note that I am not an expert**. In fact I am not even a professional software developer (though [I am looking for a graduate or entry level role](https://www.linkedin.com/in/mehdi-syed-hassan/)). I've tried to include accurate information as much as I can, and I started writing this article after I got the debugger to a functional state, so that I have the benefit of hindsight.

## Introduction

### Motivation

Roughly two months ago I wanted to debug my STM32 blue pill I had bought to dip my toes into embedded programming. I plugged in my ST-Link and started a remote session with GDB. Everything seemed to be working until I switched to the TUI assembly view with `tui layout asm`. I could scroll down the list of assembly instructions, but I couldn't scroll up! On top of that, occasionally the TUI wouldn't refresh correctly and half the screen would show one thing and the other half would show another. I experience frame tearing all the time when playing games but I did not expect it on a TUI of all things... although given how bloated these new TUI based LLM agents are perhaps I now can. I had searched the internet for a while to see if it was something I could resolve but all I could find was [this](https://stackoverflow.com/questions/26572805/gdb-tui-scroll-assembly-view-above-current-instruction#26603663) currently 7 year old stackoverflow post suggesting that you continually enter the disassemble command at a previous address, and a comment recommending you use a GDB frontend.

Admittedly you're *expected* to use the CLI for GDB, but it doesn't really excuse the fact that the de-facto standard for Linux debuggers has a TUI thats buggy and awkward to use to this day. Also, as a novice user, I don't want to comb through help commands to do something as simple as setting breakpoints, retrieving the value of a register or executing the debuggee (which I imagine is the extent of what people wish to do in the majority of cases where print debugging is insufficient). Rarely do I use any debugging features more complicated than this, but when I need them then I am willing to spend more time to learn the tool and bear the friction. In most cases, however, my attention is solely focused on fixing my program, not learning the quirks of my debugger. Finally, while I can attest to how efficient CLIs can be for other tools, a debugger is undoubtedly something that benefits from a more visually expressive interface- be it a TUI or a GUI.

I wondered how difficult it would be to write my own debugger, not some GDB/LLDB frontend or a library wrapper with a fancy interface, but something I could reasonably say I wrote from scratch. I just wanted something simple feature-wise: a TUI, source and assembly breakpoints, debuggee output display and register inspection. Besides this, following from my experiences with Linux debuggers thus far, ease of use and good user experience was my forefront concern.

It also goes without saying that writing a debugger is an excellent learning experience for an aspiring systems programmer (like yours truly). You are exposed to a broad range of topics, ranging from essential to niche. Additionally, relative to other tools, there isn't a lot of content about debuggers. Hence, the learning potential is another reason I chose to do this project.

### Feasibility

It turns out writing your own debugger "from scratch" is actually not too hard! Well... provided of course you make a few concessions; **I forwent the following**:

- Variable inspection
- Conditional breakpoints
- Fancier features that rely heavily on source code constructs

However, `dabugger` **does currently support**:

- Viewing the source and assembly of compilation units referenced by the debuggee executable's debug information
- Highlighting the assembly instructions that correspond to a particular source line
- Setting source and assembly line breakpoints
- A TUI with some vim motion keybindings
- Displaying the debuggee's output
- Inspecting the debuggee's registers

Personally I would *love* to have included variable inspection in particular. The rationale behind skipping the former features and keeping the latter ones is primarily down to this: DWARF is quite complicated!

DWARF is the debugging format used in the ELF binaries of modern Linux programs, under the various `.debug_*` sections. Most of the debug information lives within the `.debug_info` section, though it references some of the other debug sections. This section contains a tree of DIEs (an acronym for Debugging Information Entry). Each DIE represents a part of the program: variables, constants, types, functions, etc. Naturally some DIEs refer to others (for example, a variable DIE referring to a type DIE), and some DIEs are composed of nested children. For more information, [here](https://dwarfstd.org/doc/Debugging%20using%20DWARF-2012.pdf) is the official introduction to DWARF. Its a short read at 11 pages.

Alas, the actual [DWARF 5 standard]() (as of the time of writing, the latest version of DWARF) is ~400 pages long! Writing a fully featured DWARF parser is an arduous endeavour. At the other end of the spectrum, you could just avoid parsing DWARF entirely. The Linux syscall for tracing a process is aptly named `ptrace()`, and it exposes enough functionality for you to set machine instruction level breakpoints, read registers and single step through instructions. Such a debugger, assuming you use a third party disassembler, could be written in a weekend or two in a few hundred lines. However, for me personally, its not feature complete enough to see myself actually using it.

After reading the previously mentioned introduction, I found a tractable middle ground to writing something decently useful. The `.debug_line` section contains the DWARF information for the mapping from source lines to the most relevant machine instructions. Only ~20 pages of the DWARF 5 specification is dedicated to parsing this section. Since DWARF 5, this section is also mostly self contained, so we don't have to touch the DIE tree at all. Parsing this allows us to introduce a very useful feature: **source line breakpoints**.

All in all, this being my first C project and after just ~3k lines of code, I'd say this endeavour went pretty well and its actually kind of useable.

## Parsing ELF Binaries

I used the glibc `elf.h` header file to conveniently obtain the structs and typedefs I'd need to parse the debuggee ELF file. It also includes a lot of helpful comments so it served well as a reference too, along with the image below: 
![ELF structure diagram](https://upload.wikimedia.org/wikipedia/commons/e/e4/ELF_Executable_and_Linkable_Format_diagram_by_Ange_Albertini.png)

### The ELF Header
We need to parse the ELF header first. `elf.h` exposes an `Elf64_Ehdr` struct that we can use for parsing the header of an 64 bit ELF binary. You would use `Elf32_Ehdr` for ELF32 files, but for `dabugger` we are only concerned with ELF64.

First we read in the first 16 bytes, corresponding to `e_ident`.

- The first 4 bytes represent the magic number for all ELF files:
  * `e_ident[0] ==  0x7f`
  * `e_ident[1] == 'E'`
  * `e_ident[2] == 'L'`
  * `e_ident[3] == 'F'`
- `e_ident[4]` represents the file class, letting us determine if the file is a 32 or 64 bit binary.
- `e_ident[5]` tells us whether the binary is in little endian or big endian format, x86-64 is little endian.
- `e_ident[6]` is the ELF version, Linux uses version 1.
- `e_ident[7]` represents the OS ABI and `e_ident[8]` the ABI version.
- `e_ident[9]` to `e_ident[15]` are for padding.

We check that these values are what we expect:
```c
ProgramData parse_elf_file(const char *path) {
	FILE *elf_file = fopen(path, "rb");
	if (elf_file == NULL)
		goto sys_error;

	size_t read_count;
	int seek_result;

	Elf64_Ehdr elf_header = {0};

	read_count = fread(&elf_header.e_ident, EI_NIDENT, 1, elf_file);
	if (read_count != 1)
		goto sys_error;

	if (memcmp(&elf_header.e_ident, ELFMAG, SELFMAG) != 0) {
		fprintf(stderr, "This is not an ELF file!\n");
		goto error;
	}

	if (elf_header.e_ident[EI_CLASS] != ELFCLASS64) {
		fprintf(stderr,
				"dabugger currently only supports 64 bit executables.\n");
		goto error;
	}

	if (elf_header.e_ident[EI_DATA] != ELFDATA2LSB) {
		fprintf(
			stderr,
			"dabugger currently only supports little endian executables.\n");
		goto error;
	}

	/* ... */
}
```

Having determined the ELF file is valid, we can now read in the remainder of the header. We check that `e_machine` (the architecture) is x86-64. After that, we allocate enough space for the section header table. The section header table is a contiguous array of ELF section headers. There are `elf_header.e_shnum` section headers, with each section header having size `elf_header.e_shentsize`. We can then seek to the section header offset, relative to the beginning of the file. This is given by `elf_header.e_shoff`. Now, we simply read in all the section headers.

We're only interested in the following ELF sections:

- `.text`: This contains the program instructions, we'll use this during disassembly.
- `.debug_line`: This contains the DWARF line number information for the program.
- `.debug_str`: This contains strings referenced by the DWARF `.debug_*` sections. 
- `.debug_line_str`: This contains strings referenced specifically by the `.debug_line` section. In practice, `.debug_line` may reference both this section and `.debug_str`.

Additionally, we need to read the section header strings table as an intermediate value. This is because while iterating over the section headers, we need to determine what the name of the current section is, and the names of the sections are found in the section header strings table.

```c
ProgramData parse_elf_file(const char *path) {
	/* ... */
	
	read_count =
		fread(&elf_header.e_type, sizeof(Elf64_Ehdr) - EI_NIDENT, 1, elf_file);
	if (read_count != 1)
		goto sys_error;

	if (elf_header.e_machine != EM_X86_64) {
		fprintf(stderr,
				"dabugger currently only supports x86-64 executables.\n");
		goto error;
	}

	Elf64_Shdr *section_header =
		malloc(elf_header.e_shentsize * elf_header.e_shnum);

	seek_result = fseek(elf_file, (long)elf_header.e_shoff, SEEK_SET);
	if (seek_result != 0)
		goto sys_error;

	read_count = fread(section_header, elf_header.e_shentsize,
					   elf_header.e_shnum, elf_file);
	if (read_count != elf_header.e_shnum)
		goto sys_error;

	Elf64_Shdr string_table_header = section_header[elf_header.e_shstrndx];

	seek_result =
		fseek(elf_file, (long)string_table_header.sh_offset, SEEK_SET);
	if (seek_result != 0)
		goto sys_error;

	char *section_names = malloc(string_table_header.sh_size);

	read_count = fread(section_names, string_table_header.sh_size, 1, elf_file);
	if (read_count != 1)
		goto sys_error;

	SectionBuffer text_section = {0};
	SectionBuffer debug_line_section = {0};
	SectionBuffer debug_str_section = {0};
	SectionBuffer debug_line_str_section = {0};

	for (Elf64_Half i = 0; i < elf_header.e_shnum; i++) {
		Elf64_Shdr current_section_header = section_header[i];
		Elf64_Word section_name_offset = current_section_header.sh_name;

		char *section_name = &section_names[section_name_offset];

		SectionBuffer *current_section = NULL;

		if (strcmp(section_name, ".debug_line") == 0) {
			current_section = &debug_line_section;
		} else if (strcmp(section_name, ".debug_str") == 0) {
			current_section = &debug_str_section;
		} else if (strcmp(section_name, ".debug_line_str") == 0) {
			current_section = &debug_line_str_section;
		} else if (strcmp(section_name, ".text") == 0) {
			current_section = &text_section;
		} else {
			continue;
		}

		current_section->address = current_section_header.sh_addr;
		current_section->size = current_section_header.sh_size;
		current_section->data = malloc(current_section_header.sh_size);

		seek_result =
			fseek(elf_file, (long)current_section_header.sh_offset, SEEK_SET);
		if (seek_result != 0)
			goto sys_error;

		read_count = fread(current_section->data,
						   current_section_header.sh_size, 1, elf_file);
		if (read_count != 1)
			goto sys_error;
	}
	
	/* ... */
}
```

You may find the full ELF parser code [here](). Now that we've obtained what we need from the executable file, we can start parsing the line number information.

## Parsing DWARF Line Number Information

As alluded to in the introduction, the `.debug_line` section contains mappings of machine instructions to source locations. 

The mapping from source lines to machine instructions is not a one to one correspondence. A source line could be related to multiple, non-contiguous machine instructions, and more than one source line could refer to the same instruction. Also, this mapping isn't order preserving- subsequent source lines could refer to previous machine instructions. Finally, especially at higher optimization levels, a suitable mapping is not always clear (due to instruction pipelining and other techniques employed by modern instruction set architectures). Fortunately, compilers produce this mapping for us when we pass `-g`, with more sensical results at the `-Og` or `-O0`optimization levels.

A DWARF consumer (our debugger), after parsing the `.debug_line` section, *eventually* ends up with a set of matrix representations of this mapping. Each matrix would contain the line information for a given compilation unit involved in building the debuggee executable. There would be one row per machine instruction, containing information like the instruction address, the source file name, line and column number, whether it is a recommended breakpoint location, etc. Once we have a suitable address for a source line, we can insert a breakpoint there with `ptrace`. This also allows us to step by source line, rather than only by machine instruction. *(Reference: DWARF 5 Specification, Page 149)*

However, `.debug_line` does not contain the line number information in its matrix representation out of the box. Storing such a matrix directly, particularly since many values are duplicated from row to row, is extremely space inefficient. Instead, the line number information is encoded as a byte-coded instruction stream that is interpreted using a state machine.

The binary data in `.debug_line` is structured as a series of **line number programs**, each preceded by a **line number program header**. Each line number program contains the bytecode instruction stream encoding the line number information for a particular compilation unit. The header for each line number program contains valuable metadata about how to decode it. 

### LEB128 Decoding
The line number programs and their headers use the [LEB128](https://en.wikipedia.org/wiki/LEB128) (Little Endian Base 128) format for some of the integer values. As an aside, we will discuss how to deal with LEB128 and why it is used here.

The following example is taken from the [LEB128 Wikipedia page](https://en.wikipedia.org/wiki/LEB128), and illustrates the process for *encoding* an *unsigned number* as unsigned LEB128 (ULEB128).

```
Encoding the unsigned number 624485 as ULEB128:
MSB ------------------ LSB
      10011000011101100101  In raw binary
     010011000011101100101  Padded to a multiple of 7 bits
 0100110  0001110  1100101  Split into 7-bit groups
00100110 10001110 11100101  Add high 1 bits on all but last (most significant) group to form bytes
    0x26     0x8E     0xE5  In hexadecimal

→ 0xE5 0x8E 0x26            Output stream (LSB to MSB)
```

Likewise, here is the Wikipedia example for encoding a signed number as signed LEB128.

```
MSB ------------------ LSB
         11110001001000000  Binary encoding of 123456
     000011110001001000000  As a 21-bit number
     111100001110110111111  Negating all bits (ones' complement)
     111100001110111000000  Adding one (two's complement)
 1111000  0111011  1000000  Split into 7-bit groups
01111000 10111011 11000000  Add high 1 bits on all but last (most significant) group to form bytes
    0x78     0xBB     0xC0  In hexadecimal

→ 0xC0 0xBB 0x78            Output stream (LSB to MSB)
```

The DWARF 5 Standard, Appendix C, also has some examples on how to encode and decode LEB128.

Since we're writing a DWARF consumer, we only need to decode LEB128. We don't need to write any code to encode LEB128, but I included the above examples for pedagogical reasons. All we have to do is perform the steps in reverse. I've written a reader library in `dabugger` to contain the decoder functions, so that parsing binary formats is convenient and so that I can extend it with other reader functions. Here is what the relevant parts look like:

[`reader.h`]()
```c
#ifndef DABUGGER_READER_H
#define DABUGGER_READER_H

#include <stdint.h>
#include <stdlib.h>

typedef struct {
    const uint8_t *cursor;
    size_t remaining;
} BinaryReader;

typedef enum {
    READ_OK = 0,
    READ_ERR_OUT_OF_BOUNDS,
    READ_ERR_LEB_U64_OVERFLOW,
    READ_ERR_LEB_I64_OVERFLOW
} ReadStatus;

typedef struct {
    size_t bytes_consumed;
    ReadStatus status;
} ReadResult;

/* ... */

extern ReadResult read_bytes(BinaryReader *reader, void *out, size_t bytes);

/* ... */

extern ReadResult read_uleb128(BinaryReader *reader, uint64_t *out);

extern ReadResult read_sleb128(BinaryReader *reader, int64_t *out);

/* ... */

#endif /* DABUGGER_READER_H */
```

[`reader.c`]()
```c
#include "reader.h"

/* ... */

ReadResult read_bytes(BinaryReader *reader, void *out, size_t bytes) {
    const uint8_t *current_cursor = reader->cursor;

    ReadResult result = advance_reader(reader, bytes);
    if (result.status != READ_OK)
        return result;

    memcpy(out, current_cursor, bytes);
    return result;
}

/* ... */

ReadResult read_uleb128(BinaryReader *reader, uint64_t *out) {
    ReadResult result = {0};
    uint8_t byte;
    *out = 0;
    do {
        if (result.bytes_consumed == 10) {
            result.status = READ_ERR_LEB_U64_OVERFLOW;
            return result;
        }

        ReadResult byte_read_result = read_bytes(reader, &byte, 1);

        if (byte_read_result.status != READ_OK) {
            result.status = byte_read_result.status;
            return result;
        }

        *out |= (uint64_t)(byte & 0x7f) << ((result.bytes_consumed) * 7);
        result.bytes_consumed++;
    } while ((byte & 0x80) != 0);
    return result;
}

ReadResult read_sleb128(BinaryReader *reader, int64_t *out) {
    ReadResult result = {0};
    uint8_t byte;
    *out = 0;
    do {
        if (result.bytes_consumed == 10) {
            result.status = READ_ERR_LEB_I64_OVERFLOW;
            return result;
        }

        ReadResult byte_read_result = read_bytes(reader, &byte, 1);

        if (byte_read_result.status != READ_OK) {
            result.status = byte_read_result.status;
            return result;
        }
        *out |= (int64_t)(byte & 0x7f) << ((result.bytes_consumed) * 7);
        result.bytes_consumed++;
    } while ((byte & 0x80) != 0);

    if ((result.bytes_consumed * 7 < sizeof(int64_t) * CHAR_BIT) &&
        ((byte & 0x40) != 0)) {
        *out |= -((int64_t)1 << (result.bytes_consumed * 7));
    }

    return result;
}

/* ... */
```

DWARF, along with WebAssembly and even Minecraft and osu! use LEB128 to compress integers. The Wikipedia article uses the phrase "arbitrarily large integers", which when I first read it, confused me quite a lot. Firstly, how is this a useful compression scheme for arbitrarily large integers, when it is always at least as large as the original data? Secondly, why does DWARF need to encode arbitrarily large integers, when the only numbers you would be dealing with in debug information has size up to `sizeof(size_t)` of the target architecture? The Wikipedia article unfortunately does not make this clear but after working through my DWARF parser I understood why.

As for the second question, I read [LLVM's binary reader](https://github.com/llvm/llvm-project/blob/240539f1c1ba5f72ce5879807ed1a6dd5b694ef5/llvm/lib/Support/BinaryStreamReader.cpp#L43), which they also use as a utility to parse DWARF, among other things. As you can see, they use a reference to a `uint64_t` as their output parameter. If LLVM does it this way, then I rest assured that I don't have to implement some BigInt library in C because DWARF *probably* won't require me to parse integers larger than 8 bytes (though as far as I know, the specification does not impose this explicitly).

As for the first question, the utility of this compression scheme lies in how it saves space for small integers. Suppose you have some integral data, the range of which can be large (even arbitrarily large). However, most of the instances of this data in practice are small. You want to keep the flexibility of having a large range of possible values, but you want to save some space because most of the time you encounter small integers rather than massive ones. LEB128 is a great fit for this. Rather than requiring say, `uint64_t` all the time, you could just use LEB128 and the small values will take up a small number of bytes, as if you had used a smaller integer type, and large values would take up requisite space accordingly.

We will soon see that for our parser, in most cases we will be dealing with small numbers (eg. increment a register by a small value), but on occasion we will need to parse a big one (eg. a fixed absolute address to jump to).

### Line Number Program Headers

<!-- TODO -->

### Decoding a Line Number Program

<!-- TODO -->

### Relevant Tooling

<!-- TODO: Embed this in the content instead? -->
#### `gcc` & `clang`

#### `dwarfdump`

#### `readelf`

## Designing the Terminal User Interface

I used `ncurses` for the TUI. Its part of the GNU project and comes packaged with most Linux distros. The API is quite simple and provides enough features that I needed. I was contemplating whether to use `notcurses`, which is newer, but I didn't really need the features it introduces.

We have five windows in the interface, one of which is a popup menu:

- File picker window: This is a popup menu which lets you choose which compilation unit referenced by the debug line information you want to view and set breakpoints on.
- Source window: 
- Assembly window: 
- Output window:
- Registers window:

### The Elm Architecture (Model/View/Update)

## Debuggee Control

### Handling Position Independent Executables

`ptrace`

### Breakpoints

### Capturing Output with a `pty`

### Event Loop with `poll()`
