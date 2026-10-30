# Snail-Scheme

Snail-Scheme is more than just a Scheme compiler and runtime: it is a framework 
for building portable, high-performance, distributed, and formally verified 
applications atop modern web technology (WebAssembly, WebGPU, ...).

It relies on Scheme's macro and library systems to support Scheme and other 
languages by expanding them all to a low-level, statically-typed language named 
"Snail-Core".

By strictly type-checking and specializing at the core level, Snail-Scheme
achieves excellent runtime performance, provides helpful type-directed error
messages ahead of time, and facilitates formal verification of distributed 
systems using its type system.

## Snail-Core

Snail-Scheme does not compile or run Scheme code directly, like most Scheme 
implementations. Instead, it relies on Scheme's macros and libraries to expand
Scheme's standard syntax into a lower-level core-language, named "Snail-Core".

Snail-Core is statically-typed, functional, eager, and low-level. It is closer
to ML or Rust than to Scheme, while remaining convenient to write and read. 
**Most Snail libraries are written in Snail-Core directly.**

Functional programming essentials like let-polymorphism, ad-hoc polymorphism
(typeclasses), closures, and proper tail calls are all supported by Snail-Core. 
A Koka-inspired effect system makes effects explicit and controllable, including 
`ctl` effects that involve one-shot delimited continuations.

Snail-Core also supports low-level programming features. Pointers, manual
memory management, and unsafe casts are all supported. Affine types enable 
Rust-style static ownership checks. Closures can capture-by-move. Allocations
are never automatically inserted, and all allocations require an explicit effect
to be in-scope, allowing performance-sensitive code to forbid allocations.

`Any` is Snail-Core's escape hatch to facilitate dynamic typing. The compiler 
works hard to eliminate all `Any` type judgements, but upcasts to `Any` always
imply a performance cost, and downcasts from `Any` always imply runtime checks.

Together, these features create a powerful statically-typed substrate upon which
Scheme or other languages can be built. This also lets us type-check across IPC 
boundaries, producing something like protobuf/gRPC supercharged by a 
state-of-the-art type-and-effect-system.

## The Application Framework

Modern applications are complex networks of processes and services. For example, 
a full-stack web app may contain one or more backend services, countless 
front-end client instances, and state managed by third-party services like 
databases or in-browser IndexedDB instances. GUI applications also do not 
typically own their own application loops anymore. Instead, a runtime invokes
callbacks on events like input, render, tick, etc to avoid blocking the main 
thread. Even multithreaded applications can be modeled as several single-
threaded processes that share memory. So can CPU/GPU applications that 
communicate across a GPU ABI boundary.

Today's programming languages lack support for type-checking across these 
boundaries. IPC typically relies on untyped JSON payloads or binary blobs, both
of which are error prone to use and difficult to understand. Solutions like gRPC 
can make types explicit at these boundaries, but must cater to the lowest common 
denominator type systems and cannot define an ABI.

Snail-Scheme uses the same types to model IPC as any in-process workflow.
This makes the Snail-Scheme runtime truly distributed, while still being 
type-checked. Serialization and deserialization code is automatically generated
and transparently managed for application developers. ABI guarantees are 
explicit and predictable.

Because event handlers are explicit, we can also statically trace control flow
across process boundaries. Integrating solutions like TLA+ to model-check 
protocols is future work.

## Libraries and Build Phases

Libraries are usually defined with the `(define-library ...)` form as specified 
in R7RS Scheme. However, they can also be defined using the 
`(generate-library ...)` form, which runs Snail code to generate the AST for
an exported library. The compiler handles staging boundaries automatically.

The `(generate-library ...)` feature is a powerful way to integrate arbitrary
content workflows into Snail-Scheme.

TODO: continue this.

## Next Steps

TODO: continue here.
