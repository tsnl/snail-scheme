;; The browser target: a page, run by host/browser. `start` runs the
;; program's main as the first task of the host's scheduler, inside
;; `provide`, which handles the capabilities every host has,
;;
;; - output-port, the console;
;; - clock, the monotonic clock;
;; - resource, the files the program links;
;; - wasm, the host's WebAssembly engine;
;;
;; and the page's:
;;
;; - events, the page's input and its lifecycle;
;; - storage, the page's saved state;
;; - gpu, the page's WebGPU device.
;;
;; The page's interface installs `dom` and `fetch` itself, with
;; `with-page-dom` and `with-page-fetch` ((snail shell ui page)), and a
;; scene installs `dom` for its HUD ((snail shell app)).
(define-library (snail target browser)
  (export
   provide
   start)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell resource) resource provide-resource)
   (only (snail shell wasm) wasm provide-wasm)
   (only (snail shell page) events storage provide-events provide-storage)
   (only (snail shell gpu) gpu provide-gpu))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm events storage gpu e)))
      (→ T)
      (! e)
      (∀ (T e))
      (provide-shared
       (lambda ()
         (provide-events
          (lambda ()
            (provide-storage (lambda () (provide-gpu work))))))))

    ;; What every host has.

    (define (provide-shared (work (Fn → T ! output-port clock resource wasm e)))
      (→ T)
      (! e)
      (∀ (T e))
      (provide-output-port
       (lambda ()
         (provide-clock (lambda () (provide-resource (lambda () (provide-wasm work))))))))

    (define (start (scheduler Scheduler)
                   (main
                    (Fn →
                        Unit
                        ! tasks output-port clock resource wasm events storage gpu e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
