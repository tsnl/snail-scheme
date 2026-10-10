# Platforms

The first three platforms are **native CLI**, **native GUI**, and **browser GUI**.
A platform starts a root actor, supplies its runtime services, and invokes its
handlers. The native CLI is implemented for one instance per x86-64 Linux
process; the GUI contracts remain proposals. The [AWI extension](../awi.md)
documents the scalar Scheme/runtime calls they build on.

A platform contract has two independent parts:

- **Handlers the program provides:** exported methods that make the module
  spawnable by this platform. The CLI has one entry; a GUI has event handlers.
- **Operations the platform provides:** imported procedures available through
  utility libraries. Programs choose the interfaces they use.

Imports and exports in each WAT file show this direction explicitly. Supporting
an operation does not mean requiring a handler with the same name. Several
platforms can implement the same operation interface with the same types,
ownership, and behavior. The native and browser GUI platforms share such an
interface without pretending their surfaces have identical implementations.

These imported operations are effects in the ordinary sense: they interact with
the world. Platform bindings handle them. For now, library imports and linking
select the provider; no new effect syntax, dynamically scoped handler stack, or
resumable operation is required. If we later need those semantics, they can build
on the operation contracts. A platform must reject unavailable imports before
invoking the program; the browser does not inherit native OS capabilities.

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
