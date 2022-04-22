## GC

Cf TCMalloc: https://github.com/google/tcmalloc/blob/master/docs/design.md

> NOTE: <br/>
> TCMalloc uses the term 'object' to refer to a memory allocation of
> any size. <br/>
> SnailScheme uses the term 'object' to refer to an instance of a monotype
> in the Scheme programming language. <br/>
> In the GC, the term 'object' follows TCMalloc's convention: when ambiguous,
> we will call TCMalloc objects 'GC objects', and SnailScheme objects 'Scheme 
> objects'.

The garbage collector for `snail-scheme` is a two-color mark-and-sweep 
allocator for a thread-private heap. <br/>
Rather than implement a three-color collector with a write-barrier, I instead
use a staggered blocking collection that only pauses one thread at a time.

The design of this allocator is based on TCMalloc. <br/>
In TCMalloc terms, since every allocation is tracked in the front-end, it is
sufficient to mark-and-sweep only each front-end provided live allocations cannot 
traverse thread bounds. This means channels must copy their arguments.

The mark phase gathers pointers in a priority queue such that we access pointers
in sorted order. This improves cache coherency when accessing the page-map and
various free-lists.

Mark and sweep can be performed as follows only on the front-end:
- mark all objects in a set of pre-reserved vectors, one per size-class.
- sweep by reconstructing free-lists, i.e. ...
  - create fresh free-lists for each size-class
  - re-allocate each marked object in the free-list at the same position
    it was originally at
  - relinquish free pages to the transfer cache (middle-end)

Note that any allocations in the largest size-class, <+oo, must go into a 
special list in the frontend: allocations and de-allocations skip the 
transfer-cache, interacting directly with the [legacy tcmalloc] page heap.

There is no (user-facing) global heap memory. All inter-thread 
communication occurs via _channels_, which are an extension datatype I
that allow messages to be asynchronously posted and retrieved via a
synchronized FIFO. Data is always deep-copied lazily from the source heap to 
the destination heap: the copy is forced when the receiver receives the message.

> By restricting all synchronization to builtins whose explicit purpose
> is synchronization, we ensure the user pays no synchronization overhead
> when operating on common data-structures, and ensures that each VM
> instance executes in a single-threaded environment (concurrency, not 
> parallelism). There is a similar philosophy behind Python's GIL.

> UPDATE: stop-the-world GC means that all frontends are marked simultaneously <br/>
> => need to support page-map to look up which front-end a page is mapped to

Future improvements:
- escape analysis to move short-lived heap allocations onto the stack
