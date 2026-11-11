(import
 (snail core base)
 (snail core io)
 (snail core dynamic)
 (snail shell integer)
 (snail shell rational)
 (snail shell datum)
 (snail shell read)
 (snail shell write)
 (scheme runtime))

(struct Payload
  ((text String)))

(define (assert (condition Bool)) (→ Unit)
  (unless condition (panic "Scheme Any assertion failed")))

(define (reading (text String)) (→ Any)
  (match (read-datum text)
    ((Ok value) value)
    ((Err message) (panic message))))

;; Reader payloads are the actual Core types, with no scalar Datum wrappers.
(assert (type-test (reading "#t") Bool))
(assert (type-test (reading "#\\x") Char))
(assert (type-test (reading "\"text\"") String))
(assert (type-test (reading "name") Symbol))
(assert (type-test (reading "9223372036854775808") Integer))
(assert (type-test (reading "1/2") Rational))
(assert (type-test (reading "2/1") Integer))
(assert (type-test (reading "2.5") F64))
(assert (type-test (reading "#(1 #f)") (Vector Any)))
(assert (type-test (reading "#u8(0 255)") Bytes))
(assert (type-test (reading "()") Null))
(assert (type-test (reading "(1 . 2)") SchemePair))
(assert (datum-truthy? (reading "()")))
(assert (datum-truthy? (reading "0")))
(assert (not (datum-truthy? (reading "#f"))))
(assert (not (datum=? (reading "symbol") (reading "\"symbol\""))))

;; Byte syntax accepts exact integral literals, checking the range before
;; narrowing even when an integer is larger than a machine word.
(assert (datum=? (reading "#u8(0 2/1 255)") (reading "#u8(0 2 255)")))
(for-each
 (lambda (text)
   (match (read-datum text)
     ((Err _) (unit))
     ((Ok _) (panic "expected invalid bytevector"))))
 (list "#u8(-1)" "#u8(256)" "#u8(18446744073709551616)"
       "#u8(2.0)" "#u8(1/2)" "#u8(#t)" "#u8(1 . 2)"))

;; Vector equality compares nested values, lengths and numeric exactness.
(assert (datum=? (reading "#()") (reading "#()")))
(assert (datum=? (reading "#(1 #(symbol) (2 . 3))") (reading "#(1 #(symbol) (2 . 3))")))
(assert (not (datum=? (reading "#(1)") (reading "#(1 2)"))))
(assert (not (datum=? (reading "#(1 2)") (reading "#(1)"))))
(assert (not (datum=? (reading "#(1 2)") (reading "#(1 3)"))))
(assert (not (datum=? (reading "#(1)") (reading "#(1.0)"))))

;; A successful type probe with a failed ordinary pattern continues. The
;; expression runs once, and the selected body alone runs.
(let ((count (ref 0)))
  (assert (match-any (begin (ref-set! count (+ 1 (ref-get count))) (Symbol "yes"))
                     ((Symbol (Symbol "no")) (panic "wrong pattern"))
                     ((Symbol (Symbol "yes")) #t)
                     (else #f)))
  (assert (= (ref-get count) 1)))

(handle dyn-cast ((conversion-failed (lambda (error) (panic (cast-error->string error)))))
  (let* ((value (ann (Payload "native") Any))
         (pair (call (ref-get %cons) (list value (reading "()"))))
         (vector (call (ref-get %vector) (list value (reading "#f"))))
         (cell (ref (ann #f Any)))
         (procedure (ann (Procedure (lambda (arguments)
                                      (ann arguments (List Any))
                                      value)) Any)))
    (ref-set! cell pair)
    (assert (string=? (● (type-convert (call (ref-get %car) (list (ref-get cell))) Payload) text)
                      "native"))
    (assert
     (string=?
      (● (type-convert (call (ref-get %vector-ref) (list vector (reading "0"))) Payload) text)
      "native"))
    (assert (string=? (● (type-convert (call procedure (Nil)) Payload) text) "native"))
    (assert
     (string=?
      (● (type-convert (call (ref-get %apply) (list procedure (reading "()"))) Payload) text)
      "native"))
    (assert (string=? (datum->string value) "#<opaque>"))
    (assert (type-test (call (ref-get %number?) (list value)) Bool)))
  (let ((sum (call (ref-get %+) (list (reading "9223372036854775807") (reading "1"))))
        (ratio (call (ref-get %/) (list (reading "4") (reading "2")))))
    (assert (type-test sum Integer))
    (assert (string=? (integer->string sum) "9223372036854775808"))
    (assert (type-test ratio Rational))
    (assert (ann (call (ref-get %integer?) (list ratio)) Bool))
    (assert (string=? (datum->string ratio) "2"))
    (assert (datum=? ratio (reading "2")))
    (assert (type-test (call (ref-get %quotient) (list ratio (reading "2"))) Integer)))
  (assert (type-test (call (ref-get %+) (list (reading "1") (reading "2.5"))) F64))
  (assert (= (ann (call (ref-get %-) (list (reading "2.5") (reading "1"))) F64) 1.5))
  (assert (= (ann (call (ref-get %-) (list (reading "1") (reading "2.5"))) F64) -1.5))
  (assert (string=? (datum->string (call (ref-get %/) (list (reading "2")))) "1/2"))
  (assert (string=? (datum->string (call (ref-get %+) (Nil))) "0"))
  (assert (string=? (datum->string (call (ref-get %*) (Nil))) "1")))

;; Both concrete type checks and dynamic instance selection are catchable.
(for-each
 (lambda (work)
   (match (try-dynamic work)
     ((Ok _) (panic "expected dyn-cast failure"))
     ((Err _) (write-line "caught"))))
 (list (lambda () (call (ref-get %car) (list (reading "1"))))
       (lambda () (call (ref-get %+) (list (reading "1") (reading "#f"))))
       (lambda () (call (ref-get %length) (list (reading "(1 . 2)"))))
       (lambda () (call (reading "#f") (Nil)))
       (lambda () (call (ref-get %string-length) (list (reading "name"))))))
(write-line "Scheme Any interop passed")
