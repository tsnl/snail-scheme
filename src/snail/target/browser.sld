;; The browser target: a page, run by host/browser. `start` runs the
;; program's main as the first task of the host's scheduler. Main asks for
;; what it needs by its parameters' types, and a function here of no
;; parameters provides the type it answers. The target holds the one
;; `Host` there is, `root`, and makes each of the host's capabilities from
;; it. What every host has:
;;
;; - Mut, to write with;
;; - Host, to make a capability later or not at all;
;; - Arguments and ProcessEnvironment, what the program was started with;
;; - OutputPort, the console;
;; - Clock, the monotonic clock;
;; - Resources, the files the program links;
;; - Wasm, the host's WebAssembly engine;
;;
;; and the page's:
;;
;; - Events, the page's input and its lifecycle;
;; - PageStorage, the page's saved state;
;; - Gpu, the page's WebGPU device;
;; - Dom, the page's document;
;; - Fetch, requests to a server;
;; - FilePicker, the files a user chooses.
(define-library (snail target browser)
  (export
   start
   provide-mut
   provide-host
   provide-arguments
   provide-environment
   provide-output-port
   provide-clock
   provide-resources
   provide-wasm
   provide-events
   provide-storage
   provide-gpu
   provide-dom
   provide-fetch
   provide-file-picker)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell task) Scheduler dispatch-in)
   (only (snail shell resource) Resources host-resources)
   (only (snail shell wasm) Wasm host-wasm)
   (only (snail shell page) Events PageStorage host-events host-storage)
   (only (snail shell gpu) Gpu host-gpu)
   (only (snail shell dom) Dom)
   (only (snail shell dom page) page-dom)
   (only (snail shell fetch) Fetch)
   (only (snail shell fetch page) page-fetch)
   (only (snail shell files) FilePicker)
   (only (snail shell files page) page-file-picker))
  (begin

    (define (start (scheduler Scheduler) (main (Fn → Unit))) (→ Unit)
      (dispatch-in scheduler main)
      (unit))

    ;; ---- What every host has ----

    ;; A program's `Mut` comes from here: main asks for one and hands it to
    ;; what should write.
    (define (provide-mut) (→ Mut)
      (unsafe-mut))

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

    (define (provide-wasm) (→ Wasm)
      (host-wasm root))

    ;; ---- The page ----

    (define (provide-events) (→ Events)
      (host-events root))

    (define (provide-storage) (→ PageStorage)
      (host-storage root))

    (define (provide-gpu) (→ Gpu)
      (host-gpu root))

    ;; The document delivers its events through the page's.
    (define (provide-dom) (→ Dom)
      (page-dom root (host-events root)))

    (define (provide-fetch) (→ Fetch)
      (page-fetch root))

    (define (provide-file-picker) (→ FilePicker)
      (page-file-picker root))

    ))
