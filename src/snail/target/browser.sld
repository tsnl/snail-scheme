;; The browser target: a page, run by host/browser. `start` runs the
;; program's main as the first task of the host's scheduler. Main asks for
;; capabilities by its parameters' types, and a function here of no
;; parameters provides the type it answers: those every host has,
;;
;; - OutputPort, the console;
;; - Clock, the monotonic clock;
;; - Resources, the files the program links;
;; - Wasm, the host's WebAssembly engine;
;;
;; and the page's:
;;
;; - Events, the page's input and its lifecycle;
;; - Storage, the page's saved state;
;; - Gpu, the page's WebGPU device.
;;
;; A page's interface makes its own `Dom` and `Fetch` from these, with
;; `page-dom` and `page-fetch` ((snail shell ui page)), and a scene makes
;; a `Dom` for its HUD ((snail shell app)).
(define-library (snail target browser)
  (export
   start
   provide-output-port
   provide-clock
   provide-resources
   provide-wasm
   provide-events
   provide-storage
   provide-gpu)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell task) Scheduler dispatch-in)
   (only (snail shell resource) Resources host-resources)
   (only (snail shell wasm) Wasm host-wasm)
   (only (snail shell page) Events PageStorage host-events host-storage)
   (only (snail shell gpu) Gpu host-gpu))
  (begin

    (define (start (scheduler Scheduler) (main (Fn → Unit ! mut))) (→ Unit) (! mut)
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

    ;; ---- The page ----

    (define (provide-events) (→ Events)
      (host-events))

    (define (provide-storage) (→ PageStorage)
      (host-storage))

    (define (provide-gpu) (→ Gpu)
      (host-gpu))

    ))
