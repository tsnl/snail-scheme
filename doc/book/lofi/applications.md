# Application model

{{#include ../../language.md:applications}}

<a id="live-reload"></a>

## Hot reload

This section describes the current browser application implementation.
The proposed [project workflow](toolchain.md#proposed-project-workflow) moves
development watching to `lofi dev` and requires server and browser data to
survive code replacement. It proposes storage as that boundary, while working
state stays in RAM. The handover implementation below has not yet changed.

`lofi serve APP-DIRECTORY` builds an application one library at a time,
serves it at `http://127.0.0.1:8000/`, and builds it again whenever the
application's directory, the standard library or the browser host
changes, compiling only the libraries the change reaches. Each page it
serves relinks the modules that changed, and those after them, without
reloading. Their globals start over; the application's state crosses to
the new program:

- as it is, when `type-test` finds its type unchanged;
- through `save` and `restore` when its layout changed. That is the
  contract a page reload already relies on, so an application whose save
  is a journal, as Siegework's is, replays the journal under the new code;
- not at all when the save cannot be restored either: the old program
  keeps running, and the page offers to start the new one over.

A failed build is shown over the page, and the old program keeps running.
A program that traps keeps the last state whose whole event succeeded,
including presentation. The next good build resumes from that checkpoint
without repeating the failing event; unread actions wait for it. A cold
first-frame failure also stays available for a source fix. Reload waits for
the old root to save and return, then cancels and drains its remaining
tasks and I/O cleanup before relinking. It accepts a new
entry only after its first frame succeeds. A changed style
sheet is fetched again; a changed page or host script reloads the page
after saving. Each event carries the manifest of the build being served,
so a page that missed events, even across a restart of the server,
catches up from the next one.

Neither `lofi serve` nor the IDE builds a `generate-library` recipe yet, so
an application with one, such as Hearsay, is built with `make site`.

`lofi watch SOURCE` is the same loop for a program: it builds and runs the
program again whenever its sources change, stopping a run still in
progress once a new build succeeds. [The development
toolchain](toolchain.md) describes how builds stay this fast, and the
browser IDE that runs the same loop without a server.

### Proposed persistence boundary

The [design for review](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md#4-running-and-reloading-applications)
keeps ordinary updates and rendering in memory. A planned browser reload
would commit the application's saved representation, then restore it in a
fresh instance. This would replace direct cross-build state handover, subject
to measuring checkpoint and restoration costs before deleting the relink path.
Siegework's journal-based save is compact but still requires replay; fast
incremental compilation does not make that reconstruction free.

Server processes would reopen the same actual database after replacement.
Committed records survive; caches and connections are reconstructed. Any
additional RAM-only state promised to survive must be explicitly saved by
the application. Browser periodic checkpoints remain useful for recovery
after unexpected exits, but cannot preserve changes not yet committed.

Storage errors must stay distinct from missing data. A failed reload save
must leave the old browser loop usable; incompatible saved data must remain
intact. Fresh instance replacement would drop automatic recovery to the old
loop after a replacement startup failure: saved data survives, but the page
awaits a fix or retry. These are proposed changes, not guarantees of the
implementation described above.

## Task lifetime

Each invocation owns a [task runtime](../runtimes/scheduling.md). Normal
root completion after initial presentation lets children finish. Root
failure or return before that acceptance boundary closes the runtime.
Explicit reload waits for the root's
checkpoint handover before closing it. Repeated stop requests share one
handover result. This is application lifecycle policy; ordinary task
completion does not cancel its children.

Event waits and storage use the same suspension bridge as task waits.
Their cancellation signals belong to the invocation that began the call.
Non-abortable storage may delay teardown until it finishes. An old
completion cannot write into a replacement invocation.

Only one loop consumes application events. The runtime buffers input and
coalesces frames; it does not own an implicitly shared current world.
The root task owns event consumption, boot acknowledgement and checkpoint
storage. Calling these operations from a detached task fails before any
input or saved bytes change. A child can use task waits and separately bound
I/O, but cannot replace the application's checkpoint while its loop saves.
Read-only seed and canvas dimensions remain available to all tasks.
