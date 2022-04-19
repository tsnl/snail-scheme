## GC

Cf TCMalloc: https://github.com/google/tcmalloc/blob/master/docs/design.md

The garbage collector for `snail-scheme` is a two-color mark-and-sweep 
allocator for a thread-private heap. The design of this allocator is based
on TCMalloc, but such that all allocations specify their size class rather
than a size. This allows us to elide the pagemap, which uses a radix tree.

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

Future improvements:
- escape analysis to move short-lived heap allocations onto the stack
