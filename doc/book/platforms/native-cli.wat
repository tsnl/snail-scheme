;; Native CLI -- proposed application interface, not implemented. Scheme
;; compiles through Wasm to native code and links the Rust runtime. The
;; platform owns command startup, OS IO, subprocesses, and resource teardown.
;;
;; Every call borrows an instance-local i32 root to an argument vector and
;; returns an owned result root. Brackets describe the Scheme arguments in that
;; vector. These are local AWI calls; actor connections serialize S-expressions
;; separately.
;;
;; The host initializes runtime/library globals before entry. Ordinary Scheme
;; scripts get a generated command adapter; no new entry-point syntax is
;; needed. Existing snail.rust signatures come from the Wasm runtime. Native
;; linking, snail.process/run, and snail:main still need implementation. Bodies
;; are stubs.
;;
;; The self-hosting acceptance case is a build.scm that chooses output paths,
;; builds snail-scheme, and then runs under that interpreter to rebuild it.
;; Blocking IO/process calls are suitable for this command profile. A server
;; can keep its command alive; GUI-thread use needs asynchronous services
;; instead.
(module

  ;; ---- Arguments and IO ----

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

  ;; ---- Build subprocesses ----

  ;; [executable, argv-list] -> process-outcome. Proposed blocking convenience
  ;; operation: inherit cwd, environment, and stdio, launch without a shell, and
  ;; wait for termination. The outcome distinguishes exited(status),
  ;; signalled(signal), and not-started(reason). Exact record syntax remains to
  ;; be designed with typed messages. Nonzero status is an outcome; the build
  ;; library decides whether to fail. Files already written are not rolled back.
  ;; Ownership lasts through reaping/cleanup. GUI/streaming process contracts and
  ;; cancellation need separate support.
  (import "snail.process" "run"
    (func (param $arguments i32) (result i32)))

  ;; ---- Command entry ----

  ;; [] -> exit-status. Invoke once after library initialization. The returned
  ;; Scheme exact integer must fit the supported OS status range; the launcher
  ;; validates and transfers it to the OS. For ordinary scripts the compiler
  ;; supplies this adapter, evaluates statements in order, and returns 0 on
  ;; normal completion. A trap/fatal runtime error produces a failing command
  ;; status and host-owned resource cleanup.
  (func (export "snail:main") (param $arguments i32) (result i32) unreachable)

)
