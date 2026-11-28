;; The Node target: a program run on Node by host/native/run-snail.mjs.
;; `start` runs the program's main as the first task of the host's
;; scheduler. Main asks for what it needs by its parameters' types, and a
;; function here of no parameters provides the type it answers. The target
;; holds the one `Host` there is, `root`, and makes each of the host's
;; capabilities from it. What every host has:
;;
;; - Host, to make a capability later or not at all, as a program that
;;   draws makes its `Gpu` ((snail shell gpu));
;; - Arguments and ProcessEnvironment, what the program was started with;
;; - OutputPort, standard output;
;; - Clock, the monotonic clock;
;; - Resources, the files the program links;
;;
;; and the local machine's:
;;
;; - InputPort, standard input;
;; - Fs, the file system;
;; - Files, whole-file reads that wait as a task;
;; - Processes, child processes;
;; - Signals, the termination signals sent to the program;
;; - Tcp and Udp, sockets;
;; - Web, the files at URLs, a part at a time.
(define-library (snail target node)
  (export
   start
   provide-host
   provide-arguments
   provide-environment
   provide-output-port
   provide-clock
   provide-resources
   provide-input-port
   provide-fs
   provide-files
   provide-processes
   provide-signals
   provide-tcp
   provide-udp
   provide-web)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell task) Scheduler dispatch-in)
   (only (snail shell async-files) Files host-files)
   (only (snail shell resource) Resources host-resources)
   (only (snail shell process) Processes Signals host-processes host-signals)
   (only (snail shell socket) Tcp Udp host-tcp host-udp)
   (only (snail shell web) Web host-web))
  (begin

    (define (start (scheduler Scheduler) (main (Fn → Unit))) (→ Unit)
      (dispatch-in scheduler main)
      (unit))

    ;; ---- What every host has ----

    ;; The one `Host`: what makes every capability below.
    (define root (→ Host) (unsafe-host))

    (define (provide-host) (→ Host)
      root)

    (define (provide-arguments) (→ Arguments)
      (host-arguments root))

    (define (provide-environment) (→ ProcessEnvironment)
      (host-environment root))

    (define (provide-output-port) (→ OutputPort)
      (standard-output root))

    (define (provide-clock) (→ Clock)
      (host-clock root))

    (define (provide-resources) (→ Resources)
      (host-resources root))


    ;; ---- The local machine ----

    (define (provide-input-port) (→ InputPort)
      (standard-input root))

    (define (provide-fs) (→ Fs)
      (host-fs root))

    (define (provide-files) (→ Files)
      (host-files root))

    (define (provide-processes) (→ Processes)
      (host-processes root))

    (define (provide-signals) (→ Signals)
      (host-signals root))

    (define (provide-tcp) (→ Tcp)
      (host-tcp root))

    (define (provide-udp) (→ Udp)
      (host-udp root))

    (define (provide-web) (→ Web)
      (host-web root))

    ))
