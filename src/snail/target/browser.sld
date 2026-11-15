;; The browser target: a page, run by host/browser. `start` runs the
;; program's main as the first task of the host's scheduler, inside
;; `provide`, which handles the portable target's capabilities. The page's
;; own, events, storage, the screen, the DOM and fetch, still have their
;; own defaults.
(define-library (snail target browser)
  (export
   provide
   start)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell resource) resource)
   (only (snail shell wasm) wasm)
   (prefix (snail target portable) portable:))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm e))) (→ T) (! e) (∀ (T e))
      (portable:provide work))

    (define (start (scheduler Scheduler)
                   (main (Fn → Unit ! tasks output-port clock resource wasm e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
