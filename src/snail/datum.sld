;; Concrete runtime datums. Recursive data stays in Scheme; Rust receives only
;; scalar characters, number fields and owned temporary IDs, never Scheme roots.
(define-library (snail datum)
  (export Symbol string->symbol symbol->string symbol=?
          Scalar exact-scalar inexact-scalar scalar->f64 scalar-equivalent?
          Number exact-number inexact-number complex-number number->f64 number-equivalent?
          NumberResult not-a-number parsed-number number-error parsed-number-value number-error-text
          string->number identifier? datum-fail
          Datum datum-null datum-boolean datum-character datum-string datum-symbol datum-number
          datum-pair datum-vector datum-bytevector datum=? datum-cons datum-car datum-cdr
          datum-set-car! datum-set-cdr! datum-number? datum-number-value datum-string-value datum-symbol-value)
  (import (snail strict) (snail bytes))
  (begin

    ;; ---- Explicit scalar service ownership ----

    (define-extern token-open "snail.library" "snail:datum/token-open" (-> I32))
    (define-extern token-character "snail.library" "snail:datum/token-character" (-> I32 Char Unit))
    (define-extern token-close "snail.library" "snail:datum/token-close" (-> I32 Unit))
    (define-extern token-parse "snail.library" "snail:datum/token-parse" (-> I32 I32))
    (define-extern token-identifier "snail.library" "snail:datum/token-identifier" (-> I32 I32))
    (define-extern token-intern "snail.library" "snail:datum/token-intern" (-> I32 I32))
    (define-extern raw-number-kind "snail.library" "snail:datum/number-kind" (-> I32 I32 I32))
    (define-extern raw-number-integer "snail.library" "snail:datum/number-integer" (-> I32 I32 I64))
    (define-extern raw-number-real "snail.library" "snail:datum/number-real" (-> I32 I32 F64))
    (define-extern error-length "snail.library" "snail:datum/error-length" (-> I32 I32))
    (define-extern error-character "snail.library" "snail:datum/error-character" (-> I32 I32 Char))
    (define-extern raw-fail "snail.library" "snail:datum/fail" (-> I32 Unit))
    (define-extern symbol-length "snail.library" "snail:datum/symbol-length" (-> I32 I64))
    (define-extern symbol-character "snail.library" "snail:datum/symbol-character" (-> I32 I32 Char))
    (define-extern real-equivalent "snail.library" "snail:datum/real-equivalent" (-> F64 F64 I32))

    ;; The caller owns this ID until close or intern consumes it. These loops
    ;; invoke no user callbacks. Rust trap cleanup releases outstanding tokens.
    (: stage-text (-> String I32))
    (define (stage-text text)
      (let ((handle (token-open)) (count (string-length text)))
        (let loop ((index 0))
          (if (= index count) handle
              (begin (token-character handle (string-ref text index))
                     (loop (+ index 1)))))))
    (: datum-fail (-> String Never))
    (define (datum-fail message) (raw-fail (stage-text message)) (unreachable))
    (: identifier? (-> String Bool))
    (define (identifier? text)
      (let* ((handle (stage-text text)) (valid (token-identifier handle)))
        (token-close handle) (i32-eq valid (ann 1 I32))))

    ;; ---- Interned symbols, independent of the legacy literal domain ----

    (define-data Symbol (symbol (id I32 symbol-id)))
    (: string->symbol (-> String Symbol))
    (define (string->symbol text) (symbol (token-intern (stage-text text))))
    (: symbol=? (-> Symbol Symbol Bool))
    (define (symbol=? left right) (i32-eq (symbol-id left) (symbol-id right)))
    (: symbol->string (-> Symbol String))
    (define (symbol->string value)
      (let* ((id (symbol-id value)) (count (symbol-length id))
             (result (make-string count)))
        (let loop ((index 0))
          (if (= index count) result
              (begin (string-set! result index (symbol-character id (i64->i32 index)))
                     (loop (+ index 1)))))))

    ;; ---- Numbers preserve exactness and binary64 zero signs ----

    (define-data Scalar (exact-scalar (value I64)) (inexact-scalar (value F64)))
    (define-data Number (exact-number (value I64 exact-number-value))
      (inexact-number (value F64 inexact-number-value))
      (complex-number (real Scalar complex-real) (imaginary Scalar complex-imaginary)))
    (define-data NumberResult (not-a-number)
      (parsed-number (value Number parsed-number-value))
      (number-error (message String number-error-text)))
    (: scalar->f64 (-> Scalar F64))
    (define (scalar->f64 value)
      (match value ((exact-scalar value) (i64->f64 value)) ((inexact-scalar value) value)))
    (: number->f64 (-> Number F64))
    (define (number->f64 value)
      (match value
        ((exact-number value) (i64->f64 value)) ((inexact-number value) value)
        ((complex-number real imaginary)
         (if (= (scalar->f64 imaginary) 0.0) (scalar->f64 real)
             (datum-fail "number->f64: expected a real-valued number")))))
    (: token-scalar (-> I32 I32 Scalar))
    (define (token-scalar handle part)
      (if (i32-eq (raw-number-kind handle part) (ann 1 I32))
          (exact-scalar (raw-number-integer handle part))
          (inexact-scalar (raw-number-real handle part))))
    (: token-error-text (-> I32 String))
    (define (token-error-text handle)
      (let* ((count (i32->i64 (error-length handle))) (result (make-string count)))
        (let loop ((index 0))
          (if (= index count) result
              (begin (string-set! result index (error-character handle (i64->i32 index)))
                     (loop (+ index 1)))))))
    (: token-number-result (-> I32 I32 NumberResult))
    (define (token-number-result handle kind)
      (if (i32-eq kind (ann 0 I32)) (not-a-number)
          (if (i32-eq kind (ann 1 I32)) (parsed-number (exact-number (raw-number-integer handle (ann 0 I32))))
              (if (i32-eq kind (ann 2 I32)) (parsed-number (inexact-number (raw-number-real handle (ann 0 I32))))
                  (if (i32-eq kind (ann 3 I32))
                      (parsed-number (complex-number (token-scalar handle (ann 0 I32))
                                                     (token-scalar handle (ann 1 I32))))
                      (number-error (token-error-text handle)))))))
    (: string->number (-> String NumberResult))
    (define (string->number text)
      (let* ((handle (stage-text text)) (kind (token-parse handle))
             (result (token-number-result handle kind)))
        (token-close handle) result))

    ;; Equivalence follows the selected Chez contract: exact/inexact differ,
    ;; signed zeros differ, all NaNs are equivalent, and infinities keep sign.
    (: scalar-equivalent? (-> Scalar Scalar Bool))
    (define (scalar-equivalent? left right)
      (match left
        ((exact-scalar left) (match right ((exact-scalar right) (= left right)) ((inexact-scalar right) #f)))
        ((inexact-scalar left) (match right
                                 ((inexact-scalar right) (i32-eq (real-equivalent left right) (ann 1 I32))) ((exact-scalar right) #f)))))
    (: number-kind (-> Number I64))
    (define (number-kind value)
      (match value ((exact-number value) 0) ((inexact-number value) 1) ((complex-number real imaginary) 2)))
    (: number-equivalent? (-> Number Number Bool))
    (define (number-equivalent? left right)
      (and (= (number-kind left) (number-kind right))
           (match left
             ((exact-number left) (= left (exact-number-value right)))
             ((inexact-number left) (i32-eq (real-equivalent left (inexact-number-value right)) (ann 1 I32)))
             ((complex-number real imaginary)
              (and (scalar-equivalent? real (complex-real right))
                   (scalar-equivalent? imaginary (complex-imaginary right)))))))

    ;; ---- Recursive datums and explicit mutable pair fields ----

    (define-data Datum
      (datum-null) (datum-boolean (value Bool datum-boolean-value))
      (datum-character (value Char datum-character-value))
      (datum-string (value String datum-string-value))
      (datum-symbol (value Symbol datum-symbol-value))
      (datum-number (value Number datum-number-value))
      (datum-pair (first (Ref Datum) datum-first) (rest (Ref Datum) datum-rest))
      (datum-vector (values (Vector Datum) datum-vector-values))
      (datum-bytevector (values Bytevector datum-bytevector-values)))
    (: datum-cons (-> Datum Datum Datum))
    (define (datum-cons first rest) (datum-pair (ref first) (ref rest)))
    (: datum-car (-> Datum Datum))
    (define (datum-car pair) (ref-get (datum-first pair)))
    (: datum-cdr (-> Datum Datum))
    (define (datum-cdr pair) (ref-get (datum-rest pair)))
    (: datum-set-car! (-> Datum Datum Unit))
    (define (datum-set-car! pair value) (ref-set! (datum-first pair) value))
    (: datum-set-cdr! (-> Datum Datum Unit))
    (define (datum-set-cdr! pair value) (ref-set! (datum-rest pair) value))
    (: datum-kind (-> Datum I64))
    (define (datum-kind value)
      (match value
        ((datum-null) 0) ((datum-boolean value) 1) ((datum-character value) 2)
        ((datum-string value) 3) ((datum-symbol value) 4) ((datum-number value) 5)
        ((datum-pair first rest) 6) ((datum-vector values) 7) ((datum-bytevector values) 8)))
    (: datum-number? (-> Datum Bool))
    (define (datum-number? value) (= (datum-kind value) 5))

    ;; Finite acyclic structural equality. Mutation can create cycles, but
    ;; cycle-aware equality and datum-label input are outside this API contract.
    ;; The exhaustive dispatch keeps each representation's equality visible.
    (: datum=? (-> Datum Datum Bool))
    (define (datum=? left right)
      (and (= (datum-kind left) (datum-kind right))
           (match left
             ((datum-null) #t)
             ((datum-boolean left) (if left (datum-boolean-value right) (not (datum-boolean-value right))))
             ((datum-character left) (char=? left (datum-character-value right)))
             ((datum-string left) (string=? left (datum-string-value right)))
             ((datum-symbol left) (symbol=? left (datum-symbol-value right)))
             ((datum-number left) (number-equivalent? left (datum-number-value right)))
             ((datum-pair first rest)
              (and (datum=? (ref-get first) (datum-car right)) (datum=? (ref-get rest) (datum-cdr right))))
             ((datum-vector left) (datum-vector=? left (datum-vector-values right)))
             ((datum-bytevector left) (datum-bytes=? left (datum-bytevector-values right))))))
    (: datum-vector=? (-> (Vector Datum) (Vector Datum) Bool))
    (define (datum-vector=? left right)
      (let ((count (vector-length left)))
        (and (= count (vector-length right))
             (let loop ((index 0))
               (or (= index count)
                   (and (datum=? (vector-ref left index) (vector-ref right index)) (loop (+ index 1))))))))
    (: datum-bytes=? (-> Bytevector Bytevector Bool))
    (define (datum-bytes=? left right)
      (let ((count (bytevector-length left)))
        (and (= count (bytevector-length right))
             (let loop ((index 0))
               (or (= index count)
                   (and (= (bytevector-u8-ref left index) (bytevector-u8-ref right index))
                        (loop (+ index 1))))))))))
