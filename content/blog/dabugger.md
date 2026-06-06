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

I've been working on `dabugger`, an x86-64 debugger for Linux ELF + DWARF executables. The only third party libraries I used are glibc, [zydis]() for disassembly, and [ncurses]() for the TUI. This article is a summary of my journey working on this project. If anyone is interested, I may also write a more detailed tutorial style series.

**Please note that I am not an expert**. In fact I am not even a professional software developer (though [I am looking for a graduate or entry level role](https://www.linkedin.com/in/mehdi-syed-hassan/)). I've tried to include accurate information as much as I can, and I started writing this article after I got the debugger to a functional state, so that I have the benefit of hindsight.

## Introduction

### Motivation

Roughly two months ago I wanted to debug my STM32 blue pill I had bought to dip my toes into embedded programming. I plugged in my ST-Link and started a remote session with GDB. Everything seemed to be working until I switched to the TUI assembly view with `tui layout asm`. I could scroll down the list of assembly instructions, but I couldn't scroll up! On top of that, occasionally the TUI wouldn't refresh correctly and half the screen would show one thing and the other half would show another. I experience frame tearing all the time when playing games but I did not expect it on a TUI of all things... although given how bloated these new TUI based LLM agents are perhaps I now can. I had searched the internet for a while to see if it was something I could resolve but all I could find was [this](https://stackoverflow.com/questions/26572805/gdb-tui-scroll-assembly-view-above-current-instruction#26603663) currently 7 year old stackoverflow post suggesting that you continually enter the disassemble command at a previous address, and a comment recommending you use a GDB frontend.

Admittedly you're *expected* to use the CLI for GDB, but it doesn't really excuse the fact that the de-facto standard for Linux debuggers has a TUI thats buggy and awkward to use to this day. Also, as a novice user, I don't want to comb through help commands to do something as simple as setting breakpoints, retrieving the value of a register or executing the debuggee (which I imagine is the extent of what people wish to do in the majority of cases where print debugging is insufficient). Rarely do I use any debugging features more complicated than this, but when I need them then I am willing to spend more time to learn the tool and bear the friction. In most cases, however, my attention is solely focused on fixing my program, not learning the quirks of my debugger. Finally, while I can attest to how efficient CLIs can be for other tools, a debugger is undoubtedly something that benefits from a more visually expressive interface- be it a TUI or a GUI.

I wondered how difficult it would be to write my own debugger, not some GDB/LLDB frontend or a library wrapper with a fancy interface, but something I could reasonably say I wrote from scratch. I just wanted something simple feature-wise: a TUI, source and assembly breakpoints, debuggee output display and register inspection. Besides this, following from my experiences with Linux debuggers thus far, ease of use and good user experience was my forefront concern.

It also goes without saying that writing a debugger is an excellent learning experience for an aspiring systems programmer (like yours truly). You are exposed to a broad range of topics, ranging from essential to niche. Additionally, relative to other tools, there isn't a lot of content about debuggers. Thus, the learning potential is another reason I chose to do this project.

### Feasibility

It turns out writing your own debugger "from scratch" is actually not too hard! Well... provided of course you make a few concessions; **I forwent the following**:

- Variable inspection
- Conditional breakpoints
- Step into function execution
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

Alas, the actual [DWARF 5 standard]() (as of the time of writing, the latest version of DWARF) is ~400 pages long! Writing a fully featured DWARF parser is an arduous endeavour. At the other end of the spectrum, you could just avoid parsing DWARF entirely. The Linux syscall for tracing a process is aptly named `ptrace()`, and it exposes enough functionality for you to set machine instruction level breakpoints, read registers and single step through instructions. Such a debugger, assuming you use a third party disassembler, could be written in a weekend in a few hundred lines. However, for me personally, its not feature complete enough to see myself actually using it.

After reading the previously mentioned introduction, I found a tractable middle ground to writing something decently useful. The `.debug_line` section contains the DWARF information for the mapping from source lines to the most relevant machine instructions. Only ~20 pages of the DWARF 5 specification is dedicated to parsing this section. Since DWARF 5, this section is also mostly self contained, so we don't have to touch the DIE tree at all. Parsing this allows us to introduce a very useful feature: **source line breakpoints**.

<!--
TODO: Move to dwarf section?

The mapping from source lines to machine instructions is not a one to one correspondence. A source line could be related to multiple, non-contiguous machine instructions, and more than one source line could refer to the same instruction. Also, this mapping isn't order preserving- subsequent source lines could refer to previous machine instructions. Finally, especially at higher optimization levels, a suitable mapping is not always clear (due to instruction pipelining and other techniques employed by modern instruction set architectures). Fortunately, compilers produce this mapping for us when we pass `-g`, with more sensical results at the `-Og` or `-O0`optimization levels.

A DWARF consumer (our debugger), after parsing the `.debug_line` section, *eventually* ends up with a set of matrix representations of this mapping. Each matrix would contain the line information for a given compilation unit involved in building the debuggee executable. Once we have a suitable address for a source line, we can insert a breakpoint there with `ptrace()`. I will discuss the structure of this matrix and how to parse this section, which is not in matrix form out of the box, later on in the article.
-->
All in all, this being my first C project and after just ~3k lines of code, I'd say this endeavour went pretty well and its actually kind of useable.

## Project Setup

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
  # TODO: Remove the following option once supported
  $<$<C_COMPILER_ID:GNU>:-gno-as-loc-support>
)

#...
```

Funnily enough, it was here that I ran into my first problem. You may notice that I'm not using any sanitizers. *TODO* 

## Parsing DWARF Line Number Programs (`.debug_line`)

### LEB128 Decoding

## Designing the Terminal User Interface

### The Elm Architecture (Model/View/Update)

## Debuggee Control

`ptrace`

### Breakpoints

### Capturing Output with a `pty`

### Event Loop with `poll()`
