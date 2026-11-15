;; The Node target: a program run on Node by host/native/run-snail.mjs.
;; `start` runs the program's main as the first task of the host's
;; scheduler, inside `provide`, which handles the wasmtime target's
;; capabilities. Processes, signals and sockets still have their own
;; defaults.
(define-library (snail target node)
  (export
   provide
   start)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell async-files) files)
   (only (snail shell resource) resource)
   (only (snail shell wasm) wasm)
   (prefix (snail target wasmtime) wasmtime:))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm input-port fs files e)))
      (→ T)
      (! e)
      (∀ (T e))
      (wasmtime:provide work))

    (define (start (scheduler Scheduler)
                   (main (Fn → Unit ! tasks output-port clock resource wasm input-port fs files e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
