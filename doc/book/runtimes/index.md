# Runtimes

`snail-scheme`'s shipping target is WebAssembly GC. Tasks are suspended
computations, scheduled in `snail-scheme`; a host drives the scheduler and
completes the operations tasks wait on. A runtime supplies the platform's
capabilities and owns the computations that use them. Each
instance of a program is single-threaded; parallel work runs as several
instances, which will talk through queues and shared memory
([instances](instances.md), proposed).

The **host** is the surrounding platform, such as Node or a browser. A runtime
owns language tasks; an OS process owns its platform execution environment.
The [toolchain terms](../snail-scheme/terms.md#toolchain-terms) keep these boundaries
distinct in the project and development design.

The [task contract](contract.md) specifies the replacement for
the actor API. It separates scheduling, capabilities and the
values tasks hold. The actor request/reply API has been removed. [Task operations](tasks.md)
run in the CLI and GUI. [Applications](../snail-scheme/applications.md) describes
pages' saves on that runtime.
[Values](../snail-scheme/values.md) describes sharing, mutation and resources.
The [socket capabilities](networking.md) bind typed, replaceable TCP and UDP operations
to native Node resources, with cancellation and shutdown owned by the runtime, and
[`Processes`](networking.md#child-processes) binds child processes the same way.

## Execution and waiting

Every call into Wasm runs until it returns: no import suspends a Wasm
stack. A task waits by returning. Its suspension unwinds through
each frame to the task's `with-prompt`, whose handler hands the rest of the
task back to the scheduler, and the host's call returns. The host then runs its own
event loop, and calls in again for the next turn
([driving the scheduler](scheduling.md)). A host operation that completes
later starts on one call and finishes on another, under a ticket its
completion wakes. A pending Promise alone does not keep a Node process
alive; a runtime must account for outstanding work and own any required
process-lifetime token.

An event loop, an I/O readiness service and a scheduler serve different
purposes. Linux `epoll` reports which descriptors can make progress; it
does not schedule language closures. Our hosts
use JavaScript platform APIs for Node and browser I/O notifications,
[asynchronous file reads](tasks.md#native-asynchronous-file-reads) among
them.
`snail-scheme`'s scheduler owns tasks on both hosts. It does not need its own `epoll` wrapper. See the
[Linux interface](https://man7.org/linux/man-pages/man7/epoll.7.html).

## Rust subsystems

Give a Rust subsystem a typed `snail-scheme` interface. The application
works with ordinary records and arrays. Inside the library, `extern`
declarations call functions supplied by the Rust crate
`crates/snail-scheme-support`. The build links this provider,
`snail.core.support`, into the program's Wasm module. The engine traces
the application's managed values. Rust owns its working data in linear
memory and controls when to release it.
[Foreign functions](../snail-scheme/types.md#foreign-functions) ·
[Linking](../snail-scheme/toolchain.md#assembly-linking-and-optional-optimization)

For example, Last Mile calls `step-traffic!` once per simulation tick.
The chassis library passes road geometry, driver inputs, poses and momenta
as scalars. Rapier advances the cars and nearby pedestrians together. The
library copies the results back into the same game records and releases
the Rust world. A saved shift therefore holds the bodies' poses and momenta
as ordinary `snail-scheme` values. The build includes Rapier when a
program imports `(snail shell game chassis)`.
[Game simulation](../libraries/games.md) · [Last Mile Taxi](../games/last-mile.md)

## Scaling the deployed program

For CPU parallelism today, run independent instances in separate execution
agents or processes and distribute requests at the service boundary. A
reverse proxy can load-balance several processes. Each instance has its own
managed heap; communication uses an explicit external protocol.

`snail-scheme` does not need a second compiler backend to use multiple
independently hosted instances.

## Direction

Node and the page are today's hosts, not the only ones `snail-scheme` is for.
Others, such as [workerd](https://github.com/cloudflare/workerd), should be
able to run the same programs, so nothing a program or library does may
depend on
JavaScript: a host provides Wasm imports, and JavaScript is the glue that
provides them on Node and in the page.

Both hosts already do only what a host must: WASI, their device services, WebGPU among them, which Node
gets from Dawn ([WebGPU on Node](../graphics/plan.md#webgpu-on-node)), and
the loop that turns the scheduler. A program is one module linked with its runtime, which each
instantiates. An engine written in `snail-scheme` once linked programs
compiled one library at a time
([#660](https://github.com/tsnl/snail-scheme/issues/660)); it went when
every build became one linked module.
A native executable embedding [wasmtime](https://wasmtime.dev) once ran
programs that needed only WASI and files; it is removed, since its
collector made the compiler compiling itself take 46 s against Node's 1.3 s
([#562](https://github.com/tsnl/snail-scheme/issues/562)) and it was a
second host to keep for no program that needed it. A target for a new host
handles the portable subset of capabilities
([scripts](../snail-scheme/scripts.md)) and adds its own. workerd's isolates
are not OS processes, and its WasmGC and import support must be checked
before promising compatibility.

The Unicode tables, transcendental math and float printing already live in
`snail-scheme`. One proposal would also let the core I/O library call WASI
directly once it has the necessary linear-memory primitives.
[Core I/O proposal](https://github.com/tsnl/snail-scheme/blob/main/crates/snail-scheme-support/README.md#later)

## Future work

[Instances, queues and shared memory](instances.md) proposes how several
single-threaded instances will cooperate. [Continuations and parallel
execution](future.md) retains the earlier backend research.
