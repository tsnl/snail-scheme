# Runtimes

Snail-Core's shipping target is WebAssembly GC, with JavaScript Promise
Integration (JSPI) suspending tasks until tasks become effects. A runtime
supplies platform effects and owns the computations that use them. Each
instance of a program is single-threaded; parallel work runs as several
instances, which will talk through queues and shared memory
([instances](instances.md), proposed).

The **host** is the surrounding platform, such as Node or a browser. A runtime
owns language tasks; an OS process owns its platform execution environment.
A compiler session is cached compiler work, not an application runtime.
The [toolchain terms](../snail-core/terms.md#toolchain-terms) keep these boundaries
distinct in the project and development design.

The [task contract](contract.md) specifies the replacement for
the actor API. It separates scheduling, handler installations and owned
values. The actor request/reply API has been removed. [Task operations](tasks.md)
run in the CLI and GUI. [Applications](../snail-core/applications.md) describes
checkpoint handover and reload on that runtime. [One-shot work and
ownership](ownership.md) describes the implemented affine subset.
The [socket effects](networking.md) bind typed, interceptable TCP and UDP operations
to native Node resources, with cancellation and shutdown owned by the runtime, and the
[process effect](networking.md#child-processes) binds child processes the same way.

## Execution and suspension

A synchronous piece of Wasm runs until it returns or reaches a suspending
import. A JSPI import can return a Promise: Wasm execution suspends while
the JavaScript event loop services other work. Resolving or rejecting that
Promise resumes or fails the computation. A pending Promise alone does not
keep a Node process alive; a runtime must account for outstanding work and
own any required process-lifetime token.

An event loop, an I/O readiness service and a scheduler serve different
purposes. Linux `epoll` reports which descriptors can make progress; it
does not schedule language closures or preserve effect bindings. Our host
uses JavaScript platform APIs for I/O notifications, and JSPI for suspended
Wasm stacks. It does not need its own `epoll` wrapper. See the
[Linux interface](https://man7.org/linux/man-pages/man7/epoll.7.html) and
[V8's JSPI explanation](https://v8.dev/blog/jspi).

## Scaling the deployed program

For CPU parallelism today, run independent instances in separate execution
agents or processes and distribute requests at the service boundary. A
reverse proxy can load-balance several processes. Each instance has its own
managed heap; communication uses an explicit external protocol.

[workerd](https://github.com/cloudflare/workerd) is a possible host to
investigate, not a currently supported Snail-Core deployment target. Its isolates
are not synonymous with OS processes. Its WasmGC, JSPI and import support
must be checked before promising compatibility. Snail-Core does not need a second
compiler backend to use multiple independently hosted instances.

## Future work

[Instances, queues and shared memory](instances.md) proposes how several
single-threaded instances will cooperate. [Tasks as effects](https://github.com/tsnl/snail-scheme/issues/511)
will replace JSPI with a scheduler written in Snail-Core, using one-shot
continuations. [Continuations and parallel execution](future.md) retains
the earlier backend research.
