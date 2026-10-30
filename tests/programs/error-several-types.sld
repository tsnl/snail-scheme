(import
 (snail core base)
 (snail core io))

;; Each definition and statement that fails to check is reported, in
;; source order, though `helper`, which has no signature, is checked
;; first. What uses `helper` is not checked: without its type, its
;; errors would only echo helper's own.
(: label (-> I64 String))
(define (label n)
  (+ n 1))

(define (helper flag)
  (if flag (string-length flag) 0))

(define (uses-helper)
  (+ (helper #t) 1))

(write-line (show (helper #t)))

(: shout (-> String String))
(define (shout text)
  (string-append text #\!))

(write-line (shout (label 2)))
