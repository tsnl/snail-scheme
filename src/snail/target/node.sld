;; The Node target: a program run on Node by host/native/run-snail.mjs.
;; `start` runs the program's main as the first task of the host's
;; scheduler. Main asks for capabilities by its parameters' types, and a
;; function here of no parameters provides the type it answers: those
;; every host has,
;;
;; - OutputPort, standard output;
;; - Clock, the monotonic clock;
;; - Resources, the files the program links;
;; - Wasm, the host's WebAssembly engine;
;;
;; and the local machine's:
;;
;; - InputPort, standard input;
;; - Fs, the file system;
;; - Files, whole-file reads that wait as a task;
;; - Processes, child processes;
;; - Signals, the termination signals sent to the program;
;; - Tcp and Udp, sockets.
(define-library (snail target node)
  (export
   start
   provide-output-port
   provide-clock
   provide-resources
   provide-wasm
   provide-input-port
   provide-fs
   provide-files
   provide-processes
   provide-signals
   provide-tcp
   provide-udp)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell async-files) Files host-files)
   (only (snail shell resource) Resources host-resources)
   (only (snail shell wasm) Wasm host-wasm)
   (only (snail shell process) Processes Signals host-processes host-signals)
   (only (snail shell socket) Tcp Udp host-tcp host-udp))
  (begin

    (define (start (scheduler Scheduler) (main (Fn → Unit ! tasks e))) (→ Unit) (! mut host e) (∀ (e))
      (dispatch-in scheduler main)
      (unit))

    ;; ---- What every host has ----

    (define (provide-output-port) (→ OutputPort)
      (standard-output))

    (define (provide-clock) (→ Clock)
      (host-clock))

    (define (provide-resources) (→ Resources)
      (host-resources))

    (define (provide-wasm) (→ Wasm)
      (host-wasm))

    ;; ---- The local machine ----

    (define (provide-input-port) (→ InputPort)
      (standard-input))

    (define (provide-fs) (→ Fs)
      (host-fs))

    (define (provide-files) (→ Files)
      (host-files))

    (define (provide-processes) (→ Processes)
      (host-processes))

    (define (provide-signals) (→ Signals)
      (host-signals))

    (define (provide-tcp) (→ Tcp)
      (host-tcp))

    (define (provide-udp) (→ Udp)
      (host-udp))

    ))
