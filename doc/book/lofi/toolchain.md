# Development toolchain

Lofi builds programs as C does. A release build links statically: the
whole program is compiled at once, optimized, and merged with the Rust
runtime into one module. A debug build links dynamically: each library is
its own module, and the modules are linked, with the runtime as a separate
instance, when the program starts.

| Command | Build |
| --- | --- |
| `lofi run`, `lofi compile`, `make site` | Release |
| `lofi serve`, `lofi watch`, `make ide` | Debug |

## Builds in proportion to the edit

`lofi serve` and `lofi watch` run a development loop that is itself a
Lofi program, `(lofi develop)`, and keeps the compiler running between
builds. It remembers every library's **interface**: everything importers
depend on, which is every declaration but the bodies of functions with
monomorphic signatures. An edit to such a body recompiles one library; an
edit to an interface recompiles the libraries that import it too.

```text
$ ./lofi serve apps/siegework
built siegework in 457 ms: 14 of 14 modules compiled
serving siegework at http://127.0.0.1:8000/
built siegework in 106 ms: 1 of 14 modules compiled
```

A page relinks the modules that changed and every module after them, which
are the only ones that can import from them, and keeps the application's
state ([live reload](applications.md#live-reload)). Because the loop
checks each library before the libraries that import it, a definition
gets its type from its own library: give constants a signature where a
literal could have more than one type, as `(lofi app)` gives its key codes
`I32`.

## The browser IDE

The following describes the current implementation. The
[desktop IDE proposal](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md)
would replace its browser backend with a native project server, remove the
integrated preview and launch applications in separate processes with
external browser windows. That design awaits review; the commands below
have not changed.

`make ide` packages an IDE as a static site in `build/ide`, with nothing to
install and no server beyond one for static files:

```text
$ make ide
$ python3 -m http.server --directory build/ide
```

It opens Siegework until you open a folder of your own; the project stays
in the browser's storage, and saving writes each file back to its folder
where the browser allows it. The toolbar along the top toggles the file
browser on the left and the running application on the right, and splits
the editor panes. Code is highlighted as you type; Tab and Enter indent as
Emacs's Scheme mode does, and saving formats the file as `make check`
expects. Each edit, saved or not,
goes to the development loop running in a worker, compiler included: a
build that fails puts a squiggle under what the compiler points at, and one
that succeeds relinks the application, in 50 to 100 ms for an edit to one
library of Siegework.

## Loading code while a program runs

`(lofi wasm)` loads a WebAssembly module from a file, linked against the
program's own modules, and takes the functions it exports. They arrive
untyped, as a `Funcref`, and `unsafe-cast` makes one a function of the
type its context expects:

```scheme
(import
 (lofi base)
 (lofi io)
 (lofi wasm))

(let* ((module (load-module "adder" "adder.wasm"))
       (add (ann (unsafe-cast (module-export module "add")) (-> I64 I64 I64))))
  (display (add 40 2)))
```

Nothing checks the Lofi type. WebAssembly traps if the function's own
type differs from the one Lofi gives `(-> I64 I64 I64)`, and the program
ends. The Node runner provides the `wasm` effect; browser hosts do not
yet.

[The toolchain design](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)
explains separate compilation, the recursion groups that let WebAssembly
types match across modules, and what is left to build.
