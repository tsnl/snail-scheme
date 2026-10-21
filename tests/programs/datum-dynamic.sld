;; Typed values cross into Scheme data and back through `Dynamic`: scalars,
;; collections, functions in both directions, and opaque values.
(import
 (lofi base)
 (lofi io)
 (lofi random)
 (lofi datum)
 (lofi write))

(define-opaque Random "random")

(: show-datum (All (T) (requires (Dynamic T)) (-> T Unit ! console)))
(define (show-datum value)
  (write-line (datum->string (to-datum value))))

(: call-datum (-> Datum (List Datum) Datum ! console mut))
(define (call-datum procedure arguments)
  (match procedure
    ((ProcedureDatum f) (f arguments))
    (_ (panic "not a procedure"))))

(: add (-> I64 I64 I64))
(define (add a b)
  (+ a b))

(: greet (-> String Unit ! console))
(define (greet name)
  (write-line (string-append "hello, " name)))

(show-datum 42)
(show-datum (ann 7 I32))
(show-datum 2.5)
(show-datum #\x)
(show-datum "text")
(show-datum (unit))
(show-datum (list 1 2 3))
(show-datum (list->vector (list "a" "b")))
(show-datum (Pair 1 (list #t #f)))
(show-datum (ann (Some 5) (Option I64)))
(show-datum (ann (None) (Option I64)))
(show-datum (make-random 7))

;; Typed values parse back out of data.
(display (+ 1 (ann (from-datum (to-datum 41)) I64)))
(newline)
(display (length (ann (from-datum (to-datum (list 1.0 2.0))) (List F64))))
(newline)
(display (random-below (from-datum (to-datum (make-random 7))) 1000))
(newline)

;; A typed function called as a procedure, effects and all.
(write-line (datum->string (call-datum (to-datum add) (list (to-datum 2) (to-datum 3)))))
(write-line (datum->string (call-datum (to-datum greet) (list (to-datum "notebook")))))

;; A procedure used as a typed function.
(: twice (-> (-> I64 I64) I64 I64))
(define (twice f x)
  (f (f x)))

(display (twice (from-datum (to-datum (lambda (n) (* n 10)))) 3))
(newline)

;; A datum that is not a value of the type stops at the boundary.
(display (ann (from-datum (to-datum "seven")) I64))
