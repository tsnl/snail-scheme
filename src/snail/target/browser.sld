;; The browser target: a page, run by host/browser. `start` runs the
;; program's main as the first task of the host's scheduler, inside
;; `provide`, which handles the portable target's capabilities and
;;
;; - events, the page's input and its lifecycle;
;; - storage, the page's saved state;
;; - screen, the page's canvas.
;;
;; The page's interface installs `dom` and `fetch` itself, with
;; `with-page-dom` and `with-page-fetch` ((snail shell ui page)).
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
   (only (snail shell page) events storage provide-events provide-storage)
   (only (snail shell app) screen provide-screen)
   (prefix (snail target portable) portable:))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm events storage screen e)))
      (→ T)
      (! e)
      (∀ (T e))
      (portable:provide
       (lambda ()
         (provide-events (lambda () (provide-storage (lambda () (provide-screen work))))))))

    (define (start (scheduler Scheduler)
                   (main
                    (Fn → Unit ! tasks output-port clock resource wasm events storage screen e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
