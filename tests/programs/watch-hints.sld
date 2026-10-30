(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell watch))

;; Hints of a scratch tree: a write outside the excluded directory hints,
;; one inside it does not, and a closed watch answers a wait at once. The
;; writer prints before its write outside, 200 ms after the one inside, so
;; a hint for the write inside would print first.
(define root "build/tests/watch-hints")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: writer (-> Unit ! fs tasks console))
(define (writer)
  (write-file (at "build/output") "out")
  (sleep 200)
  (write-line "writing outside")
  (write-file (at "src/main.sld") "main"))

(: waiter (-> Watch Unit ! fs tasks console hints))
(define (waiter watch)
  (write-line (if (next-hint watch) "hinted" "closed"))
  (close-watch watch)
  (write-line (if (next-hint watch) "hinted" "closed"))
  (remove-tree root)
  (unit))

(remove-tree root)
(make-directories (at "build"))
(make-directories (at "src"))
(match (watch-tree root (list (at "build")))
  ((Some watch)
   (dispatch-local (once (lambda () (writer))))
   (dispatch-local (once (lambda () (waiter watch)))))
  ((None) (write-line "cannot watch")))
