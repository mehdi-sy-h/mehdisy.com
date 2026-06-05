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

<!--
TODO: Move to bottom, this article is not a series but mention that you might write one if people are interested.
-->

Welcome to this series on writing your own debugger from scratch, in C, for x86-64 Linux executables. The only third party libraries we will be using are glibc, [zydis]() for disassembly, and [ncurses]() for the TUI.

**Please note that I am not an expert**. In fact I am not even a professional software developer (though [I am looking for a graduate or entry level role]()). I've tried to include accurate information as much as I can, and I started writing this series after I got the debugger to a functional state, *TODO*.

## Introduction

### Motivation

Roughly two months ago I wanted to debug my STM32 blue pill I had bought to dip my toes into embedded programming. I plugged in my ST-Link and started a remote session with GDB. Everything seemed to be working until I switched to the TUI assembly view with `tui layout asm`. I could scroll down the list of assembly instructions, but I couldn't scroll up! On top of that, occassionally the TUI wouldn't refresh correctly and half the screen would show one thing and the other half would show another. I experience frame tearing all the time when playing games but I did not expect it on a TUI of all things... although given how bloated these new TUI based LLM agents are perhaps I now can. I had searched the internet for a while to see if it was something I could resolve but all I could find was [this](https://stackoverflow.com/questions/26572805/gdb-tui-scroll-assembly-view-above-current-instruction#26603663) currently 7 year old stackoverflow post suggesting that you continually enter the disassemble command at a previous address, and a comment recommending you use a GDB frontend.

Admittedly you're *expected* to use the CLI for GDB, but it doesn't really excuse the fact that the de-facto standard for Linux debuggers has a TUI thats buggy and awkward to use to this day. Also, as a novice user, I don't want to comb through help commands to do something as simple as setting breakpoints, retrieving the value of a register or executing the debuggee (which I imagine is the extent of what people wish to do in the majority of cases where print debugging is insufficient). Rarely do I use any debugging features more complicated than this, but when I need them then I am willing to spend more time to learn the tool and bare the friction. In most cases, however, my attention is solely focused on fixing my program, not learning the quirks of my debugger. Finally, while I can attest to how efficient CLIs can be for other tools, a debugger is undoubtedly something that benefits from a more visually expressive interface- be it a TUI or a GUI.

I wondered how difficult it would be to write my own debugger, not some GDB/LLDB frontend or a library wrapper with a fancy interface, but something I could reasonably say I wrote from scratch. I just wanted something simple feature-wise: a TUI, source and assembly breakpoints, debuggee output display and register inspection. Besides this, following from my experiences with Linux debuggers thus far, ease of use and good user experience was my forefront concern.

It also goes without saying that writing a debugger is an excellent learning experience for an aspiring systems programmer (like yours truly). You are exposed to a broad range of topics *TODO*.

### Feasibility

It turns out writing your own debugger is actually not too hard! Well... provided of course you make a few concessions. *TODO*. All in all, this being my first C project, taking just ~3k lines of code, I'd say this endeavour went pretty well.

## Project Setup

We will be using CMake for this project. Since I daily drive NixOS, I've also written a simple Nix flake.

```cmake
cmake_minimum_required(VERSION 3.30)

project(dabugger
  VERSION 0.1.0
  LANGUAGES C
)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options(
  -Wall
  -Wextra
  -Wpedantic
  -Wshadow
  -Wconversion
  # TODO: Remove the following two options once supported
  -gdwarf64
  -fno-pie
)

add_executable(${PROJECT_NAME}
  src/dabugger.c
  src/elf.c
  src/dwarf.c
  src/reader.c
  src/tui.c
  src/debug.c
)

# TODO: Remove the line once supported
target_link_options(${PROJECT_NAME} PRIVATE -no-pie)

target_compile_options(${PROJECT_NAME} PRIVATE
	$<$<CONFIG:Debug>:-g3 -Og>
	$<$<CONFIG:Release>:-O2 -DNDEBUG>
	# TODO: Remove the following option once supported
	$<$<C_COMPILER_ID:GNU>:-gno-as-loc-support>
)

# TODO: Allow non-wide or curses support (will require guards in tui.h)
set(CURSES_NEED_NCURSES TRUE)
set(CURSES_NEED_WIDE TRUE)
find_package(Curses REQUIRED)

if(Curses_FOUND AND NOT TARGET Curses::Curses)
	add_library(Curses::Curses INTERFACE IMPORTED)
	set_target_properties(
				Curses::Curses
				PROPERTIES
						INTERFACE_LINK_LIBRARIES "${CURSES_LIBRARIES}"
						INTERFACE_INCLUDE_DIRECTORIES "${CURSES_INCLUDE_DIRS}"
		)
endif()

find_library(PANEL_LIBRARY panelw REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE Curses::Curses ${PANEL_LIBRARY})

set(ZYDIS_FEATURE_ENCODER OFF)
find_package(Zydis REQUIRED)

target_link_libraries(${PROJECT_NAME} PRIVATE Zydis)

install(TARGETS ${PROJECT_NAME})
```

## Parsing DWARF Line Number Programs (`.debug_line`)

### LEB128 Decoding

## Designing the Terminal User Interface

### The Elm Architecture (Model/View/Update)

## Debuggee Control

### Breakpoints

### Capturing Output with a `pty`

### Event Loop with `poll()`
