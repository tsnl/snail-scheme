# `snail-scheme`

`snail-scheme` is my personal minimal Scheme implementation.

It offers a nice-to-use C++ API that is easily extended using C++'s native OOP
principles.

It includes a basic interpreter (SSI) written in C++.
- the interpreter is based on Ch3 of ["Three Implementations"](/doc/three-imp.pdf), using a heap-based VM.
  - the use of a byte-code VM is key to realizing Scheme's continuations and 
    tail-recursion: this implementation (and all future implementations) will be 
    properly tail-recursive.
  - implementation of Ch4 is partially complete, moving most data-structures to the stack.
- the `object.hh` header contains the `OBJECT` datatype, which offers an efficient representation of
  latently typed objects within C++.
  - `OBJECT` instances will also offer support for manually-invoked mark-and-sweep GC.
- 

## Language Features / Digressions from Scheme

0.  Language is dynamically typed, but with support for 'assert' (cf Typed Racket) for refinement typing upon monotype 
    system
0.  No block comments supported
0.  Like R7RS and unlike older Scheme revisions, identifiers are case-sensitive.

## Build instructions

0.  Ensure you run `git submodule update --init --recursive` to fetch all dependencies.
1.  Build with CMake: will require a C++20-compliant compiler.

## Plan

Many features to implement!

1.  STABLE SINGLE THREADED EXECUTION

    -   run GC in single-threaded mode: perform necessary plumbing.
    -   update VM to latest available version of three-imp: this will allow 
        divergence from three-imp to support multithreading once stack is finalized.

2.  MULTI-THREADED EXECUTION

    -   Single-threaded mode is the primary mode of operation, but the VM can
        instantiate a global Reactor if they so desire.

        The reactor is the ~preferred~ only way to do multi-threading in 
        Snail-Scheme, and offers a job system with grand central dispatch.
    
    -   The reactor only runs on non-main threads, and only runs in the background,
        so the main thread must still read output from the reactor via **channels**,
        which are `SmtFifo<OBJECT>` classes that implement `IBoxedObject`

    -   Channels should behave like ports in that they are just IDs (names) that are
        unique per-instance.

    -   The reactor is more of an accelerator than a primary workhorse.
    
        It can be used by standard libraries.

        E.g. windowing and 3D game engine can both use the reactor as a generic
        event pump and job manager.
    
3.  ACCELERATORS, DISTRIBUTED COMPUTING

    -   Key feature: ability to generate different code. <br/>
        => can target different kinds of bytecode via DSLs (e.g. SPIRV) <br/>
        => can compile and link own source code into a more efficient representation <br/>
        => interpreter is merely a platform for generating and running or dumping efficient, generated code.

    -   Channels should be diversified into...
        -   DmaChannels: used to communicate with reactor workers, drivers
        -   NetworkChannels: used to communicate with clients over TCP/IP, HTTPS, etc
        -   Since channels are nominal...
            -   can emulate Pi calculus and use same code with 'channel' interface
            -   can replicate environment on all distributed nodes so code can be 
                exchanged and run (cf `delay` and `force`)