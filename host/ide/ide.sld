;; The host entry for the shared IDE application.
(import
 (snail core base)
 (snail shell ui page)
 (snail shell ide application))

(define-ui Ide
  Msg
  (init: (lambda (seed) initial))
  (update: update)
  (view: view)
  (window: window)
  (start: (list (Boot) (Connect)))
  (save: kept)
  (restore: restored))
