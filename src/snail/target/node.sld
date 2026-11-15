;; The node target: the handlers a program built with `--target node` runs
;; under. The build calls `provide` around the program's main, so an
;; effect it handles is one the program may perform. It handles none yet:
;; every capability still has its default, the host's implementation.
(define-library (snail target node)
  (export
   provide)
  (import
   (snail core base))
  (begin

    (define (provide (work (Fn → T ! e))) (→ T) (! e) (∀ (T e))
      (work))

    ))
