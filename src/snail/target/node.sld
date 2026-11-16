;; The Node target: a program run on Node by host/native/run-snail.mjs.
;; `start` runs the program's main as the first task of the host's
;; scheduler, inside `provide`, which handles the capabilities every host
;; has,
;;
;; - output-port, standard output;
;; - clock, the monotonic clock;
;; - resource, the files the program links;
;; - wasm, the host's WebAssembly engine;
;;
;; and the local machine's:
;;
;; - input-port, standard input;
;; - fs, the file system;
;; - files, whole-file reads that wait as a task;
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
   (only (snail shell async-files) files provide-files)
   (only (snail shell resource) resource provide-resource)
   (only (snail shell wasm) wasm provide-wasm)
   (only (snail shell process) process signals provide-process provide-signals)
   (only (snail shell socket) tcp udp provide-tcp provide-udp))
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
      (provide-shared
       (lambda ()
         (provide-local
          (lambda ()
            (provide-process
             (lambda ()
               (provide-signals (lambda () (provide-tcp (lambda () (provide-udp work))))))))))))

    ;; What every host has.

    (define (provide-shared (work (Fn → T ! output-port clock resource wasm e)))
      (→ T)
      (! e)
      (∀ (T e))
      (provide-output-port
       (lambda ()
         (provide-clock (lambda () (provide-resource (lambda () (provide-wasm work))))))))

    ;; The local machine's input and files.

    (define (provide-local (work (Fn → T ! input-port fs files e))) (→ T) (! e) (∀ (T e))
      (provide-input-port (lambda () (provide-fs (lambda () (provide-files work))))))

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
