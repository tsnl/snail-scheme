(import
 (snail core base)
 (snail core io)
 (gradual describe))

(instance (Num (! dyn-tc) Any)
  (dispatch I64 F64))

(: describe-twice (All (T e) (requires (Describe e T) (Copy T)) (-> T String ! e)))
(define (describe-twice value)
  (string-append (describe value) (describe value)))

(: sum (All (T e) (requires (Num e T)) (-> T T T ! e)))
(define (sum a b) (+ a b))

(: left Any)
(define left 20)
(: right Any)
(define right 22)
(: word Any)
(define word "ok")
(: numbers Any)
(define numbers (list 1 2 3))

(display (sum 20 22))
(newline)

(handle dyn-tc
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (write-line (describe (sum left right)))
  (write-line (describe-twice word))
  (write-line (describe numbers))
  (display (ann (+ (ann 1.5 Any) (ann 2.5 Any)) F64))
  (newline))
