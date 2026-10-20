(import
 (lofi core)
 (lofi base))

(def state (ref (ann 0 I32)))
(def stamp (-> I32 Unit)
     (lambda (value) (ref-set! state (+ (* (ref-get state) 10) value))))
(data Token ()
  (token
   (derive-second I32 token-value))
  (deriving derive-first derive-second late))
(define-syntax derive-first
     (syntax-rules (data)
       ((_ (data Name ()
             (constructor
              (next Type accessor))))
        (define-syntax next (syntax-rules () ((_ declaration) (stamp 1)))))))
(define-syntax install-late
     (syntax-rules ()
       ((_ name)
        (begin
         (begin
           (define-syntax name (syntax-rules () ((_ declaration) (stamp 2)))))))))
(install-late late)
(ref-get state)
