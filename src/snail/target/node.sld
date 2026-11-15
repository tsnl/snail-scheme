;; The Node target: a program run on Node by host/native/run-snail.mjs.
;; `start` runs the program's main as the first task of the host's
;; scheduler, inside `provide`, which handles the wasmtime target's
;; capabilities and
;;
;; - process, child processes;
;; - signals, the termination signals sent to the program;
;; - tcp and udp, sockets.
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
   (only (snail shell process) process signals provide-process provide-signals)
   (only (snail shell socket) tcp udp provide-tcp provide-udp)
   (prefix (snail target wasmtime) wasmtime:))
  (begin

    (define (provide (work (Fn → T
                               !
                               output-port
                               clock
                               resource
                               wasm
                               input-port
                               fs
                               files
                               process
                               signals
                               tcp
                               udp
                               e)))
      (→ T)
      (! e)
      (∀ (T e))
      (wasmtime:provide
       (lambda ()
         (provide-process
          (lambda ()
            (provide-signals (lambda () (provide-tcp (lambda () (provide-udp work))))))))))

    (define (start (scheduler Scheduler)
                   (main (Fn → Unit
                             !
                             tasks
                             output-port
                             clock
                             resource
                             wasm
                             input-port
                             fs
                             files
                             process
                             signals
                             tcp
                             udp
                             e)))
      (→ Unit)
      (! mut host e)
      (∀ (e))
      (dispatch-in scheduler (lambda () (provide main)))
      (unit))

    ))
