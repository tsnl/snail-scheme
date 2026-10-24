# Terms

{{#include ../../language.md:terms}}

## Toolchain terms

These names distinguish source organization, compilation and execution.
The project-file and `lofi dev` workflow is
[proposed](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md),
not implemented yet.

| Term | Meaning |
| --- | --- |
| Project | One directory of source files and its project description. A plain directory can be edited before a description is added. |
| Workspace | A collection of projects. The proposed tools support one project; they do not introduce a workspace object. |
| Build target | A named description of what to build. It produces one output directory, which may contain multiple files. |
| Artifact bundle | The complete output of a build target, resolved by name during compilation. |
| Launch target | A named command for running a built program with its arguments. |
| Build attempt | One invocation of project building, with an ID, diagnostics and a success/failure result. |
| Compiler session | Cached expansion, checking and emitted code retained between builds. |
| Development session | A running `lofi dev`: file watching, persistent compilation, application control and the editor's services. |
| Application process | An OS subprocess running a program. A browser frontend is a client of a server process, not another launch target by necessity. |
| Runtime | The scheduler and effect bindings executing a program's tasks. It is distinct from both the compiler session and the OS process. |
| Host | The platform environment, such as Node or a browser, providing APIs to the runtime. |
| Worker | A separate execution agent used for CPU work. Here a native compiler worker keeps its own compiler state; it is not a browser Service Worker or a Lofi task. |

**Incremental compilation** reuses compiler work. **Restart** replaces an
application process and resets its in-memory state. **Hot reload** (also
called live reload) replaces running code through an application state-handover
contract. Recompiling incrementally does not by itself preserve application
state, and moving execution into a worker does not supply a handover contract.
