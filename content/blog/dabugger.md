---
{
  "title": "dabugger",
  "published": "2026-06-05",
  "author": "Mehdi Hassan",
  "tags": [ "debuggers" ],
  "series": "Write your own debugger from scratch"
}
---

# dabugger - writing a debugger from scratch as my first C project

#### *This article was written by a human.*

I've been working on `dabugger`, an x86-64 debugger for Linux ELF + DWARF executables. The only third party libraries I used are glibc, [zydis]() for disassembly, and [ncurses]() for the TUI. This article is a summary of my journey working on this project. The order of topics may seem atypical but this is roughly the actual implementation order. If anyone is interested, I may also write a more detailed tutorial style series.

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
- Proper step into/step out of function execution
- Other fancier features

However, `dabugger` **does currently support**:

- Viewing the source and assembly of compilation units referenced by the debuggee executable's debug information
- Highlighting the assembly instructions that correspond to a particular source line
- Setting source and assembly line breakpoints
- A TUI with some vim motion keybindings
- Displaying the debuggee's output
- Inspecting the debuggee's registers

Personally I would *love* to have included variable inspection, and perhaps also "step into/out". The rationale behind skipping the former features and keeping the latter ones is primarily down to this: DWARF is quite complicated!

DWARF is the debugging format used in the ELF binaries of modern Linux programs, under the various `.debug_*` sections. Most of the debug information lives within the `.debug_info` section, though it references some of the other debug sections. This section contains a tree of DIEs (an acronym for Debugging Information Entry). Each DIE represents a part of the program: variables, constants, types, functions, etc. Naturally some DIEs refer to others (for example, a variable DIE referring to a type DIE), and some DIEs are composed of nested children. For more information, [here](https://dwarfstd.org/doc/Debugging%20using%20DWARF-2012.pdf) is the official introduction to DWARF. Its a short read at 11 pages.

Alas, the actual [DWARF 5 standard]() (as of the time of writing, the latest version of DWARF) is ~400 pages long! Writing a fully featured DWARF parser is an arduous endeavour. At the other end of the spectrum, you could just avoid parsing DWARF entirely. The Linux syscall for tracing a process is aptly named `ptrace()`, and it exposes enough functionality for you to set machine instruction level breakpoints, read registers and single step through instructions. Such a debugger, assuming you use a third party disassembler, could be written in a weekend or two in a few hundred lines. However, for me personally, its not feature complete enough to see myself actually using it.

After reading the previously mentioned introduction, I found a tractable middle ground to writing something decently useful. The `.debug_line` section contains the DWARF information for the mapping from source lines to the most relevant machine instructions. Only ~20 pages of the DWARF 5 specification is dedicated to parsing this section. Since DWARF 5, this section is also mostly self contained, so we don't have to touch the DIE tree at all. Parsing this allows us to introduce a very useful feature: **source line breakpoints**.

<!--
TODO: Move to dwarf section?

The mapping from source lines to machine instructions is not a one to one correspondence. A source line could be related to multiple, non-contiguous machine instructions, and more than one source line could refer to the same instruction. Also, this mapping isn't order preserving- subsequent source lines could refer to previous machine instructions. Finally, especially at higher optimization levels, a suitable mapping is not always clear (due to instruction pipelining and other techniques employed by modern instruction set architectures). Fortunately, compilers produce this mapping for us when we pass `-g`, with more sensical results at the `-Og` or `-O0`optimization levels.

A DWARF consumer (our debugger), after parsing the `.debug_line` section, *eventually* ends up with a set of matrix representations of this mapping. Each matrix would contain the line information for a given compilation unit involved in building the debuggee executable. Once we have a suitable address for a source line, we can insert a breakpoint there with `ptrace()`. I will discuss the structure of this matrix and how to parse this section, which is not in matrix form out of the box, later on in the article.
-->
All in all, this being my first C project and after just ~3k lines of code, I'd say this endeavour went pretty well and its actually kind of useable.

<!--*TODO: Only include this section once you can figure the bug out properly.*

## Build Configuration

I used CMake for this project, `CMakeLists.txt` [here](). Since I daily drive NixOS, I've also written a simple `flake.nix` [here](). Below are particularly relevant parts of the configuration.

```cmake
#...
set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

#...

add_compile_options(
  # ...
  -gdwarf64
  -fno-pie
)

#...

target_link_options(${PROJECT_NAME} PRIVATE -no-pie)

target_compile_options(${PROJECT_NAME} PRIVATE
  $<$<CONFIG:Debug>:-g3 -Og>
  $<$<CONFIG:Release>:-O2 -DNDEBUG>
  $<$<C_COMPILER_ID:GNU>:-gno-as-loc-support>
)

#...
```

Funnily enough, it was while I was setting up my build configuration that I ran into my first problem. Initially I had enabled ASAN and UBSAN and compiled a Hello World program. I wanted to get my project and Nix devshell set up, and also wanted to become more familiar with gdb. If you checkout my [initial commit](), compile the hello world program and run it through gdb, you will come across this error:

```
Reading symbols from build/dabugger...
(gdb) start
Temporary breakpoint 1 at 0x1188: file /home/me/Source/dabugger/src/dabugger.c, line 6.
Starting program: /home/me/Source/dabugger/build/dabugger 
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/nix/store/l0l2ll1lmylczj1ihqn351af2kyp5x19-glibc-2.42-51/lib/libthread_db.so.1".

Temporary breakpoint 1, main (argc=1, argv=0x7fffffffa048) at /home/me/Source/dabugger/src/dabugger.c:6
6		printf("Hello, world!\n");
(gdb) n
Hello, world!
7		return EXIT_SUCCESS;
(gdb) n
8	}
(gdb) n
0x00007ffff6c2b285 in __libc_start_call_main ()
   from /nix/store/l0l2ll1lmylczj1ihqn351af2kyp5x19-glibc-2.42-51/lib/libc.so.6
(gdb) n
Single stepping until exit from function __libc_start_call_main,
which has no line number information.
==60278==LeakSanitizer has encountered a fatal error.
==60278==HINT: For debugging, try setting environment variable LSAN_OPTIONS=verbosity=1:log_threads=1
==60278==HINT: LeakSanitizer does not work under ptrace (strace, gdb, etc)
[Inferior 1 (process 60278) exited with code 01]
```

The hint seems to be pretty clear, LeakSanitizer does not work under ptrace. The `ptrace(2)` man page clearly states that ...*TODO: verify?*. However, having just tested this against the latest `dabugger` commit (which of course uses `ptrace()`), I don't appear to run into this issue? Why does it happen under `gdb` but not my `dabugger`? Unfortunately I could not find a conclusive reason for this online. 
-->

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

### LEB128 Decoding

## Designing the Terminal User Interface

### The Elm Architecture (Model/View/Update)

## Debuggee Control

`ptrace`

### Breakpoints

### Capturing Output with a `pty`

### Event Loop with `poll()`
