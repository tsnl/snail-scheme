;; The wasmtime target: the handlers a program built with `--target wasmtime` runs
;; under. The build calls `start` with the host's scheduler and the
;; program's main, which runs as the scheduler's first task inside
;; `provide`, so an effect `provide` handles is one the program may
;; perform. It handles none yet: every capability still has its default,
;; the host's implementation.
(define-library (snail target wasmtime)
  (export
   provide
   start)
  (import
   (snail core base)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in))
  (begin

    (define (provide (work (Fn → T ! e))) (→ T) (! e) (∀ (T e))
      (work))

    (define (start (scheduler Scheduler) (main (Fn → Unit ! tasks e))) (→ Unit) (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
