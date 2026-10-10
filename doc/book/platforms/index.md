# Platforms

The first three platforms are **native CLI**, **native GUI**, and **browser GUI**.
A platform starts a root actor, supplies its runtime services, and invokes its
handlers. These platform contracts are proposals; the existing compiler/runtime
does not yet implement them. The [AWI extension](../awi.md) documents the scalar
Scheme/runtime calls they build on.

| Platform | Entry and dispatch | Primary use |
| --- | --- | --- |
| [Native (CLI)](native-cli.md) | Invoke a command once; Rust owns OS IO and subprocesses. | The self-hosted interpreter, builds, command tools, and servers. |
| [Native (GUI)](native-gui.md) | A native event loop invokes application handlers. | Windows, game frames, retained graphics resources. |
| [Browser (GUI)](browser-gui.md) | The browser invokes similar handlers for an owned DOM subtree. | Documents, interactive workbooks, and web applications. |

The GUI platforms share lifecycle, input, and redraw concepts inspired by
[winit's application handlers](https://docs.rs/winit/latest/winit/application/trait.ApplicationHandler.html).
Browser DOM composition is a separate set of operations on the same platform.
A surface is a native window or an application-owned DOM subtree; individual DOM
elements are not windows. Browser event timing and DOM ownership choices remain
proposals, recorded alongside their function declarations.

Each platform page renders **only its WAT interface file**. Function roles,
parameter meanings, ownership, lifecycle, errors, and open questions live in the
WAT comments beside the declarations. There is no second symbol list to maintain.
All example function bodies are non-executable `unreachable` stubs.
