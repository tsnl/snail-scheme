(import
 (snail core base)
 (snail core io))

;; The examples of "Handlers" in the book's chapter on effects and
;; handlers, doc/book/snail-core/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: declare
(effect Log
  ((log (dyn (Fn String → Unit)))))

;; Adds up prices, logging each one.
(define (total (prices (List I64))) (→ I64) (! Log)
  (fold-left (lambda (sum price)
               (log (string-append "adding " (show price)))
               (+ sum price))
             0 prices))
;; ANCHOR_END: declare

;; ANCHOR: handle
(write-line (show (handle Log
                      ((log (lambda (message) (write-line message))))
                    (total (list 3 4)))))
;; ANCHOR_END: handle

;; ANCHOR: quietly
;; Runs `action`, discarding what it logs.
(define (quietly (action (dyn (Fn → A ! Log e)))) (→ A) (! e) (∀ A e)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

;; Total: the handler has removed Log.
(define (quiet-total (prices (List I64))) (→ I64)
  (quietly (lambda () (total prices))))
;; ANCHOR_END: quietly

(write-line (show (quiet-total (list 1 2 3))))

;; ANCHOR: indented
;; Indents what `action` logs: each implementation passes the line on to
;; the Log handler outside this one.
(define (indented (action (dyn (Fn → A ! Log e)))) (→ A) (! Log e) (∀ A e)
  (handle Log
      ((log (lambda (message) (log (string-append "  " message)))))
    (action)))

(handle Log
    ((log (lambda (message) (write-line message))))
  (log "order")
  (indented (lambda ()
              (log (string-append "total " (show (total (list 3 4))))))))
;; ANCHOR_END: indented

;; ANCHOR: files
(effect Files
  ((load (dyn (Fn String → String)))))

(define (greeting (name String)) (→ String) (! Files)
  (string-append (load "greeting.txt") ", " name))

;; Files from the disk, under `build/`. `read-file` performs fs, which
;; goes to the handlers outside this one: here, the host.
(define (from-disk (action (dyn (Fn → A ! Files e)))) (→ A) (! fs e) (∀ A e)
  (handle Files
      ((load (lambda (name) (read-file (string-append "build/" name)))))
    (action)))

;; A test double: files from memory, with no file system at all.
(define (from-memory (action (dyn (Fn → A ! Files e)))) (→ A) (! e) (∀ A e)
  (handle Files
      ((load (lambda (name) (if (string=? name "greeting.txt") "hello" ""))))
    (action)))
;; ANCHOR_END: files

;; ANCHOR: run-files
(write-file "build/greeting.txt" "bonjour")
(write-line (from-disk (lambda () (greeting "disk"))))
(write-line (from-memory (lambda () (greeting "memory"))))
;; ANCHOR_END: run-files

;; ANCHOR: default
;; How much to report: 1 unless a handler says otherwise.
(effect Verbosity
  ((verbosity (dyn (Fn → I64))))
  (default
    ((verbosity (lambda () 1)))))

(define (note (level I64) (message String)) (→ Unit) (! Verbosity output-port)
  (when (<= level (verbosity))
    (write-line message)))

(note 1 "shown by default")
(note 2 "hidden by default")
(handle Verbosity
    ((verbosity (lambda () 2)))
  (note 2 "shown when verbose"))
;; ANCHOR_END: default
