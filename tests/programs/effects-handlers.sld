(import
 (snail core base)
 (snail core io))

;; The examples of "Handlers" in the book's chapter on effects and
;; handlers, doc/book/snail-scheme/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: declare
(effect Log
  ((log (Fn String → Unit))))

;; Adds up prices, logging each one.
(define (total (prices (List I64))) (→ I64) (! Log)
  (fold-left (lambda (sum price)
               (log (string-append "adding " (show price)))
               (+ sum price))
             0 prices))

;; ANCHOR_END: handle

;; ANCHOR: quietly
;; Runs `action`, discarding what it logs.
(define (quietly (action (Fn → A ! Log e))) (→ A) (! e) (∀ (A e))
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

;; Total: the handler has removed Log.
(define (quiet-total (prices (List I64))) (→ I64)
  (quietly (lambda () (total prices))))

;; ANCHOR: indented
;; Indents what `action` logs: each implementation passes the line on to
;; the Log handler outside this one.
(define (indented (action (Fn → A ! Log e))) (→ A) (! Log e) (∀ (A e))
  (handle Log
      ((log (lambda (message) (log (string-append "  " message)))))
    (action)))

;; ANCHOR_END: indented

;; ANCHOR: files
(effect Files
  ((load (Fn String → String))))

(define (greeting (name String)) (→ String) (! Files)
  (string-append (load "greeting.txt") ", " name))

;; Files from the disk, under `build/`. `read-file` performs fs, which
;; goes to the handlers outside this one: here, the host.
(define (from-disk (fs Fs) (action (Fn → A ! Files e))) (→ A) (! mut e) (∀ (A e))
  (handle Files
      ((load (lambda (name) (read-file fs (string-append "build/" name)))))
    (action)))

;; A test double: files from memory, with no file system at all.
(define (from-memory (action (Fn → A ! Files e))) (→ A) (! e) (∀ (A e))
  (handle Files
      ((load (lambda (name) (if (string=? name "greeting.txt") "hello" ""))))
    (action)))

;; ANCHOR_END: run-files

;; ANCHOR: verbosity
;; How much to report, as the innermost handler says.
(effect Verbosity
  ((verbosity (Fn → I64))))

(define (note (out OutputPort) (level I64) (message String)) (→ Unit) (! Verbosity mut)
  (when (<= level (verbosity))
    (write-line out message)))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)

  ;; ANCHOR_END: declare

  ;; ANCHOR: handle
  (write-line out (show (handle Log
                        ((log (lambda (message) (write-line out message))))
                      (total (list 3 4)))))
  ;; ANCHOR_END: quietly

  (write-line out (show (quiet-total (list 1 2 3))))
  (handle Log
      ((log (lambda (message) (write-line out message))))
    (log "order")
    (indented (lambda ()
                (log (string-append "total " (show (total (list 3 4))))))))
  ;; ANCHOR_END: files

  ;; ANCHOR: run-files
  (write-file fs "build/greeting.txt" "bonjour")
  (write-line out (from-disk fs (lambda () (greeting "disk"))))
  (write-line out (from-memory (lambda () (greeting "memory"))))
  (handle Verbosity
      ((verbosity (lambda () 1)))
    (note out 1 "shown at level 1")
    (note out 2 "hidden at level 1")
    (handle Verbosity
        ((verbosity (lambda () 2)))
      (note out 2 "shown when verbose")))
  (unit))
