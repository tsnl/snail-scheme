(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell watch))

;; Hints of a scratch tree: a write outside the excluded directory hints,
;; one inside it does not, and a closed watch answers a wait at once. The
;; writer prints before its write outside, 200 ms after the one inside, so
;; a hint for the write inside would print first.
(define (root) (→ String) "build/tests/watch-hints")

(define (at (name String)) (→ String)
  (string-append (root) "/" name))

(define (writer) (→ Unit) (! fs tasks output-port)
  (write-file (at "build/output") "out")
  (sleep 200)
  (write-line "writing outside")
  (write-file (at "src/main.sld") "main"))

(define (waiter (watch Watch)) (→ Unit) (! fs tasks output-port hints)
  (write-line (if (next-hint watch) "hinted" "closed"))
  (close-watch watch)
  (write-line (if (next-hint watch) "hinted" "closed"))
  (remove-tree (root))
  (unit))

(define (main) (→ Unit) (! host mut fs output-port tasks hints)
  (remove-tree (root))
  (make-directories (at "build"))
  (make-directories (at "src"))
  (match (watch-tree (root) (list (at "build")))
    ((Some watch)
     (dispatch-local (once (lambda () (writer))))
     (dispatch-local (once (lambda () (waiter watch)))))
    ((None) (write-line "cannot watch")))
  (unit))
