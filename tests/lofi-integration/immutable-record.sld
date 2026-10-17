(import
 (scheme base)
 (scheme immutable)
 (only (lofi core) data deriving ann I32)
 (only (lofi base) ref ref-get ref-set!))

(define-immutable-record Pair make-pair
  (left I32 left left-set)
  (right I32 right right-set))
(define calls (ref (ann 0 I32)))
(define-syntax count-derive
  (syntax-rules (data)
    ((_ (data Name () constructor ...))
     (ref-set! calls (+ (ref-get calls) 1)))))
(define-immutable-record Tagged make-tagged
  (first I32 first first-set)
  (second I32 second second-set)
  (deriving count-derive count-derive count-derive))
(let* ((prior (make-pair 10 20))
       (next (right-set (left-set prior 42) 7))
       (tagged (second-set (make-tagged 1 2) 3)))
  (if (and (= (left prior) 10) (= (right prior) 20)
           (= (left next) 42) (= (right next) 7)
           (= (first tagged) 1) (= (second tagged) 3)
           (= (ref-get calls) 3))
      42 0))
