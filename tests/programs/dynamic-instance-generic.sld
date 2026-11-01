(import
 (snail core base)
 (snail core io)
 (gradual describe))

(struct (Wrapper T)
  ((value T)))

;; The instance's row comes from its requirement. It must survive in the
;; evidence and in the specialization, even though it used to be erased
;; when class instances could perform only ordinary effects.
(instance (Describe (! e) (Wrapper T))
  (requires (Describe e T))
  (define (describe wrapper)
    (match wrapper ((Wrapper value) (describe value)))))

(: twice (All (T e) (requires (Describe e T) (Copy T)) (-> T String ! e)))
(define (twice value) (string-append (describe value) (describe value)))

(write-line (twice (Wrapper 7)))
(handle dyn-tc ((conversion-failed (lambda (_) (write-line "caught generic instance"))))
  (write-line (twice (Wrapper (ann "ok" Any))))
  (write-line (twice (Wrapper (ann #t Any))))
  (write-line "unreachable"))

;; The core's generic Show instance similarly propagates its element's row.
(instance (Show (! dyn-tc) Any) (dispatch I64 String))
(handle dyn-tc ((conversion-failed (lambda (_) (write-line "caught list show"))))
  (write-line (show (list (ann 7 Any) (ann "ok" Any))))
  (write-line (show (list (ann #t Any)))))
