## GC := Reactor

The garbage collector for `snail-scheme` is an arena allocator where we can
and a copying garbage collector when we must.

Each allocation is a simple stack allocation operation. When the stack
overflows, we run a stop-the-world mark-and-sweep pass.

There is no (user-facing) global heap memory. All inter-thread 
communication occurs via _channels_, which are an extension datatype I
that allow messages to be asynchronously posted and retrieved via a
synchronized FIFO.

> By restricting all synchronization to builtins whose explicit purpose
> is synchronization, we ensure the user pays no synchronization overhead
> when operating on common data-structures, and ensures that each VM
> instance executes in a single-threaded environment (concurrency, not 
> parallelism). There is a similar philosophy behind Python's GIL.

The Reactor model allows us to allocate cheaply, and then collect cheaply:
after an initialization phase, the reactor maps short-lived jobs onto logical
cores in response to _events_ enqueued asynchronously. Each thread resets
a stack allocator (arena allocator) between job-runs: if this allocator 
overflows, we raise an exception: execution cannot continue given the heap
size being targeted.

This approach ensures that allocations are cheap, most stacks are not traced,
and that the usual design-solution to 'stutters' arising from a stop-the-world
compaction is to factor code into smaller jobs, which generally aids rather than
harms readability. Finally, this strategy makes copying garbage collection, a
very simple GC strategy, viable: because only one thread is likely to collect at
a time, the asymptotic overhead of collection in the average case nears 0 as 
processors obtain more logical cores.*

> *- This hits a limit at the point that multiple
> jobs collect at a high-level of granularity, but this limit will only be hit if
> jobs are poorly designed OR if the system is achieving extremely high throughput,
> scheduling so many more jobs than a fewer-core system that it schedules infrequent
> GC-overflows simultaneously. Ultimately, collections run as often as the client
> program dictates them to. :)

> This encourages solutions that operate on fixed amounts of memory, which is
> the best solution to allocation overhead: never allocating. 

## User Interface

The user still feeds the compiler a single entry-point script which resides in a
global heap. 
This script is executed in serial fashion, allocating to a large arena.
During this script's execution, callbacks can be bound to respond to messages.

After the script executes, the reactor performs a compacting copy of the heap into
another global heap that is fixed. Then, the original arena is subdivided into each
worker's memory for the reactor, and the reactor begins polling for events.


