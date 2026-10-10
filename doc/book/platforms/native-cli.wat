;; Native CLI -- one command instance per native process (x86-64 Linux). Scheme
;; compiles through Wasm to native code and links the Rust runtime. The
;; platform owns command startup, OS IO, subprocesses, and resource teardown.
;;
;; Every call borrows an instance-local i32 root to an argument vector and
;; returns an owned result root. Brackets describe the Scheme arguments in that
;; vector. These are local AWI calls; actor connections serialize S-expressions
;; separately.
;;
;; Wasm module globals are initialized before the host invokes snail:main.
;; The generated adapter evaluates library/source forms once, then invokes the
;; selected Scheme handler. An ordinary script instead returns zero after its
;; top-level forms. build-native selects the handler explicitly; a helper named
;; main does not change script behavior. Rust is linked as a native archive.
;; Interface bodies below are documentary stubs.
;;
;; The self-hosting acceptance case is a build.scm that chooses output paths,
;; builds snail-scheme, and then runs under that interpreter to rebuild it.
;; Blocking IO/process calls are suitable for this command profile. A server
;; can keep its command alive; GUI-thread use needs asynchronous services
;; instead.
(module

  ;; ---- Operations provided by the platform ----

  ;; [] -> argv list of strings, including the executable/script identity
  ;; selected by the interpreter. Forward argument strings without shell parsing.
  (import "snail.rust" "snail:command-line"
    (func (param $arguments i32) (result i32)))

  ;; [count, optional input-port] -> string or EOF. Reads up to count Unicode
  ;; scalars; defaults to stdin and may block. A nonzero request reading nothing
  ;; returns EOF; count zero returns an empty string.
  (import "snail.rust" "snail:read-string"
    (func (param $arguments i32) (result i32)))

  ;; [value, optional output-port] -> unspecified. Writes display text; defaults
  ;; to stdout. Current-error-port selects stderr through the shared runtime API.
  ;; Output failure follows the runtime error contract.
  (import "snail.rust" "snail:display"
    (func (param $arguments i32) (result i32)))

  ;; [optional output-port] -> unspecified. Writes a newline to that port,
  ;; defaulting to stdout.
  (import "snail.rust" "snail:newline"
    (func (param $arguments i32) (result i32)))

  ;; [path] -> input-port. Rust performs the filesystem access. The current
  ;; implementation reads the complete file as UTF-8; the returned port is owned
  ;; by this instance.
  (import "snail.rust" "snail:open-input-file"
    (func (param $arguments i32) (result i32)))

  ;; [path] -> output-port. Creates or truncates a file. The build script
  ;; supplies output paths; the platform does not invent artifact locations.
  (import "snail.rust" "snail:open-output-file"
    (func (param $arguments i32) (result i32)))

  ;; [port] -> unspecified. Explicitly flushes/closes the resource. Repeated
  ;; close is harmless. Do not depend on GC finalization for build completion.
  (import "snail.rust" "snail:close-port"
    (func (param $arguments i32) (result i32)))

  ;; [optional status] -> does not return. Terminates this command; default/true
  ;; means 0, false means 1, and an integer status must be valid for the target.
  ;; This process-exit operation is not a browser or multi-actor shutdown
  ;; primitive.
  (import "snail.rust" "snail:exit"
    (func (param $arguments i32) (result i32)))

  ;; [name] -> string or false. Read an environment variable. Native strings
  ;; must be UTF-8; missing variables return false. No shell interpolation.
  (import "snail.rust" "snail:get-environment-variable"
    (func (param $arguments i32) (result i32)))

  ;; [argv-list, cwd, inherit-stdin?, argv0] -> integer status. Spawn and reap one
  ;; child without a shell. argv-list starts with its executable; argv0 selects
  ;; the identity seen by the child. Stdout/stderr and environment are inherited.
  ;; False stdin supplies EOF from /dev/null; build tools use this so the user
  ;; script's input remains untouched. Return exit status or 128+signal; those
  ;; encodings can overlap. Failure to launch is a terminal runtime error.
  ;; This blocking CLI convenience is not a GUI task or actor connection API.
  (import "snail.cli" "snail:%process-status"
    (func (param $arguments i32) (result i32)))

  ;; [path] -> absolute path string, relative to the caller's working directory.
  ;; Does not require the final file to exist or resolve symlinks.
  (import "snail.cli" "snail:%absolute-path"
    (func (param $arguments i32) (result i32)))

  ;; [first, second] -> boolean. Compare existing files by device/inode, following
  ;; symbolic links and recognizing hard links. Missing files return false;
  ;; other filesystem failures are errors. Used to protect build inputs.
  (import "snail.cli" "snail:%same-file?"
    (func (param $arguments i32) (result i32)))

  ;; [path] -> unspecified. Create a directory and missing parents; an existing
  ;; directory is accepted. Does not remove or replace existing files.
  (import "snail.cli" "snail:%create-directory*"
    (func (param $arguments i32) (result i32)))

  ;; [output-path or false] -> private directory path. Create beside the output
  ;; on the same filesystem, or in the OS temporary directory for execution.
  ;; Register ownership for cleanup and terminal-failure diagnostics. Fatal
  ;; runtime errors report retained paths; aborts and external kills may not.
  (import "snail.cli" "snail:%reserve-build-directory"
    (func (param $arguments i32) (result i32)))

  ;; [owned-directory] -> unspecified. Remove only a directory registered by
  ;; this invocation, then forget it. Removal failure warns without changing a
  ;; completed build's success; failed builds do not call this operation.
  (import "snail.cli" "snail:%clean-build-directory"
    (func (param $arguments i32) (result i32)))

  ;; [completed-file, output-path] -> unspecified. Rename the completed artifact
  ;; atomically over the destination. Build callers keep both on one filesystem;
  ;; failed compilation never reaches this operation. Rename failure retains
  ;; the previous output and the completed candidate.
  (import "snail.cli" "snail:%publish-file"
    (func (param $arguments i32) (result i32)))

  ;; ---- Handler required from the application ----

  ;; [] -> exit-status. Invoke once; its adapter initializes the Scheme program
  ;; and invokes the selected zero-argument handler. The returned Scheme exact
  ;; integer must be in 0..255; the launcher validates and transfers it to the OS.
  ;; For ordinary scripts the compiler
  ;; supplies this adapter, evaluates statements in order, and returns 0 on
  ;; normal completion. A trap/fatal runtime error produces a failing command
  ;; status and host-owned resource cleanup.
  (func (export "snail:main") (param $arguments i32) (result i32) unreachable)

)
