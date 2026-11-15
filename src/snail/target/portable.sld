;; The portable target: the capabilities every host has, which the other
;; targets build on. A program built with `--target portable` runs on any
;; of them. `start` runs the program's main as the first task of the
;; host's scheduler, inside `provide`, which handles
;;
;; - output-port, standard output;
;; - clock, the monotonic clock;
;; - resource, the files the program links;
;; - wasm, the host's WebAssembly engine.
(define-library (snail target portable)
  (export
   provide
   start)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell resource) resource provide-resource)
   (only (snail shell wasm) wasm provide-wasm))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm e))) (→ T) (! e) (∀ (T e))
      (provide-output-port
       (lambda ()
         (provide-clock (lambda () (provide-resource (lambda () (provide-wasm work))))))))

    (define (start (scheduler Scheduler)
                   (main (Fn → Unit ! tasks output-port clock resource wasm e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
