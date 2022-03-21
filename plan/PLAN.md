PLAN

GOAL: snail-scheme is an embeddable Scheme interpreter, where libraries offer standardized Scheme and C++ interfaces.
- ordinary C++ objects expressible as pointers or `size_t` handles can be wrapped as an unboxed OBJECT
- code can start life in Scheme and eventually move to C++
  - Scheme is great for moving code to ahead-of-time computation
  - C++ is great for...
    - memory management
    - applying monadic (lazy) side-effects
  - IDEA: Use Pure Scheme, just make IO lazy, write a `reactor`
    - changes GC/memory management significantly
      - Scheme can allocate and return: after this, must collect with Cheney on the MTA
      - if stack never exceeded, collection only occurs on subprocess end
      - subprocesses triggered by event-driven framework (cf Elm)
    - changes IO significantly: now C++ must...
      - implement monads representing mutation
      - handle all memory allocation/de-allocation
    - TODO: implement 'BaseReactor' in C++: template for a job system.
      - a reactor is an event generator that plugs into certain input sources and output sinks.
      - a single reactor ('the' reactor) runs all jobs for an interpreter.
        - the reactor provides events that are bound from C++: 
        - the user can...
          - subscribe: bind a function to an event
            - 1-to-many binding: bound do not know if/how many others are bound.
          - publish: raise an event from a function 
          - 'events' are just arbitrary OBJECT instances
        - events are managed using channels
          - the channel is the only parallel data-structure provided
          - channels are used for intra-reactor communication only
          - TODO: can you transmit channels on channels?
            - easy if each interpreter maintains a global list of channels like ports
            - cf Pi calculus, nominal computation
        - the reactor stops when there are no more events left to run
          - it's like a big reduction machine in some ways
      - reactors are responsible for applying jobs' IO monads, managing memory
        - TLDR: each job is allocated some scratch to return an IO monad, which the reactor applies and uses to perform GC.
        - each job has some scratch heap area that is cleaned up after the job is completed: jobs should be small.
        - each job returns an IO monad that specifies an ordered list of lazily applied side-effects
          - WARNING: need to handle case where a variable is updated, then used, so need to be able to embed a fair amount of AST as data
          - IDEA: what about storing VM bytecode?
        - after running a job and while applying IO monads, the reactor must perform mark and sweep, retaining only globally accessible 
          memory.
      - reactors accept C++ bindings for events too
        - this is critical for performance

TASKS

- implement modules and languages, allow 'require' to resolve
  - modules: allow bundles of mixed C++ and Scheme code using Scheme's type-system.
  - languages: make a module an ambient requirement, serves as 'builtins'.
  - this lets us implement primitive builtins as a module that is required at first.
  - NOTE: for simplicity, languages can be a C++-facing feature at first: the user can 
    specify a base language to load when initializing the VM (provides an initial 
    environment).
  - 'require' must resolve to C++ and Scheme modules registered
    - can register a directory to load as a root name, these must have a 'main.scm' root file
      - use '/' to access sub-modules
    - can register a C++ object as a module with a synthetic name
      - can even contain submodules that are entirely synthetic or loaded from source code
      - if C++ modules and Scheme modules are to be mixed, C++ is the mixer
    - FUTURE: allow exporting a DLL as a module

- implement macros
  - BRANCH: (choose one)
    - learn about and implement `macroexpand` in Scheme
    - implement `macroexpand` as a C++ function
