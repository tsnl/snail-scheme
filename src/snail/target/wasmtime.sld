;; The wasmtime target: a program run by `snail run-wasm`, which needs of
;; its host only WASI, its files and the WebAssembly engine
;; (crates/snail). `start` runs the program's main as the first task of
;; the host's scheduler, inside `provide`, which handles the portable
;; target's capabilities and
;;
;; - input-port, standard input;
;; - fs, the file system;
;; - files, whole-file reads that wait as a task.
(define-library (snail target wasmtime)
  (export
   provide
   start)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) Scheduler tasks dispatch-in)
   (only (snail shell async-files) files provide-files)
   (only (snail shell resource) resource)
   (only (snail shell wasm) wasm)
   (prefix (snail target portable) portable:))
  (begin

    (define (provide (work (Fn → T ! output-port clock resource wasm input-port fs files e)))
      (→ T)
      (! e)
      (∀ (T e))
      (portable:provide
       (lambda () (provide-input-port (lambda () (provide-fs (lambda () (provide-files work))))))))

    (define (start (scheduler Scheduler)
                   (main (Fn → Unit ! tasks output-port clock resource wasm input-port fs files e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
