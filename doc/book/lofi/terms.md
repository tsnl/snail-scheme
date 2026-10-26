# Terms

{{#include ../../language.md:terms}}

## Toolchain terms

These names distinguish source organization, compilation and execution.
Project descriptions, builds and the native `lofi dev` editor are implemented.
The [application process and persistence workflow](applications.md#proposed-application-processes)
remains proposed.

| Term | Meaning |
| --- | --- |
| Project | One directory of source files and its project description. A plain directory can be edited before a description is added. |
| Workspace | A collection of projects. The tools support one project; they do not introduce a workspace object. |
| Build target | A named description of what to build. It produces one output directory, which may contain multiple files. |
| Artifact bundle | The complete output of a browser build target, resolved by name during compilation. |
| Run target | A named command for running a program build with its arguments. |
| Build attempt | One invocation of project building, with an ID, diagnostics and a success/failure result. |
| Compiler session | Cached expansion, checking and emitted code retained between builds. |
| Development session | A running `lofi dev`: file watching, persistent compilation and the editor's services. Application control remains planned. |
| Application process | An OS process running a program. A browser frontend is a client of a server process, not a run target. |
| Runtime | The scheduler and effect bindings executing a program's tasks. It is distinct from both the compiler session and the OS process. |
| Host | The platform environment, such as Node or a browser, providing APIs to the runtime. |
| Worker | A separate execution agent used for CPU work. Here a native compiler worker keeps its own compiler state; it is not a browser Service Worker or a Lofi task. |
| Working state | In-memory values used by the running application, including changes not yet saved. |
| Persisted data | The application's chosen representation committed to storage independently of the running code. It need not encode every transient resource or cache. |

**Incremental compilation** reuses compiler work. **Restart** starts a fresh
application process; the application can reconstruct working state from
persisted data. **Hot reload** (also called live reload) replaces
running code while preserving application data under a stated contract.
Today's browser uses state handover; the proposal uses durable typed tables
and disposable cached views, recomputed on demand after ordinary startup.
Recompiling incrementally does not by itself preserve application state, and
moving execution into a worker does not supply a preservation contract.
