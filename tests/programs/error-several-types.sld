(import
 (snail core base)
 (snail core io))

;; Each definition and statement that fails to check is reported, in
;; source order, though `helper`, which has no signature, is checked
;; first. What uses `helper` is not checked: without its type, its
;; errors would only echo helper's own.
(define (label (n I64)) (→ String)
  (+ n 1))

(define helper
  (lambda (flag) (if flag (string-length flag) 0)))

(define uses-helper
  (lambda () (+ (helper #t) 1)))

(write-line (show (helper #t)))

(define (shout (text String)) (→ String)
  (string-append text #\!))

(write-line (shout (label 2)))
