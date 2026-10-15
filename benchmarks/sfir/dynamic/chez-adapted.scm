;; Explicit-representation control authored from the static SFIR program.
;; The source algorithm, staged bindings, Value tags, mutable links and concrete
;; Procedure cases are identical. Chez supplies its native numeric tower and I/O;
;; the SFIR target instead uses its ordinary Integer/Rational/Number libraries.
(import (except (chezscheme) symbol=? string-copy! vector-copy! open-output-file call-with-output-file number->string string->number read read-char peek-char) (prefix (chezscheme) host:))
(define debug-source-stack (make-parameter '()))

;; ---- Native services implement the same typed boundary contracts ----
(define (unit) (void))
(define (unreachable) (error 'sfir "unreachable"))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define string-eq? eq?)
(define vector-eq? eq?)
(define bytevector-eq? eq?)
(define symbol=? eq?)
(define output-port=? eq?)
(define (empty-vector) (vector))
(define (i64->i32 value) value)
(define (i32->i64 value) value)
(define (i64->f64 value) (inexact value))
(define (f64->i64 value) (exact (truncate value)))
(define (string-copy! to start from low high)
 (let loop ((index low) (at start))
  (unless (= index high) (string-set! to at (string-ref from index)) (loop (+ index 1) (+ at 1)))))
(define (vector-copy! to start from low high)
 (let loop ((index low) (at start))
  (unless (= index high) (vector-set! to at (vector-ref from index)) (loop (+ index 1) (+ at 1)))))
(define (open-output-file file)
 (host:open-file-output-port file (host:file-options no-fail) (host:buffer-mode block) (host:native-transcoder)))
(define (call-with-output-file file procedure)
 (let* ((port (open-output-file file)) (result (procedure port))) (close-output-port port) result))
(define (datum-fail message) (error 'sfir message))
(define (exact-number x) x)
(define (rational-number x) x)
(define (inexact-number x) x)
(define (exact-scalar x) x)
(define (rational-scalar x) x)
(define (inexact-scalar x) x)
(define (scalar-from-rational x) x)
(define (number-from-scalar x) x)
(define complex-number make-rectangular)
(define number-rectangular make-rectangular)
(define number->f64 inexact)
(define (number->integer x) (unless (and (exact? x) (integer? x)) (error 'number->integer "exact integer required")) x)
(define (number->rational x) (unless (rational? x) (error 'number->rational "real finite value required")) (exact x))
(define (number-from-integer x) x)
(define (number-from-rational x) x)
(define number->string host:number->string)
(define number-equivalent? eqv?)
(define number-exact? exact?)
(define number-real? real?)
(define number-integer? integer?)
(define number-rational? rational?)
(define (number-exact-integer? x) (and (exact? x) (integer? x)))
(define number-zero? zero?)
(define number-negative? negative?)
(define number-abs abs)
(define number-negate -)
(define number-add +)
(define number-subtract -)
(define number-multiply *)
(define number-divide /)
(define number=? =)
(define number<? <)
(define number<=? <=)
(define number>? >)
(define number>=? >=)
(define number-numerator numerator)
(define number-denominator denominator)
(define number-real-part real-part)
(define number-imag-part imag-part)
(define number-exact exact)
(define number-inexact inexact)
(define number-truncate truncate)
(define rational-from-f64 exact)
(define rational-numerator numerator)
(define rational-denominator denominator)
(define rational-integer? integer?)
(define rational-floor floor)
(define make-rational /)
(define (integer-from-i64 x) x)
(define (integer->i64 x) (unless (<= (- (expt 2 63)) x (- (expt 2 63) 1)) (error 'integer->i64 "out of range")) x)
(define integer-zero? zero?)
(define integer-negative? negative?)
(define integer-abs abs)
(define integer-negate -)
(define integer-add +)
(define integer-multiply *)
(define integer-quotient quotient)
(define integer-remainder remainder)
(define integer-gcd gcd)
(define-record-type (division-record division division?) (fields (immutable quotient division-quotient) (immutable remainder division-remainder)))
(define (integer-divide a b) (division (quotient a b) (remainder a b)))
(define-record-type (root-record root root?) (fields (immutable value root-value) (immutable remainder root-remainder)))
(define (integer-sqrt/remainder x) (call-with-values (lambda () (exact-integer-sqrt x)) root))
(define atan2 atan)
(define pow expt)
(define-record-type (number-parsed-record parsed-number is-parsed-number) (fields (immutable value parsed-number-value)))
(define-record-type (number-absent-record not-a-number is-not-a-number) (fields))
(define-record-type (number-error-record number-error is-number-error) (fields (immutable message number-error-text)))
(define (string->number text) (let ((result (host:string->number text))) (if result (parsed-number result) (not-a-number))))
(define (string->number/radix text radix) (let ((result (host:string->number text radix))) (if result (parsed-number result) (not-a-number))))
(define-record-type (read-end-record read-end is-read-end) (fields))
(define-record-type (read-value-record read-value is-read-value) (fields (immutable datum read-value-datum)))
(define-record-type (read-error-record read-error is-read-error) (fields (immutable message read-error-message)))
(define (read port) (let ((datum (host:read port))) (if (eof-object? datum) (read-end) (read-value datum))))
(define (read-value! result) (if (is-read-value result) (read-value-datum result) (error 'read "missing canonical datum")))
(define-record-type (character-end-record character-end is-character-end) (fields))
(define-record-type (character-value-record character-value is-character-value) (fields (immutable character character-value-character)))
(define (read-char port) (let ((c (host:read-char port))) (if (eof-object? c) (character-end) (character-value c))))
(define (peek-char port) (let ((c (host:peek-char port))) (if (eof-object? c) (character-end) (character-value c))))
(define (datum-kind x) (cond ((null? x) 0) ((boolean? x) 1) ((char? x) 2) ((string? x) 3) ((symbol? x) 4) ((number? x) 5) ((pair? x) 6) ((vector? x) 7) ((bytevector? x) 8) (else (error 'datum-kind "unknown datum"))))
(define (datum-null) '())
(define (datum-boolean x) x)
(define (datum-character x) x)
(define (datum-string x) x)
(define (datum-symbol x) x)
(define (datum-number x) x)
(define (datum-vector x) x)
(define (datum-bytevector x) x)
(define (datum-boolean-value x) x)
(define (datum-character-value x) x)
(define (datum-string-value x) x)
(define (datum-symbol-value x) x)
(define (datum-number-value x) x)
(define (datum-vector-values x) x)
(define (datum-bytevector-values x) x)
(define datum-cons cons)
(define datum-car car)
(define datum-cdr cdr)
(define datum-set-car! set-car!)
(define datum-set-cdr! set-cdr!)
(define datum-eq? eqv?)
(begin
  (host:define-record-type (value-null/record value-null is-value-null) (fields))
  (host:define-record-type
    (value-boolean/record value-boolean is-value-boolean)
    (fields (immutable boolean value-boolean-boolean)))
  (host:define-record-type
    (value-character/record value-character is-value-character)
    (fields (immutable character value-character-character)))
  (host:define-record-type
    (value-string/record value-string is-value-string)
    (fields (immutable string value-string-string)))
  (host:define-record-type
    (value-symbol/record value-symbol is-value-symbol)
    (fields (immutable symbol value-symbol-symbol)))
  (host:define-record-type
    (value-number/record value-number is-value-number)
    (fields (immutable number value-number-number)))
  (host:define-record-type
    (value-pair/record value-pair is-value-pair)
    (fields (immutable first value-pair-first) (immutable rest value-pair-rest)))
  (host:define-record-type
    (value-vector/record value-vector is-value-vector)
    (fields (immutable vector value-vector-vector)))
  (host:define-record-type
    (value-bytevector/record value-bytevector is-value-bytevector)
    (fields (immutable bytes value-bytevector-bytes)))
  (host:define-record-type
    (value-input/record value-input is-value-input)
    (fields (immutable identity value-input-identity) (immutable port value-input-port)))
  (host:define-record-type
    (value-output/record value-output is-value-output)
    (fields (immutable port value-output-port)))
  (host:define-record-type
    (value-procedure/record value-procedure is-value-procedure)
    (fields
      (immutable identity value-procedure-identity)
      (immutable procedure value-procedure-procedure)))
  (host:define-record-type (value-eof/record value-eof is-value-eof) (fields))
  (host:define-record-type
    (value-unspecified/record value-unspecified is-value-unspecified)
    (fields))
  (host:define-record-type
    (value-uninitialized/record value-uninitialized is-value-uninitialized)
    (fields)))

(begin
  (host:define-record-type
    (function-0/record function-0 is-function-0)
    (fields (immutable body function-0-body)))
  (host:define-record-type
    (function-1/record function-1 is-function-1)
    (fields (immutable body function-1-body)))
  (host:define-record-type
    (function-2/record function-2 is-function-2)
    (fields (immutable body function-2-body)))
  (host:define-record-type
    (function-3/record function-3 is-function-3)
    (fields (immutable body function-3-body)))
  (host:define-record-type
    (function-4/record function-4 is-function-4)
    (fields (immutable body function-4-body)))
  (host:define-record-type
    (function-5/record function-5 is-function-5)
    (fields (immutable body function-5-body))))

(define value-kind
  (lambda (value)
    (let ((matched-value.2 value))
      (cond
        ((is-value-null matched-value.2) (let () 0))
        ((is-value-boolean matched-value.2)
          (let ((boolean (value-boolean-boolean matched-value.2))) 1))
        ((is-value-character matched-value.2)
          (let ((character (value-character-character matched-value.2))) 2))
        ((is-value-string matched-value.2) (let ((string (value-string-string matched-value.2))) 3))
        ((is-value-symbol matched-value.2) (let ((symbol (value-symbol-symbol matched-value.2))) 4))
        ((is-value-number matched-value.2) (let ((number (value-number-number matched-value.2))) 5))
        ((is-value-pair matched-value.2)
          (let ((first (value-pair-first matched-value.2)) (rest (value-pair-rest matched-value.2)))
            6))
        ((is-value-vector matched-value.2) (let ((vector (value-vector-vector matched-value.2))) 7))
        ((is-value-bytevector matched-value.2)
          (let ((bytes (value-bytevector-bytes matched-value.2))) 8))
        ((is-value-input matched-value.2)
          (let ((identity (value-input-identity matched-value.2)) (port (value-input-port matched-value.2)))
            9))
        ((is-value-output matched-value.2) (let ((port (value-output-port matched-value.2))) 10))
        ((is-value-procedure matched-value.2)
          (let ((identity (value-procedure-identity matched-value.2)) (procedure (value-procedure-procedure matched-value.2)))
            11))
        ((is-value-eof matched-value.2) (let () 12))
        ((is-value-unspecified matched-value.2) (let () 13))
        ((is-value-uninitialized matched-value.2) (let () 14))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            2
            (debug-source-stack)
            (if (host:record? matched-value.2)
              (host:record-type-name (host:record-rtd matched-value.2))
              "nonrecord")))))))

(define binding-value
  (lambda (cell)
    (let ((value (ref-get cell)))
      (if (value-uninitialized? value) (datum-fail "binding read before initialization") value))))

(define value-truth?
  (lambda (value)
    (let ((matched-value.4 value))
      (cond
        ((is-value-null matched-value.4) (let () #t))
        ((is-value-boolean matched-value.4)
          (let ((boolean (value-boolean-boolean matched-value.4))) boolean))
        ((is-value-character matched-value.4)
          (let ((character (value-character-character matched-value.4))) #t))
        ((is-value-string matched-value.4)
          (let ((string (value-string-string matched-value.4))) #t))
        ((is-value-symbol matched-value.4)
          (let ((symbol (value-symbol-symbol matched-value.4))) #t))
        ((is-value-number matched-value.4)
          (let ((number (value-number-number matched-value.4))) #t))
        ((is-value-pair matched-value.4)
          (let ((first (value-pair-first matched-value.4)) (rest (value-pair-rest matched-value.4)))
            #t))
        ((is-value-vector matched-value.4)
          (let ((vector (value-vector-vector matched-value.4))) #t))
        ((is-value-bytevector matched-value.4)
          (let ((bytes (value-bytevector-bytes matched-value.4))) #t))
        ((is-value-input matched-value.4)
          (let ((identity (value-input-identity matched-value.4)) (port (value-input-port matched-value.4)))
            #t))
        ((is-value-output matched-value.4) (let ((port (value-output-port matched-value.4))) #t))
        ((is-value-procedure matched-value.4)
          (let ((identity (value-procedure-identity matched-value.4)) (procedure (value-procedure-procedure matched-value.4)))
            #t))
        ((is-value-eof matched-value.4) (let () #t))
        ((is-value-unspecified matched-value.4) (let () #t))
        ((is-value-uninitialized matched-value.4) (let () #t))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            4
            (debug-source-stack)
            (if (host:record? matched-value.4)
              (host:record-type-name (host:record-rtd matched-value.4))
              "nonrecord")))))))

(define value-null? (lambda (value) (= (value-kind value) 0)))

(define value-boolean? (lambda (value) (= (value-kind value) 1)))

(define value-character? (lambda (value) (= (value-kind value) 2)))

(define value-string? (lambda (value) (= (value-kind value) 3)))

(define value-symbol? (lambda (value) (= (value-kind value) 4)))

(define value-number? (lambda (value) (= (value-kind value) 5)))

(define value-pair? (lambda (value) (= (value-kind value) 6)))

(define value-vector? (lambda (value) (= (value-kind value) 7)))

(define value-bytevector? (lambda (value) (= (value-kind value) 8)))

(define value-input? (lambda (value) (= (value-kind value) 9)))

(define value-output? (lambda (value) (= (value-kind value) 10)))

(define value-procedure? (lambda (value) (= (value-kind value) 11)))

(define value-eof? (lambda (value) (= (value-kind value) 12)))

(define value-unspecified? (lambda (value) (= (value-kind value) 13)))

(define value-uninitialized? (lambda (value) (= (value-kind value) 14)))

(define value-cons (lambda (first rest) (value-pair (ref first) (ref rest))))

(define value-car (lambda (pair) (ref-get (value-pair-first pair))))

(define value-cdr (lambda (pair) (ref-get (value-pair-rest pair))))

(define value-eq?
  (lambda (left right)
    (if (= (value-kind left) (value-kind right))
      (let ((matched-value.6 left))
        (cond
          ((is-value-null matched-value.6) (let () #t))
          ((is-value-boolean matched-value.6)
            (let ((boolean (value-boolean-boolean matched-value.6)))
              (if boolean (value-boolean-boolean right) (not (value-boolean-boolean right)))))
          ((is-value-character matched-value.6)
            (let ((character (value-character-character matched-value.6)))
              (char=? character (value-character-character right))))
          ((is-value-string matched-value.6)
            (let ((string (value-string-string matched-value.6)))
              (string-eq? string (value-string-string right))))
          ((is-value-symbol matched-value.6)
            (let ((symbol (value-symbol-symbol matched-value.6)))
              (symbol=? symbol (value-symbol-symbol right))))
          ((is-value-number matched-value.6)
            (let ((number (value-number-number matched-value.6)))
              (number-equivalent? number (value-number-number right))))
          ((is-value-pair matched-value.6)
            (let ((first (value-pair-first matched-value.6)) (rest (value-pair-rest matched-value.6)))
              (ref-eq? first (value-pair-first right))))
          ((is-value-vector matched-value.6)
            (let ((vector (value-vector-vector matched-value.6)))
              (vector-eq? vector (value-vector-vector right))))
          ((is-value-bytevector matched-value.6)
            (let ((bytes (value-bytevector-bytes matched-value.6)))
              (bytevector-eq? bytes (value-bytevector-bytes right))))
          ((is-value-input matched-value.6)
            (let ((identity (value-input-identity matched-value.6)) (port (value-input-port matched-value.6)))
              (ref-eq? identity (value-input-identity right))))
          ((is-value-output matched-value.6)
            (let ((port (value-output-port matched-value.6)))
              (output-port=? port (value-output-port right))))
          ((is-value-procedure matched-value.6)
            (let ((identity (value-procedure-identity matched-value.6)) (procedure (value-procedure-procedure matched-value.6)))
              (ref-eq? identity (value-procedure-identity right))))
          ((is-value-eof matched-value.6) (let () #t))
          ((is-value-unspecified matched-value.6) (let () #t))
          ((is-value-uninitialized matched-value.6) (let () #t))
          (else
            (host:error
              "SFIR"
              "nonexhaustive control match"
              6
              (debug-source-stack)
              (if (host:record? matched-value.6)
                (host:record-type-name (host:record-rtd matched-value.6))
                "nonrecord")))))
      #f)))

(define value-length
  (lambda (values) (if (value-null? values) 0 (+ 1 (value-length (value-cdr values))))))

(define value-append
  (lambda (left right)
    (if (value-null? left)
      right
      (value-cons (value-car left) (value-append (value-cdr left) right)))))

(define value-reverse
  (lambda (values result)
    (if (value-null? values)
      result
      (value-reverse (value-cdr values) (value-cons (value-car values) result)))))

(define value-tail
  (lambda (values index) (if (= index 0) values (value-tail (value-cdr values) (- index 1)))))

(define value-member
  (lambda (value values same?)
    (if (value-null? values)
      (value-boolean #f)
      (if (same? value (value-car values)) values (value-member value (value-cdr values) same?)))))

(define value-assoc
  (lambda (key entries same?)
    (if (value-null? entries)
      (value-boolean #f)
      (if (same? key (value-car (value-car entries)))
        (value-car entries)
        (value-assoc key (value-cdr entries) same?)))))

(define values->native
  (lambda (values)
    (if (value-null? values)
      (quote ())
      (cons (value-car values) (values->native (value-cdr values))))))

(define native->values
  (lambda (values)
    (if (null? values) (value-null) (value-cons (car values) (native->values (cdr values))))))

(define invoke-1
  (lambda (procedure a0)
    (let ((matched-value.8 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.8)
          (let ((body (function-0-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.8) (let ((body (function-1-body matched-value.8))) (body a0)))
        ((is-function-2 matched-value.8)
          (let ((body (function-2-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.8)
          (let ((body (function-3-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.8)
          (let ((body (function-4-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-5 matched-value.8)
          (let ((body (function-5-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            8
            (debug-source-stack)
            (if (host:record? matched-value.8)
              (host:record-type-name (host:record-rtd matched-value.8))
              "nonrecord")))))))

(define invoke-2
  (lambda (procedure a0 a1)
    (let ((matched-value.10 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.10)
          (let ((body (function-0-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.10)
          (let ((body (function-1-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.10)
          (let ((body (function-2-body matched-value.10))) (body a0 a1)))
        ((is-function-3 matched-value.10)
          (let ((body (function-3-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.10)
          (let ((body (function-4-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-5 matched-value.10)
          (let ((body (function-5-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            10
            (debug-source-stack)
            (if (host:record? matched-value.10)
              (host:record-type-name (host:record-rtd matched-value.10))
              "nonrecord")))))))

(define invoke-3
  (lambda (procedure a0 a1 a2)
    (let ((matched-value.12 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.12)
          (let ((body (function-0-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.12)
          (let ((body (function-1-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.12)
          (let ((body (function-2-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.12)
          (let ((body (function-3-body matched-value.12))) (body a0 a1 a2)))
        ((is-function-4 matched-value.12)
          (let ((body (function-4-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-5 matched-value.12)
          (let ((body (function-5-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            12
            (debug-source-stack)
            (if (host:record? matched-value.12)
              (host:record-type-name (host:record-rtd matched-value.12))
              "nonrecord")))))))

(define invoke-4
  (lambda (procedure a0 a1 a2 a3)
    (let ((matched-value.14 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.14)
          (let ((body (function-0-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.14)
          (let ((body (function-1-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.14)
          (let ((body (function-2-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.14)
          (let ((body (function-3-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.14)
          (let ((body (function-4-body matched-value.14))) (body a0 a1 a2 a3)))
        ((is-function-5 matched-value.14)
          (let ((body (function-5-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            14
            (debug-source-stack)
            (if (host:record? matched-value.14)
              (host:record-type-name (host:record-rtd matched-value.14))
              "nonrecord")))))))

(define invoke-5
  (lambda (procedure a0 a1 a2 a3 a4)
    (let ((matched-value.16 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.16)
          (let ((body (function-0-body matched-value.16)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.16)
          (let ((body (function-1-body matched-value.16)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.16)
          (let ((body (function-2-body matched-value.16)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.16)
          (let ((body (function-3-body matched-value.16)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.16)
          (let ((body (function-4-body matched-value.16)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-5 matched-value.16)
          (let ((body (function-5-body matched-value.16))) (body a0 a1 a2 a3 a4)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            16
            (debug-source-stack)
            (if (host:record? matched-value.16)
              (host:record-type-name (host:record-rtd matched-value.16))
              "nonrecord")))))))

(define read-source-value
  (lambda (port)
    (let ((matched-value.18 (read port)))
      (cond
        ((is-read-end matched-value.18) (let () (value-eof)))
        ((is-read-error matched-value.18)
          (let ((message (read-error-message matched-value.18))) (datum-fail message)))
        ((is-read-value matched-value.18)
          (let ((datum (read-value-datum matched-value.18))) (datum->value datum)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            18
            (debug-source-stack)
            (if (host:record? matched-value.18)
              (host:record-type-name (host:record-rtd matched-value.18))
              "nonrecord")))))))

(define value-error
  (lambda (arguments)
    (begin (write (value->datum arguments)) (newline) (datum-fail "benchmark primitive error"))))

(define integer-radix-digits
  (lambda (number radix digits)
    (if (integer-zero? number)
      digits
      (let ((division (integer-divide number (integer-from-i64 radix))))
        (integer-radix-digits
          (division-quotient division)
          radix
          (cons (string-ref "0123456789abcdef" (integer->i64 (division-remainder division))) digits))))))

(define integer-radix-string
  (lambda (number radix)
    (if (if (= radix 2) #t (if (= radix 8) #t (if (= radix 10) #t (= radix 16))))
      (if (integer-zero? number)
        "0"
        (string-append
          (if (integer-negative? number) "-" "")
          (list->string (integer-radix-digits (integer-abs number) radix (quote ())))))
      (datum-fail "invalid numeric radix"))))

(define primitive/+/2
  (lambda (a0 a1) (value-number (number-add (value-number-number a0) (value-number-number a1)))))

(define primitive/=/2
  (lambda (a0 a1) (value-boolean (number=? (value-number-number a0) (value-number-number a1)))))

(define primitive/>/2
  (lambda (a0 a1) (value-boolean (number>? (value-number-number a0) (value-number-number a1)))))

(define primitive/append/2 (lambda (a0 a1) (value-append a0 a1)))

(define primitive/append/10
  (lambda (a0 a1 a2 a3 a4 a5 a6 a7 a8 a9)
    (value-append
      a0
      (value-append
        a1
        (value-append
          a2
          (value-append
            a3
            (value-append
              a4
              (value-append a5 (value-append a6 (value-append a7 (value-append a8 a9)))))))))))

(define primitive/assv/2 (lambda (a0 a1) (value-assoc a0 a1 value-eq?)))

(define primitive/boolean?/1 (lambda (a0) (value-boolean (value-boolean? a0))))

(define primitive/caadr/1 (lambda (a0) (value-car (value-car (value-cdr a0)))))

(define primitive/caar/1 (lambda (a0) (value-car (value-car a0))))

(define primitive/caddr/1 (lambda (a0) (value-car (value-cdr (value-cdr a0)))))

(define primitive/cadr/1 (lambda (a0) (value-car (value-cdr a0))))

(define primitive/car/1 (lambda (a0) (value-car a0)))

(define primitive/cdadr/1 (lambda (a0) (value-cdr (value-car (value-cdr a0)))))

(define primitive/cdar/1 (lambda (a0) (value-cdr (value-car a0))))

(define primitive/cdddr/1 (lambda (a0) (value-cdr (value-cdr (value-cdr a0)))))

(define primitive/cddr/1 (lambda (a0) (value-cdr (value-cdr a0))))

(define primitive/cdr/1 (lambda (a0) (value-cdr a0)))

(define primitive/char?/1 (lambda (a0) (value-boolean (value-character? a0))))

(define primitive/close-output-port/1
  (lambda (a0) (begin (close-output-port (value-output-port a0)) (value-unspecified))))

(define primitive/cons/2 (lambda (a0 a1) (value-cons a0 a1)))

(define primitive/eof-object?/1 (lambda (a0) (value-boolean (value-eof? a0))))

(define primitive/eqv?/2 (lambda (a0 a1) (value-boolean (value-eq? a0 a1))))

(define primitive/error/2
  (lambda (a0 a1) (value-error (value-cons a0 (value-cons a1 (value-null))))))

(define primitive/error/3
  (lambda (a0 a1 a2) (value-error (value-cons a0 (value-cons a1 (value-cons a2 (value-null)))))))

(define primitive/for-each/2
  (lambda (a0 a1)
    (if (value-null? a1)
      (value-unspecified)
      (begin (invoke-1 a0 (value-car a1)) (primitive/for-each/2 a0 (value-cdr a1))))))

(define primitive/for-each/3
  (lambda (a0 a1 a2)
    (if (value-null? a1)
      (value-unspecified)
      (begin
        (invoke-2 a0 (value-car a1) (value-car a2))
        (primitive/for-each/3 a0 (value-cdr a1) (value-cdr a2))))))

(define primitive/length/1 (lambda (a0) (value-number (exact-number (value-length a0)))))

(define primitive/list/1 (lambda (a0) (value-cons a0 (value-null))))

(define primitive/list/2 (lambda (a0 a1) (value-cons a0 (value-cons a1 (value-null)))))

(define primitive/list/3
  (lambda (a0 a1 a2) (value-cons a0 (value-cons a1 (value-cons a2 (value-null))))))

(define primitive/list/4
  (lambda (a0 a1 a2 a3)
    (value-cons a0 (value-cons a1 (value-cons a2 (value-cons a3 (value-null)))))))

(define primitive/list/5
  (lambda (a0 a1 a2 a3 a4)
    (value-cons a0 (value-cons a1 (value-cons a2 (value-cons a3 (value-cons a4 (value-null))))))))

(define primitive/list/7
  (lambda (a0 a1 a2 a3 a4 a5 a6)
    (value-cons
      a0
      (value-cons
        a1
        (value-cons a2 (value-cons a3 (value-cons a4 (value-cons a5 (value-cons a6 (value-null))))))))))

(define primitive/list/33
  (lambda (a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20 a21 a22 a23 a24 a25 a26 a27 a28 a29 a30 a31 a32)
    (value-cons
      a0
      (value-cons
        a1
        (value-cons
          a2
          (value-cons
            a3
            (value-cons
              a4
              (value-cons
                a5
                (value-cons
                  a6
                  (value-cons
                    a7
                    (value-cons
                      a8
                      (value-cons
                        a9
                        (value-cons
                          a10
                          (value-cons
                            a11
                            (value-cons
                              a12
                              (value-cons
                                a13
                                (value-cons
                                  a14
                                  (value-cons
                                    a15
                                    (value-cons
                                      a16
                                      (value-cons
                                        a17
                                        (value-cons
                                          a18
                                          (value-cons
                                            a19
                                            (value-cons
                                              a20
                                              (value-cons
                                                a21
                                                (value-cons
                                                  a22
                                                  (value-cons
                                                    a23
                                                    (value-cons
                                                      a24
                                                      (value-cons
                                                        a25
                                                        (value-cons
                                                          a26
                                                          (value-cons
                                                            a27
                                                            (value-cons
                                                              a28
                                                              (value-cons
                                                                a29
                                                                (value-cons
                                                                  a30
                                                                  (value-cons
                                                                    a31
                                                                    (value-cons a32 (value-null))))))))))))))))))))))))))))))))))))

(define primitive/list->vector/1 (lambda (a0) (value-vector (list->vector (values->native a0)))))

(define primitive/list?/1 (lambda (a0) (value-boolean (value-list? a0))))

(define primitive/map/2
  (lambda (a0 a1)
    (if (value-null? a1)
      (value-null)
      (let ((first (invoke-1 a0 (value-car a1))))
        (value-cons first (primitive/map/2 a0 (value-cdr a1)))))))

(define primitive/map/3
  (lambda (a0 a1 a2)
    (if (value-null? a1)
      (value-null)
      (let ((first (invoke-2 a0 (value-car a1) (value-car a2))))
        (value-cons first (primitive/map/3 a0 (value-cdr a1) (value-cdr a2)))))))

(define primitive/memq/2 (lambda (a0 a1) (value-member a0 a1 value-eq?)))

(define primitive/memv/2 (lambda (a0 a1) (value-member a0 a1 value-eq?)))

(define primitive/newline/1
  (lambda (a0) (begin (newline (value-output-port a0)) (value-unspecified))))

(define primitive/not/1 (lambda (a0) (value-boolean (not (value-truth? a0)))))

(define primitive/null?/1 (lambda (a0) (value-boolean (value-null? a0))))

(define primitive/number->string/2
  (lambda (a0 a1)
    (value-string
      (numeric-radix-string
        (value-number-number a0)
        (integer->i64 (number->integer (value-number-number a1)))))))

(define primitive/number?/1 (lambda (a0) (value-boolean (value-number? a0))))

(define primitive/open-input-file/1
  (lambda (a0) (value-input (ref (unit)) (open-input-file (value-string-string a0)))))

(define primitive/open-output-file/1
  (lambda (a0) (value-output (open-output-file (value-string-string a0)))))

(define primitive/pair?/1 (lambda (a0) (value-boolean (value-pair? a0))))

(define primitive/read/1 (lambda (a0) (read-source-value (value-input-port a0))))

(define primitive/reverse/1 (lambda (a0) (value-reverse a0 (value-null))))

(define primitive/set-car!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-first a0) a1) (value-unspecified))))

(define primitive/set-cdr!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-rest a0) a1) (value-unspecified))))

(define primitive/string-append/2
  (lambda (a0 a1) (value-string (string-append (value-string-string a0) (value-string-string a1)))))

(define primitive/string?/1 (lambda (a0) (value-boolean (value-string? a0))))

(define primitive/symbol?/1 (lambda (a0) (value-boolean (value-symbol? a0))))

(define primitive/vector->list/1
  (lambda (a0) (native->values (vector->list (value-vector-vector a0)))))

(define primitive/vector?/1 (lambda (a0) (value-boolean (value-vector? a0))))

(define primitive/write/2
  (lambda (a0 a1) (begin (write (value->datum a0) (value-output-port a1)) (value-unspecified))))

(define primitive-value/cons (value-procedure (ref (unit)) (function-2 primitive/cons/2)))

(define primitive-value/car (value-procedure (ref (unit)) (function-1 primitive/car/1)))

(define primitive-value/cdr (value-procedure (ref (unit)) (function-1 primitive/cdr/1)))

(define primitive-value/cadr (value-procedure (ref (unit)) (function-1 primitive/cadr/1)))

(define primitive-value/cddr (value-procedure (ref (unit)) (function-1 primitive/cddr/1)))

(define numeric-floor
  (lambda (x)
    (if (number-exact? x)
      (number-from-integer (rational-floor (number->rational x)))
      (inexact-number (floor (number->f64 x))))))

(define numeric-ceiling (lambda (x) (number-negate (numeric-floor (number-negate x)))))

(define numeric-round
  (lambda (x)
    (if (number-exact? x)
      (let ((lo (number->integer (numeric-floor x))))
        (let ((fraction (number-subtract x (number-from-integer lo))))
          (number-from-integer
            (if (number<? fraction (rational-number (make-rational (integer-from-i64 1) (integer-from-i64 2))))
              lo
              (if (number>? fraction (rational-number (make-rational (integer-from-i64 1) (integer-from-i64 2))))
                (integer-add lo (integer-from-i64 1))
                (if (integer-zero? (integer-remainder lo (integer-from-i64 2)))
                  lo
                  (integer-add lo (integer-from-i64 1))))))))
      (inexact-number (round (number->f64 x))))))

(define numeric-fold
  (lambda (operation result remaining)
    (if (value-null? remaining)
      result
      (numeric-fold
        operation
        (operation result (value-number-number (value-car remaining)))
        (value-cdr remaining)))))

(define numeric-extreme
  (lambda (maximum? result remaining inexact?)
    (if (value-null? remaining)
      (if inexact? (number-inexact result) result)
      (let ((next (value-number-number (value-car remaining))))
        (numeric-extreme
          maximum?
          (if (if maximum? (number>? next result) (number<? next result)) next result)
          (value-cdr remaining)
          (if inexact? #t (not (number-exact? next))))))))

(define numeric-integral-value
  (lambda (x)
    (if (number-integer? x)
      (number->integer (number-exact x))
      (datum-fail "integer argument required"))))

(define numeric-lcm
  (lambda (a b)
    (if (if (integer-zero? a) #t (integer-zero? b))
      (integer-from-i64 0)
      (integer-abs (integer-multiply (integer-quotient a (integer-gcd a b)) b)))))

(define numeric-gcd-fold
  (lambda (lcm? result remaining inexact?)
    (if (value-null? remaining)
      (if inexact? (number-inexact (number-from-integer result)) (number-from-integer result))
      (let ((next (value-number-number (value-car remaining))))
        (numeric-gcd-fold
          lcm?
          (if lcm?
            (numeric-lcm result (numeric-integral-value next))
            (integer-gcd result (numeric-integral-value next)))
          (value-cdr remaining)
          (if inexact? #t (not (number-exact? next))))))))

(define numeric-i (complex-number (exact-scalar 0) (exact-scalar 1)))

(define numeric-complex? (lambda (x) (not (host:real? x))))

(define numeric-real (lambda (x) (number->f64 (number-real-part x))))

(define numeric-imag (lambda (x) (number->f64 (number-imag-part x))))

(define numeric-rectangular (lambda (a b) (complex-number (inexact-scalar a) (inexact-scalar b))))

(define numeric-real-absolute (lambda (x) (if (< x 0.0) (- 0.0 x) x)))

(define numeric-negative-sign? (lambda (x) (if (< x 0.0) #t (if (= x 0.0) (< (/ 1.0 x) 0.0) #f))))

(define numeric-hypot
  (lambda (x y)
    (let ((a (numeric-real-absolute x)) (b (numeric-real-absolute y)))
      (let ((hi (if (> a b) a b)) (lo (if (> a b) b a)))
        (if (= hi (/ 1.0 0.0)) hi (if (= hi 0.0) 0.0 (* hi (sqrt (+ 1.0 (* (/ lo hi) (/ lo hi)))))))))))

(define numeric-exp
  (lambda (x)
    (if (not (numeric-complex? x))
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 1)
        (inexact-number (exp (number->f64 x))))
      (let ((m (exp (numeric-real x))) (a (numeric-imag x)))
        (numeric-rectangular (* m (cos a)) (* m (sin a)))))))

(define numeric-log
  (lambda (x)
    (if (if (not (numeric-complex? x)) (not (number-negative? x)) #f)
      (if (if (number-exact? x) (number=? x (exact-number 1)) #f)
        (exact-number 0)
        (inexact-number (log (number->f64 x))))
      (numeric-rectangular
        (log (numeric-hypot (numeric-real x) (numeric-imag x)))
        (atan2 (numeric-imag x) (numeric-real x))))))

(define numeric-complex-root
  (lambda (a b)
    (if (= b 0.0)
      (if (< a 0.0)
        (numeric-rectangular
          0.0
          (if (numeric-negative-sign? b) (- 0.0 (sqrt (- 0.0 a))) (sqrt (- 0.0 a))))
        (numeric-rectangular (sqrt a) b))
      (let ((m (numeric-hypot a b)))
        (let ((large (sqrt (+ (* 0.5 m) (* 0.5 (numeric-real-absolute a))))))
          (if (>= a 0.0)
            (numeric-rectangular large (/ b (* 2.0 large)))
            (numeric-rectangular
              (/ (numeric-real-absolute b) (* 2.0 large))
              (if (numeric-negative-sign? b) (- 0.0 large) large))))))))

(define numeric-inexact-root
  (lambda (x)
    (if (numeric-complex? x)
      (numeric-complex-root (numeric-real x) (numeric-imag x))
      (if (number-negative? x)
        (numeric-rectangular 0.0 (sqrt (- 0.0 (number->f64 x))))
        (inexact-number (sqrt (number->f64 x)))))))

(define numeric-sqrt
  (lambda (x)
    (if (if (not (numeric-complex? x)) (number-exact? x) #f)
      (let ((r (number->rational (number-abs x))))
        (let ((n (integer-sqrt/remainder (rational-numerator r))) (d (integer-sqrt/remainder (rational-denominator r))))
          (if (if (integer-zero? (root-remainder n)) (integer-zero? (root-remainder d)) #f)
            (let ((root (scalar-from-rational (make-rational (root-value n) (root-value d)))))
              (if (number-negative? x)
                (number-rectangular (exact-scalar 0) root)
                (number-from-scalar root)))
            (numeric-inexact-root x))))
      (numeric-inexact-root x))))

(define numeric-sinh (lambda (x) (* 0.5 (- (exp x) (exp (- 0.0 x))))))

(define numeric-cosh (lambda (x) (* 0.5 (+ (exp x) (exp (- 0.0 x))))))

(define numeric-sin
  (lambda (x)
    (if (not (numeric-complex? x))
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 0)
        (inexact-number (sin (number->f64 x))))
      (let ((a (numeric-real x)) (b (numeric-imag x)))
        (numeric-rectangular (* (sin a) (numeric-cosh b)) (* (cos a) (numeric-sinh b)))))))

(define numeric-cos
  (lambda (x)
    (if (not (numeric-complex? x))
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 1)
        (inexact-number (cos (number->f64 x))))
      (let ((a (numeric-real x)) (b (numeric-imag x)))
        (numeric-rectangular (* (cos a) (numeric-cosh b)) (- 0.0 (* (sin a) (numeric-sinh b))))))))

(define numeric-tan
  (lambda (x)
    (if (not (numeric-complex? x))
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 0)
        (inexact-number (tan (number->f64 x))))
      (number-divide (numeric-sin x) (numeric-cos x)))))

(define numeric-asin
  (lambda (x)
    (if (if (not (numeric-complex? x)) (if (number>=? x (exact-number -1)) (number<=? x (exact-number 1)) #f) #f)
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 0)
        (inexact-number (asin (number->f64 x))))
      (number-multiply
        (number-negate numeric-i)
        (numeric-log
          (number-add
            (number-multiply numeric-i x)
            (numeric-sqrt (number-subtract (exact-number 1) (number-multiply x x)))))))))

(define numeric-acos
  (lambda (x)
    (if (if (not (numeric-complex? x)) (if (number>=? x (exact-number -1)) (number<=? x (exact-number 1)) #f) #f)
      (if (if (number-exact? x) (number=? x (exact-number 1)) #f)
        (exact-number 0)
        (inexact-number (acos (number->f64 x))))
      (number-subtract (inexact-number (acos 0.0)) (numeric-asin x)))))

(define numeric-atan
  (lambda (x)
    (if (not (numeric-complex? x))
      (if (if (number-exact? x) (number-zero? x) #f)
        (exact-number 0)
        (inexact-number (atan (number->f64 x))))
      (number-multiply
        (number-divide numeric-i (exact-number 2))
        (number-subtract
          (numeric-log (number-subtract (exact-number 1) (number-multiply numeric-i x)))
          (numeric-log (number-add (exact-number 1) (number-multiply numeric-i x))))))))

(define numeric-integer-power
  (lambda (base exponent result)
    (if (integer-zero? exponent)
      result
      (let ((division (integer-divide exponent (integer-from-i64 2))))
        (numeric-integer-power
          (number-multiply base base)
          (division-quotient division)
          (if (integer-zero? (division-remainder division)) result (number-multiply result base)))))))

(define numeric-expt
  (lambda (base exponent)
    (if (number-exact-integer? exponent)
      (let ((n (number->integer exponent)))
        (let ((result (numeric-integer-power base (integer-abs n) (exact-number 1))))
          (if (integer-negative? n) (number-divide (exact-number 1) result) result)))
      (if (if (not (numeric-complex? base)) (if (not (numeric-complex? exponent)) (not (number-negative? base)) #f) #f)
        (inexact-number (pow (number->f64 base) (number->f64 exponent)))
        (numeric-exp (number-multiply exponent (numeric-log base)))))))

(define numeric-radix-fraction
  (lambda (remainder denominator radix digits)
    (if (integer-zero? remainder)
      (numeric-reverse-characters digits (quote ()))
      (let ((division (integer-divide (integer-multiply remainder (integer-from-i64 radix)) denominator)))
        (numeric-radix-fraction
          (division-remainder division)
          denominator
          radix
          (cons (string-ref "0123456789abcdef" (integer->i64 (division-quotient division))) digits))))))

(define numeric-reverse-characters
  (lambda (source result)
    (if (null? source) result (numeric-reverse-characters (cdr source) (cons (car source) result)))))

(define numeric-inexact-radix-string
  (lambda (x radix)
    (if (if (= x x) (if (< x (/ 1.0 0.0)) (> x (/ -1.0 0.0)) #f) #f)
      (let ((value (rational-from-f64 (numeric-real-absolute x))))
        (let ((division (integer-divide (rational-numerator value) (rational-denominator value))))
          (string-append
            (if (numeric-negative-sign? x) "-" "")
            (integer-radix-string (division-quotient division) radix)
            "."
            (if (integer-zero? (division-remainder division))
              "0"
              (list->string
                (numeric-radix-fraction
                  (division-remainder division)
                  (rational-denominator value)
                  radix
                  (quote ())))))))
      (number->string (inexact-number x)))))

(define numeric-radix-real
  (lambda (x radix)
    (if (number-exact? x)
      (let ((r (number->rational x)))
        (if (rational-integer? r)
          (integer-radix-string (rational-numerator r) radix)
          (string-append
            (integer-radix-string (rational-numerator r) radix)
            "/"
            (integer-radix-string (rational-denominator r) radix))))
      (numeric-inexact-radix-string (number->f64 x) radix))))

(define numeric-radix-string
  (lambda (x radix)
    (if (if (= radix 2) #t (if (= radix 8) #t (if (= radix 10) #t (= radix 16))))
      (if (= radix 10)
        (number->string x)
        (if (numeric-complex? x)
          (let ((real (numeric-radix-real (number-real-part x) radix)) (imag (numeric-radix-real (number-imag-part x) radix)))
            (string-append
              real
              (if (if (char=? (string-ref imag 0) #\+) #t (char=? (string-ref imag 0) #\-)) "" "+")
              imag
              "i"))
          (numeric-radix-real x radix)))
      (datum-fail "invalid numeric radix"))))

(define invoke-list
  (lambda (procedure arguments)
    (let ((matched-value.20 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.20)
          (let ((body (function-0-body matched-value.20)))
            (if (value-null? arguments) (body) (datum-fail "procedure argument count mismatch"))))
        ((is-function-1 matched-value.20)
          (let ((body (function-1-body matched-value.20)))
            (if (value-null? (value-cdr arguments))
              (body (value-car arguments))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-2 matched-value.20)
          (let ((body (function-2-body matched-value.20)))
            (if (value-null? (value-cdr (value-cdr arguments)))
              (body (value-car arguments) (value-car (value-cdr arguments)))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-3 matched-value.20)
          (let ((body (function-3-body matched-value.20)))
            (if (value-null? (value-cdr (value-cdr (value-cdr arguments))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-4 matched-value.20)
          (let ((body (function-4-body matched-value.20)))
            (if (value-null? (value-cdr (value-cdr (value-cdr (value-cdr arguments)))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments)))
                (value-car (value-cdr (value-cdr (value-cdr arguments)))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-5 matched-value.20)
          (let ((body (function-5-body matched-value.20)))
            (if (value-null? (value-cdr (value-cdr (value-cdr (value-cdr (value-cdr arguments))))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments)))
                (value-car (value-cdr (value-cdr (value-cdr arguments))))
                (value-car (value-cdr (value-cdr (value-cdr (value-cdr arguments))))))
              (datum-fail "procedure argument count mismatch"))))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            20
            (debug-source-stack)
            (if (host:record? matched-value.20)
              (host:record-type-name (host:record-rtd matched-value.20))
              "nonrecord")))))))

(define value-characters
  (lambda (values)
    (if (value-null? values)
      (quote ())
      (cons (value-character-character (value-car values)) (value-characters (value-cdr values))))))

(define value-wrap-characters
  (lambda (values)
    (if (null? values)
      (quote ())
      (cons (value-character (car values)) (value-wrap-characters (cdr values))))))

(define parsed-number->value
  (lambda (result)
    (let ((matched-value.22 result))
      (cond
        ((is-not-a-number matched-value.22) (let () (value-boolean #f)))
        ((is-parsed-number matched-value.22)
          (let ((number (parsed-number-value matched-value.22))) (value-number number)))
        ((is-number-error matched-value.22)
          (let ((message (number-error-text matched-value.22))) (datum-fail message)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            22
            (debug-source-stack)
            (if (host:record? matched-value.22)
              (host:record-type-name (host:record-rtd matched-value.22))
              "nonrecord")))))))

(define value-compare-strings
  (lambda (left right index)
    (if (= index (string-length left))
      (if (= index (string-length right)) 0 -1)
      (if (= index (string-length right))
        1
        (let ((a (string-ref left index)) (b (string-ref right index)))
          (if (char=? a b) (value-compare-strings left right (+ index 1)) (if (char<? a b) -1 1)))))))

(define value-strings-length
  (lambda (values count)
    (if (> count 4294967294)
      (datum-fail "string exceeds representation bound")
      (if (value-null? values)
        count
        (value-strings-length
          (value-cdr values)
          (+ count (string-length (value-string-string (value-car values)))))))))

(define value-copy-strings
  (lambda (values result offset)
    (if (value-null? values)
      result
      (let ((text (value-string-string (value-car values))))
        (begin
          (string-copy! result offset text 0 (string-length text))
          (value-copy-strings (value-cdr values) result (+ offset (string-length text))))))))

(define value-join-strings
  (lambda (values)
    (value-string (value-copy-strings values (make-string (value-strings-length values 0)) 0))))

(define value-append-many
  (lambda (lists)
    (if (value-null? lists)
      (value-null)
      (if (value-null? (value-cdr lists))
        (value-car lists)
        (value-append (value-car lists) (value-append-many (value-cdr lists)))))))

(define value-apply-arguments
  (lambda (values)
    (if (value-null? (value-cdr values))
      (value-car values)
      (value-cons (value-car values) (value-apply-arguments (value-cdr values))))))

(define value-list-heads
  (lambda (lists)
    (if (value-null? lists)
      (value-null)
      (value-cons (value-car (value-car lists)) (value-list-heads (value-cdr lists))))))

(define value-list-tails
  (lambda (lists)
    (if (value-null? lists)
      (value-null)
      (value-cons (value-cdr (value-car lists)) (value-list-tails (value-cdr lists))))))

(define value-map-many
  (lambda (procedure lists)
    (if (value-null? (value-car lists))
      (value-null)
      (let ((first (invoke-list procedure (value-list-heads lists))))
        (value-cons first (value-map-many procedure (value-list-tails lists)))))))

(define value-for-each-many
  (lambda (procedure lists)
    (if (value-null? (value-car lists))
      (value-unspecified)
      (begin
        (invoke-list procedure (value-list-heads lists))
        (value-for-each-many procedure (value-list-tails lists))))))

(define equal-bytes?
  (lambda (left right index)
    (if (= (bytevector-length left) (bytevector-length right))
      (if (= index (bytevector-length left))
        #t
        (if (= (bytevector-u8-ref left index) (bytevector-u8-ref right index))
          (equal-bytes? left right (+ index 1))
          #f))
      #f)))

(begin
  (host:define-record-type
    (equal-pair/record equal-pair is-equal-pair)
    (fields (immutable left equal-left) (immutable right equal-right))))

(define equal-seen?
  (lambda (left right seen)
    (if (null? seen)
      #f
      (if (if (value-eq? left (equal-left (car seen))) (value-eq? right (equal-right (car seen))) #f)
        #t
        (equal-seen? left right (cdr seen))))))

(define value-equal? (lambda (left right) (equal-graph? left right (quote ()))))

(define equal-graph?
  (lambda (left right seen)
    (if (value-eq? left right)
      #t
      (if (not (= (value-kind left) (value-kind right)))
        #f
        (if (value-string? left)
          (string=? (value-string-string left) (value-string-string right))
          (if (value-bytevector? left)
            (equal-bytes? (value-bytevector-bytes left) (value-bytevector-bytes right) 0)
            (if (if (value-pair? left) #t (value-vector? left))
              (if (equal-seen? left right seen)
                #t
                (let ((seen (cons (equal-pair left right) seen)))
                  (if (value-pair? left)
                    (if (equal-graph? (value-car left) (value-car right) seen)
                      (equal-graph? (value-cdr left) (value-cdr right) seen)
                      #f)
                    (equal-vectors? (value-vector-vector left) (value-vector-vector right) 0 seen))))
              #f)))))))

(define equal-vectors?
  (lambda (left right index seen)
    (if (= (vector-length left) (vector-length right))
      (if (= index (vector-length left))
        #t
        (if (equal-graph? (vector-ref left index) (vector-ref right index) seen)
          (equal-vectors? left right (+ index 1) seen)
          #f))
      #f)))

(define value-list?
  (lambda (value)
    (if (value-null? value)
      #t
      (if (value-pair? value) (list-cycle-check value (value-cdr value)) #f))))

(define list-cycle-check
  (lambda (slow fast)
    (if (value-null? fast)
      #t
      (if (value-pair? fast)
        (if (value-eq? slow fast)
          #f
          (let ((next (value-cdr fast)))
            (if (value-null? next)
              #t
              (if (value-pair? next) (list-cycle-check (value-cdr slow) (value-cdr next)) #f))))
        #f))))

(begin
  (host:define-record-type
    (inward/record inward is-inward)
    (fields (immutable source inward-source) (immutable result inward-result))))

(begin
  (host:define-record-type
    (outward/record outward is-outward)
    (fields (immutable source outward-source) (immutable result outward-result))))

(define inward-find
  (lambda (source seen)
    (if (null? seen)
      (value-uninitialized)
      (if (datum-eq? source (inward-source (car seen)))
        (inward-result (car seen))
        (inward-find source (cdr seen))))))

(begin
  (host:define-record-type (outward-absent/record outward-absent is-outward-absent) (fields))
  (host:define-record-type
    (outward-found/record outward-found is-outward-found)
    (fields (immutable value outward-found/value))))

(define outward-find
  (lambda (source seen)
    (if (null? seen)
      (outward-absent)
      (if (value-eq? source (outward-source (car seen)))
        (outward-found (outward-result (car seen)))
        (outward-find source (cdr seen))))))

(define datum->value (lambda (source) (inward-graph source (ref (quote ())))))

(define inward-graph
  (lambda (source seen)
    (let ((kind (datum-kind source)))
      (if (= kind 0)
        (value-null)
        (if (= kind 1)
          (value-boolean (datum-boolean-value source))
          (if (= kind 2)
            (value-character (datum-character-value source))
            (if (= kind 3)
              (value-string (datum-string-value source))
              (if (= kind 4)
                (value-symbol (datum-symbol-value source))
                (if (= kind 5)
                  (value-number (datum-number-value source))
                  (if (= kind 8)
                    (value-bytevector (datum-bytevector-values source))
                    (let ((prior (inward-find source (ref-get seen))))
                      (if (value-uninitialized? prior) (inward-node source kind seen) prior))))))))))))

(define inward-node
  (lambda (source kind seen)
    (let ((result (if (= kind 6) (value-cons (value-unspecified) (value-unspecified)) (value-vector (make-vector (vector-length (datum-vector-values source)) (value-unspecified))))))
      (begin
        (ref-set! seen (cons (inward source result) (ref-get seen)))
        (if (= kind 6)
          (begin
            (ref-set! (value-pair-first result) (inward-graph (datum-car source) seen))
            (ref-set! (value-pair-rest result) (inward-graph (datum-cdr source) seen)))
          (inward-vector (datum-vector-values source) (value-vector-vector result) 0 seen))
        result))))

(define inward-vector
  (lambda (source result index seen)
    (if (= index (vector-length source))
      (unit)
      (begin
        (vector-set! result index (inward-graph (vector-ref source index) seen))
        (inward-vector source result (+ index 1) seen)))))

(define value->datum (lambda (source) (outward-graph source (ref (quote ())))))

(define outward-graph
  (lambda (source seen)
    (let ((matched-value.24 source))
      (cond
        ((is-value-null matched-value.24) (let () (datum-null)))
        ((is-value-boolean matched-value.24)
          (let ((x (value-boolean-boolean matched-value.24))) (datum-boolean x)))
        ((is-value-character matched-value.24)
          (let ((x (value-character-character matched-value.24))) (datum-character x)))
        ((is-value-string matched-value.24)
          (let ((x (value-string-string matched-value.24))) (datum-string x)))
        ((is-value-symbol matched-value.24)
          (let ((x (value-symbol-symbol matched-value.24))) (datum-symbol x)))
        ((is-value-number matched-value.24)
          (let ((x (value-number-number matched-value.24))) (datum-number x)))
        ((is-value-bytevector matched-value.24)
          (let ((x (value-bytevector-bytes matched-value.24))) (datum-bytevector x)))
        ((is-value-pair matched-value.24)
          (let ((first (value-pair-first matched-value.24)) (rest (value-pair-rest matched-value.24)))
            (outward-mutable source seen)))
        ((is-value-vector matched-value.24)
          (let ((vector (value-vector-vector matched-value.24))) (outward-mutable source seen)))
        ((is-value-input matched-value.24)
          (let ((identity (value-input-identity matched-value.24)) (port (value-input-port matched-value.24)))
            (datum-symbol (string->symbol "#<input-port>"))))
        ((is-value-output matched-value.24)
          (let ((port (value-output-port matched-value.24)))
            (datum-symbol (string->symbol "#<output-port>"))))
        ((is-value-procedure matched-value.24)
          (let ((identity (value-procedure-identity matched-value.24)) (procedure (value-procedure-procedure matched-value.24)))
            (datum-symbol (string->symbol "#<procedure>"))))
        ((is-value-eof matched-value.24) (let () (datum-symbol (string->symbol "#<eof>"))))
        ((is-value-unspecified matched-value.24)
          (let () (datum-symbol (string->symbol "#<unspecified>"))))
        ((is-value-uninitialized matched-value.24)
          (let () (datum-fail "uninitialized value is not external data")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            24
            (debug-source-stack)
            (if (host:record? matched-value.24)
              (host:record-type-name (host:record-rtd matched-value.24))
              "nonrecord")))))))

(define outward-mutable
  (lambda (source seen)
    (let ((matched-value.26 (outward-find source (ref-get seen))))
      (cond
        ((is-outward-found matched-value.26)
          (let ((result (outward-found/value matched-value.26))) result))
        ((is-outward-absent matched-value.26) (let () (outward-node source seen)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            26
            (debug-source-stack)
            (if (host:record? matched-value.26)
              (host:record-type-name (host:record-rtd matched-value.26))
              "nonrecord")))))))

(define outward-node
  (lambda (source seen)
    (let ((result (if (value-pair? source) (datum-cons (datum-null) (datum-null)) (datum-vector (make-vector (vector-length (value-vector-vector source)) (datum-null))))))
      (begin
        (ref-set! seen (cons (outward source result) (ref-get seen)))
        (if (value-pair? source)
          (begin
            (datum-set-car! result (outward-graph (value-car source) seen))
            (datum-set-cdr! result (outward-graph (value-cdr source) seen)))
          (outward-vector (value-vector-vector source) (datum-vector-values result) 0 seen))
        result))))

(define outward-vector
  (lambda (source result index seen)
    (if (= index (vector-length source))
      (unit)
      (begin
        (vector-set! result index (outward-graph (vector-ref source index) seen))
        (outward-vector source result (+ index 1) seen)))))

(define literal (value-symbol (string->symbol ":")))

(define literal.1
  (value-cons
    (value-symbol (string->symbol "lambda"))
    (value-cons
      (value-symbol (string->symbol "if"))
      (value-cons
        (value-symbol (string->symbol "set!"))
        (value-cons
          (value-symbol (string->symbol "begin"))
          (value-cons
            (value-symbol (string->symbol "cond"))
            (value-cons
              (value-symbol (string->symbol "and"))
              (value-cons
                (value-symbol (string->symbol "or"))
                (value-cons
                  (value-symbol (string->symbol "case"))
                  (value-cons
                    (value-symbol (string->symbol "let"))
                    (value-cons
                      (value-symbol (string->symbol "let*"))
                      (value-cons
                        (value-symbol (string->symbol "letrec"))
                        (value-cons
                          (value-symbol (string->symbol "do"))
                          (value-cons
                            (value-symbol (string->symbol "quasiquote"))
                            (value-cons
                              (value-symbol (string->symbol "else"))
                              (value-cons
                                (value-symbol (string->symbol "=>"))
                                (value-cons
                                  (value-symbol (string->symbol "define"))
                                  (value-cons
                                    (value-symbol (string->symbol "unquote"))
                                    (value-cons
                                      (value-symbol (string->symbol "unquote-splicing"))
                                      (value-null))))))))))))))))))))

(define literal.2 (value-symbol (string->symbol "dynamic-parse-datum")))

(define literal.3 (value-string "Unknown datum: ~s"))

(define literal.4 (value-symbol (string->symbol "dynamic-parse-formal")))

(define literal.5 (value-string "Not an identifier: ~s"))

(define literal.6 (value-symbol (string->symbol "dynamic-parse-formal")))

(define literal.7 (value-string "Duplicate variable definition: ~s"))

(define literal.8 (value-symbol (string->symbol "dynamic-parse-formal")))

(define literal.9 (value-string "Illegal identifier (keyword): ~s"))

(define literal.10 (value-symbol (string->symbol "dynamic-parse-formal*")))

(define literal.11 (value-string "Illegal formals: ~s"))

(define literal.12 (value-cons (value-symbol (string->symbol "quasiquote")) (value-null)))

(define literal.13 (value-cons (value-symbol (string->symbol "do")) (value-null)))

(define literal.14 (value-cons (value-symbol (string->symbol "letrec")) (value-null)))

(define literal.15 (value-cons (value-symbol (string->symbol "let*")) (value-null)))

(define literal.16 (value-cons (value-symbol (string->symbol "let")) (value-null)))

(define literal.17 (value-cons (value-symbol (string->symbol "or")) (value-null)))

(define literal.18 (value-cons (value-symbol (string->symbol "and")) (value-null)))

(define literal.19 (value-cons (value-symbol (string->symbol "case")) (value-null)))

(define literal.20 (value-cons (value-symbol (string->symbol "cond")) (value-null)))

(define literal.21 (value-cons (value-symbol (string->symbol "begin")) (value-null)))

(define literal.22 (value-cons (value-symbol (string->symbol "set!")) (value-null)))

(define literal.23 (value-cons (value-symbol (string->symbol "if")) (value-null)))

(define literal.24 (value-cons (value-symbol (string->symbol "lambda")) (value-null)))

(define literal.25 (value-cons (value-symbol (string->symbol "quote")) (value-null)))

(define literal.26 (value-symbol (string->symbol "dynamic-parse-expression*")))

(define literal.27 (value-string "Not a list of expressions: ~s"))

(define literal.28 (value-symbol (string->symbol "dynamic-parse-expressions")))

(define literal.29 (value-string "Illegal expression list: ~s"))

(define literal.30 (value-symbol (string->symbol "dynamic-parse-variable")))

(define literal.31 (value-string "Not an identifier: ~s"))

(define literal.32 (value-symbol (string->symbol "dynamic-parse-variable")))

(define literal.33 (value-string "Illegal identifier (keyword): ~s"))

(define literal.34 (value-symbol (string->symbol "dynamic-parse-quote")))

(define literal.35 (value-string "Not a datum (multiple arguments): ~s"))

(define literal.36 (value-symbol (string->symbol "dynamic-parse-lambda")))

(define literal.37 (value-string "Illegal formals/body: ~s"))

(define literal.38 (value-cons (value-symbol (string->symbol "begin")) (value-null)))

(define literal.39 (value-cons (value-symbol (string->symbol "define")) (value-null)))

(define literal.40 (value-symbol (string->symbol "dynamic-parse-body")))

(define literal.41 (value-string "Illegal body: ~s"))

(define literal.42 (value-symbol (string->symbol "dynamic-parse-if")))

(define literal.43 (value-string "Not an if-expression: ~s"))

(define literal.44 (value-symbol (string->symbol "dynamic-parse-set")))

(define literal.45 (value-string "Not a variable/expression pair: ~s"))

(define literal.46 (value-symbol (string->symbol "dynamic-parse-cond")))

(define literal.47 (value-string "Not a list of cond-clauses: ~s"))

(define literal.48 (value-symbol (string->symbol "dynamic-parse-cond-clause")))

(define literal.49 (value-string "Not a cond-clause: ~s"))

(define literal.50 (value-symbol (string->symbol "else")))

(define literal.51 (value-symbol (string->symbol "dynamic-parse-and")))

(define literal.52 (value-string "Not a list of arguments: ~s"))

(define literal.53 (value-symbol (string->symbol "dynamic-parse-or")))

(define literal.54 (value-string "Not a list of arguments: ~s"))

(define literal.55 (value-symbol (string->symbol "dynamic-parse-case")))

(define literal.56 (value-string "Not a list of clauses: ~s"))

(define literal.57 (value-symbol (string->symbol "dynamic-parse-case-clause")))

(define literal.58 (value-string "Not case clause: ~s"))

(define literal.59 (value-symbol (string->symbol "dynamic-parse-case-clause")))

(define literal.60 (value-string "Not a datum list: ~s"))

(define literal.61 (value-symbol (string->symbol "else")))

(define literal.62 (value-symbol (string->symbol "dynamic-parse-let")))

(define literal.63 (value-string "Illegal bindings/body: ~s"))

(define literal.64 (value-symbol (string->symbol "dynamic-parse-named-let")))

(define literal.65 (value-string "Illegal named let-expression: ~s"))

(define literal.66 (value-symbol (string->symbol "dynamic-parse-parallel-bindings")))

(define literal.67 (value-string "Not a list of bindings: ~s"))

(define literal.68 (value-symbol (string->symbol "dynamic-parse-let*")))

(define literal.69 (value-string "Illegal bindings/body: ~s"))

(define literal.70 (value-symbol (string->symbol "dynamic-parse-sequential-bindings")))

(define literal.71 (value-string "Illegal bindings: ~s"))

(define literal.72 (value-symbol (string->symbol "dynamic-parse-sequential-bindings")))

(define literal.73 (value-string "Illegal binding: ~s"))

(define literal.74 (value-symbol (string->symbol "dynamic-parse-letrec")))

(define literal.75 (value-string "Illegal bindings/body: ~s"))

(define literal.76 (value-symbol (string->symbol "dynamic-parse-recursive-bindings")))

(define literal.77 (value-string "Illegal bindings: ~s"))

(define literal.78 (value-symbol (string->symbol "dynamic-parse-do")))

(define literal.79 (value-string "Nothing yet..."))

(define literal.80 (value-symbol (string->symbol "dynamic-parse-quasiquote")))

(define literal.81 (value-string "Nothing yet..."))

(define literal.82 (value-cons (value-symbol (string->symbol "begin")) (value-null)))

(define literal.83 (value-cons (value-symbol (string->symbol "define")) (value-null)))

(define literal.84 (value-symbol (string->symbol "dynamic-parse-command*")))

(define literal.85 (value-string "Invalid sequence of commands: ~s"))

(define literal.86 (value-symbol (string->symbol "dynamic-parse-define")))

(define literal.87 (value-string "Not a valid definition: ~s"))

(define literal.88 (value-symbol (string->symbol "dynamic-parse-define")))

(define literal.89 (value-string "Not a valid pattern: ~s"))

(define literal.90 (value-symbol (string->symbol "dynamic-parse-define")))

(define literal.91 (value-string "Not a single expression: ~s"))

(define literal.92 (value-string "t#"))

(define literal.93 (value-string "Dynamic"))

(define literal.94 (value-symbol (string->symbol "is")))

(define literal.95 (value-symbol (string->symbol "boolean")))

(define literal.96 (value-symbol (string->symbol "char")))

(define literal.97 (value-symbol (string->symbol "null")))

(define literal.98 (value-symbol (string->symbol "number")))

(define literal.99 (value-symbol (string->symbol "pair")))

(define literal.100 (value-symbol (string->symbol "procedure")))

(define literal.101 (value-symbol (string->symbol "string")))

(define literal.102 (value-symbol (string->symbol "symbol")))

(define literal.103 (value-symbol (string->symbol "vector")))

(define literal.104 (value-symbol (string->symbol "forall")))

(define literal.105 (value-symbol (string->symbol "fix")))

(define literal.106 (value-string "Illegal recursive type: ~s"))

(define literal.107 (value-symbol (string->symbol "=")))

(define literal.108 (value-symbol (string->symbol "=")))

(define literal.109 (value-symbol (string->symbol "ast-show")))

(define literal.110 (value-string "Unknown abstract syntax operator: ~s"))

(define literal.111 (value-symbol (string->symbol "begin")))

(define literal.112 (value-cons (value-number (exact-number 28)) (value-null)))

(define literal.113 (value-symbol (string->symbol "define")))

(define literal.114 (value-cons (value-number (exact-number 27)) (value-null)))

(define literal.115 (value-symbol (string->symbol "define")))

(define literal.116 (value-cons (value-number (exact-number 26)) (value-null)))

(define literal.117 (value-symbol (string->symbol "ast-show")))

(define literal.118 (value-string "This can't happen: empty encountered!"))

(define literal.119 (value-cons (value-number (exact-number 25)) (value-null)))

(define literal.120 (value-symbol (string->symbol "ast-show")))

(define literal.121 (value-string "Do expressions not handled! (~s)"))

(define literal.122 (value-cons (value-number (exact-number 24)) (value-null)))

(define literal.123 (value-symbol (string->symbol "begin")))

(define literal.124 (value-cons (value-number (exact-number 23)) (value-null)))

(define literal.125 (value-symbol (string->symbol "letrec")))

(define literal.126 (value-cons (value-number (exact-number 22)) (value-null)))

(define literal.127 (value-symbol (string->symbol "let*")))

(define literal.128 (value-cons (value-number (exact-number 21)) (value-null)))

(define literal.129 (value-symbol (string->symbol "let")))

(define literal.130 (value-cons (value-number (exact-number 20)) (value-null)))

(define literal.131 (value-symbol (string->symbol "let")))

(define literal.132 (value-cons (value-number (exact-number 19)) (value-null)))

(define literal.133 (value-symbol (string->symbol "or")))

(define literal.134 (value-cons (value-number (exact-number 18)) (value-null)))

(define literal.135 (value-symbol (string->symbol "and")))

(define literal.136 (value-cons (value-number (exact-number 17)) (value-null)))

(define literal.137 (value-symbol (string->symbol "case")))

(define literal.138 (value-symbol (string->symbol "else")))

(define literal.139 (value-cons (value-number (exact-number 16)) (value-null)))

(define literal.140 (value-symbol (string->symbol "cond")))

(define literal.141 (value-symbol (string->symbol "else")))

(define literal.142 (value-cons (value-number (exact-number 15)) (value-null)))

(define literal.143 (value-symbol (string->symbol "set!")))

(define literal.144 (value-cons (value-number (exact-number 14)) (value-null)))

(define literal.145 (value-symbol (string->symbol "if")))

(define literal.146 (value-cons (value-number (exact-number 13)) (value-null)))

(define literal.147 (value-symbol (string->symbol "lambda")))

(define literal.148 (value-cons (value-number (exact-number 12)) (value-null)))

(define literal.149 (value-cons (value-number (exact-number 11)) (value-null)))

(define literal.150 (value-cons (value-number (exact-number 9)) (value-null)))

(define literal.151 (value-symbol (string->symbol "cons")))

(define literal.152 (value-cons (value-number (exact-number 7)) (value-null)))

(define literal.153 (value-cons (value-number (exact-number 6)) (value-null)))

(define literal.154 (value-symbol (string->symbol "quote")))

(define literal.155 (value-cons (value-number (exact-number 5)) (value-null)))

(define literal.156
  (value-cons
    (value-number (exact-number 30))
    (value-cons (value-number (exact-number 32)) (value-null))))

(define literal.157
  (value-cons
    (value-number (exact-number 29))
    (value-cons (value-number (exact-number 31)) (value-null))))

(define literal.158
  (value-cons
    (value-number (exact-number 0))
    (value-cons
      (value-number (exact-number 1))
      (value-cons
        (value-number (exact-number 2))
        (value-cons
          (value-number (exact-number 3))
          (value-cons
            (value-number (exact-number 4))
            (value-cons
              (value-number (exact-number 8))
              (value-cons (value-number (exact-number 10)) (value-null)))))))))

(define literal.159 (value-symbol (string->symbol "datum-show")))

(define literal.160 (value-string "This should not happen!"))

(define literal.161 (value-cons (value-number (exact-number 7)) (value-null)))

(define literal.162 (value-cons (value-number (exact-number 6)) (value-null)))

(define literal.163
  (value-cons
    (value-number (exact-number 0))
    (value-cons
      (value-number (exact-number 1))
      (value-cons
        (value-number (exact-number 2))
        (value-cons
          (value-number (exact-number 3))
          (value-cons
            (value-number (exact-number 4))
            (value-cons (value-number (exact-number 5)) (value-null))))))))

(define literal.164 (value-symbol (string->symbol "ast-gen")))

(define literal.165 (value-string "Can't handle syntax operator: ~s"))

(define literal.166 (value-cons (value-number (exact-number 28)) (value-null)))

(define literal.167 (value-cons (value-number (exact-number 27)) (value-null)))

(define literal.168 (value-cons (value-number (exact-number 26)) (value-null)))

(define literal.169 (value-cons (value-number (exact-number 25)) (value-null)))

(define literal.170 (value-symbol (string->symbol "ast-gen")))

(define literal.171 (value-string "Do-expressions not handled! (Argument: ~s) arg"))

(define literal.172 (value-cons (value-number (exact-number 24)) (value-null)))

(define literal.173 (value-cons (value-number (exact-number 23)) (value-null)))

(define literal.174 (value-cons (value-number (exact-number 20)) (value-null)))

(define literal.175
  (value-cons
    (value-number (exact-number 19))
    (value-cons
      (value-number (exact-number 21))
      (value-cons (value-number (exact-number 22)) (value-null)))))

(define literal.176
  (value-cons
    (value-number (exact-number 17))
    (value-cons (value-number (exact-number 18)) (value-null))))

(define literal.177 (value-cons (value-number (exact-number 16)) (value-null)))

(define literal.178 (value-cons (value-number (exact-number 15)) (value-null)))

(define literal.179 (value-cons (value-number (exact-number 14)) (value-null)))

(define literal.180 (value-cons (value-number (exact-number 13)) (value-null)))

(define literal.181 (value-cons (value-number (exact-number 12)) (value-null)))

(define literal.182 (value-cons (value-number (exact-number 11)) (value-null)))

(define literal.183 (value-cons (value-number (exact-number 10)) (value-null)))

(define literal.184 (value-cons (value-number (exact-number 9)) (value-null)))

(define literal.185 (value-cons (value-number (exact-number 8)) (value-null)))

(define literal.186
  (value-cons
    (value-number (exact-number 7))
    (value-cons
      (value-number (exact-number 30))
      (value-cons (value-number (exact-number 32)) (value-null)))))

(define literal.187 (value-cons (value-number (exact-number 6)) (value-null)))

(define literal.188 (value-cons (value-number (exact-number 5)) (value-null)))

(define literal.189 (value-cons (value-number (exact-number 4)) (value-null)))

(define literal.190 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.191 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.192 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.193
  (value-cons
    (value-number (exact-number 0))
    (value-cons
      (value-number (exact-number 29))
      (value-cons (value-number (exact-number 31)) (value-null)))))

(define literal.194 (value-symbol (string->symbol "convert-tvars")))

(define literal.195 (value-string "Not a list of tvars: ~s"))

(define literal.196 (value-symbol (string->symbol "tast-show")))

(define literal.197 (value-string "Unknown abstract syntax operator: ~s"))

(define literal.198 (value-symbol (string->symbol "begin")))

(define literal.199 (value-cons (value-number (exact-number 28)) (value-null)))

(define literal.200 (value-symbol (string->symbol "define")))

(define literal.201 (value-cons (value-number (exact-number 27)) (value-null)))

(define literal.202 (value-symbol (string->symbol "define")))

(define literal.203 (value-cons (value-number (exact-number 26)) (value-null)))

(define literal.204 (value-symbol (string->symbol "tast-show")))

(define literal.205 (value-string "This can't happen: empty encountered!"))

(define literal.206 (value-cons (value-number (exact-number 25)) (value-null)))

(define literal.207 (value-symbol (string->symbol "tast-show")))

(define literal.208 (value-string "Do expressions not handled! (~s)"))

(define literal.209 (value-cons (value-number (exact-number 24)) (value-null)))

(define literal.210 (value-symbol (string->symbol "begin")))

(define literal.211 (value-cons (value-number (exact-number 23)) (value-null)))

(define literal.212 (value-symbol (string->symbol "letrec")))

(define literal.213 (value-cons (value-number (exact-number 22)) (value-null)))

(define literal.214 (value-symbol (string->symbol "let*")))

(define literal.215 (value-cons (value-number (exact-number 21)) (value-null)))

(define literal.216 (value-symbol (string->symbol "let")))

(define literal.217 (value-cons (value-number (exact-number 20)) (value-null)))

(define literal.218 (value-symbol (string->symbol "let")))

(define literal.219 (value-cons (value-number (exact-number 19)) (value-null)))

(define literal.220 (value-symbol (string->symbol "or")))

(define literal.221 (value-cons (value-number (exact-number 18)) (value-null)))

(define literal.222 (value-symbol (string->symbol "and")))

(define literal.223 (value-cons (value-number (exact-number 17)) (value-null)))

(define literal.224 (value-symbol (string->symbol "case")))

(define literal.225 (value-symbol (string->symbol "else")))

(define literal.226 (value-cons (value-number (exact-number 16)) (value-null)))

(define literal.227 (value-symbol (string->symbol "cond")))

(define literal.228 (value-symbol (string->symbol "else")))

(define literal.229 (value-cons (value-number (exact-number 15)) (value-null)))

(define literal.230 (value-symbol (string->symbol "set!")))

(define literal.231 (value-cons (value-number (exact-number 14)) (value-null)))

(define literal.232 (value-symbol (string->symbol "if")))

(define literal.233 (value-cons (value-number (exact-number 13)) (value-null)))

(define literal.234 (value-symbol (string->symbol "lambda")))

(define literal.235 (value-cons (value-number (exact-number 12)) (value-null)))

(define literal.236 (value-cons (value-number (exact-number 11)) (value-null)))

(define literal.237 (value-cons (value-number (exact-number 9)) (value-null)))

(define literal.238 (value-symbol (string->symbol "cons")))

(define literal.239 (value-cons (value-number (exact-number 7)) (value-null)))

(define literal.240 (value-cons (value-number (exact-number 6)) (value-null)))

(define literal.241 (value-symbol (string->symbol "quote")))

(define literal.242 (value-cons (value-number (exact-number 5)) (value-null)))

(define literal.243
  (value-cons
    (value-number (exact-number 30))
    (value-cons (value-number (exact-number 32)) (value-null))))

(define literal.244
  (value-cons
    (value-number (exact-number 29))
    (value-cons (value-number (exact-number 31)) (value-null))))

(define literal.245
  (value-cons
    (value-number (exact-number 0))
    (value-cons
      (value-number (exact-number 1))
      (value-cons
        (value-number (exact-number 2))
        (value-cons
          (value-number (exact-number 3))
          (value-cons
            (value-number (exact-number 4))
            (value-cons
              (value-number (exact-number 8))
              (value-cons (value-number (exact-number 10)) (value-null)))))))))

(define literal.246 (value-symbol (string->symbol "no-tag")))

(define literal.247 (value-symbol (string->symbol "tag")))

(define literal.248 (value-symbol (string->symbol "no-untag")))

(define literal.249 (value-symbol (string->symbol "untag")))

(define literal.250 (value-symbol (string->symbol "no-may-untag")))

(define literal.251 (value-symbol (string->symbol "may-untag")))

(define literal.252 (value-symbol (string->symbol "tag-ast-show")))

(define literal.253 (value-string "Unknown abstract syntax operator: ~s"))

(define literal.254 (value-symbol (string->symbol "begin")))

(define literal.255 (value-cons (value-number (exact-number 28)) (value-null)))

(define literal.256 (value-symbol (string->symbol "define")))

(define literal.257 (value-symbol (string->symbol "lambda")))

(define literal.258 (value-cons (value-number (exact-number 27)) (value-null)))

(define literal.259 (value-symbol (string->symbol "define")))

(define literal.260 (value-cons (value-number (exact-number 26)) (value-null)))

(define literal.261 (value-symbol (string->symbol "tag-ast-show")))

(define literal.262 (value-string "This can't happen: empty encountered!"))

(define literal.263 (value-cons (value-number (exact-number 25)) (value-null)))

(define literal.264 (value-symbol (string->symbol "tag-ast-show")))

(define literal.265 (value-string "Do expressions not handled! (~s)"))

(define literal.266 (value-cons (value-number (exact-number 24)) (value-null)))

(define literal.267 (value-symbol (string->symbol "begin")))

(define literal.268 (value-cons (value-number (exact-number 23)) (value-null)))

(define literal.269 (value-symbol (string->symbol "letrec")))

(define literal.270 (value-cons (value-number (exact-number 22)) (value-null)))

(define literal.271 (value-symbol (string->symbol "let*")))

(define literal.272 (value-cons (value-number (exact-number 21)) (value-null)))

(define literal.273 (value-symbol (string->symbol "let")))

(define literal.274 (value-cons (value-number (exact-number 20)) (value-null)))

(define literal.275 (value-symbol (string->symbol "let")))

(define literal.276 (value-cons (value-number (exact-number 19)) (value-null)))

(define literal.277 (value-symbol (string->symbol "or")))

(define literal.278 (value-cons (value-number (exact-number 18)) (value-null)))

(define literal.279 (value-symbol (string->symbol "and")))

(define literal.280 (value-cons (value-number (exact-number 17)) (value-null)))

(define literal.281 (value-symbol (string->symbol "case")))

(define literal.282 (value-symbol (string->symbol "else")))

(define literal.283 (value-cons (value-number (exact-number 16)) (value-null)))

(define literal.284 (value-symbol (string->symbol "cond")))

(define literal.285 (value-symbol (string->symbol "else")))

(define literal.286 (value-cons (value-number (exact-number 15)) (value-null)))

(define literal.287 (value-symbol (string->symbol "set!")))

(define literal.288 (value-cons (value-number (exact-number 14)) (value-null)))

(define literal.289 (value-symbol (string->symbol "if")))

(define literal.290 (value-cons (value-number (exact-number 13)) (value-null)))

(define literal.291 (value-symbol (string->symbol "lambda")))

(define literal.292 (value-cons (value-number (exact-number 12)) (value-null)))

(define literal.293 (value-cons (value-number (exact-number 11)) (value-null)))

(define literal.294 (value-cons (value-number (exact-number 9)) (value-null)))

(define literal.295 (value-symbol (string->symbol "cons")))

(define literal.296 (value-cons (value-number (exact-number 7)) (value-null)))

(define literal.297 (value-cons (value-number (exact-number 6)) (value-null)))

(define literal.298 (value-symbol (string->symbol "quote")))

(define literal.299 (value-cons (value-number (exact-number 5)) (value-null)))

(define literal.300 (value-cons (value-number (exact-number 32)) (value-null)))

(define literal.301 (value-cons (value-number (exact-number 30)) (value-null)))

(define literal.302
  (value-cons
    (value-number (exact-number 29))
    (value-cons (value-number (exact-number 31)) (value-null))))

(define literal.303
  (value-cons
    (value-number (exact-number 8))
    (value-cons (value-number (exact-number 10)) (value-null))))

(define literal.304
  (value-cons
    (value-number (exact-number 0))
    (value-cons
      (value-number (exact-number 1))
      (value-cons
        (value-number (exact-number 2))
        (value-cons
          (value-number (exact-number 3))
          (value-cons (value-number (exact-number 4)) (value-null)))))))

(define literal.305 (value-symbol (string->symbol "quote")))

(define literal.306 (value-symbol (string->symbol "eqv?")))

(define literal.307 (value-symbol (string->symbol "eq?")))

(define literal.308 (value-symbol (string->symbol "equal?")))

(define literal.309 (value-symbol (string->symbol "open-input-file")))

(define literal.310 (value-symbol (string->symbol "eof-object?")))

(define literal.311 (value-symbol (string->symbol "read")))

(define literal.312 (value-symbol (string->symbol "write")))

(define literal.313 (value-symbol (string->symbol "display")))

(define literal.314 (value-symbol (string->symbol "newline")))

(define literal.315 (value-symbol (string->symbol "pretty-print")))

(define literal.316 (value-symbol (string->symbol "boolean?")))

(define literal.317 (value-symbol (string->symbol "not")))

(define literal.318 (value-symbol (string->symbol "pair?")))

(define literal.319 (value-symbol (string->symbol "null?")))

(define literal.320 (value-symbol (string->symbol "list?")))

(define literal.321 (value-symbol (string->symbol "cons")))

(define literal.322 (value-symbol (string->symbol "car")))

(define literal.323 (value-symbol (string->symbol "cdr")))

(define literal.324 (value-symbol (string->symbol "set-car!")))

(define literal.325 (value-symbol (string->symbol "set-cdr!")))

(define literal.326 (value-symbol (string->symbol "caar")))

(define literal.327 (value-symbol (string->symbol "cdar")))

(define literal.328 (value-symbol (string->symbol "cadr")))

(define literal.329 (value-symbol (string->symbol "cddr")))

(define literal.330 (value-symbol (string->symbol "caaar")))

(define literal.331 (value-symbol (string->symbol "cdaar")))

(define literal.332 (value-symbol (string->symbol "cadar")))

(define literal.333 (value-symbol (string->symbol "cddar")))

(define literal.334 (value-symbol (string->symbol "caadr")))

(define literal.335 (value-symbol (string->symbol "cdadr")))

(define literal.336 (value-symbol (string->symbol "caddr")))

(define literal.337 (value-symbol (string->symbol "cdddr")))

(define literal.338 (value-symbol (string->symbol "cadddr")))

(define literal.339 (value-symbol (string->symbol "cddddr")))

(define literal.340 (value-symbol (string->symbol "list")))

(define literal.341 (value-symbol (string->symbol "length")))

(define literal.342 (value-symbol (string->symbol "append")))

(define literal.343 (value-symbol (string->symbol "reverse")))

(define literal.344 (value-symbol (string->symbol "list-ref")))

(define literal.345 (value-symbol (string->symbol "memq")))

(define literal.346 (value-symbol (string->symbol "memv")))

(define literal.347 (value-symbol (string->symbol "member")))

(define literal.348 (value-symbol (string->symbol "assq")))

(define literal.349 (value-symbol (string->symbol "assv")))

(define literal.350 (value-symbol (string->symbol "assoc")))

(define literal.351 (value-symbol (string->symbol "symbol?")))

(define literal.352 (value-symbol (string->symbol "symbol->string")))

(define literal.353 (value-symbol (string->symbol "string->symbol")))

(define literal.354 (value-symbol (string->symbol "number?")))

(define literal.355 (value-symbol (string->symbol "+")))

(define literal.356 (value-symbol (string->symbol "-")))

(define literal.357 (value-symbol (string->symbol "*")))

(define literal.358 (value-symbol (string->symbol "/")))

(define literal.359 (value-symbol (string->symbol "number->string")))

(define literal.360 (value-symbol (string->symbol "string->number")))

(define literal.361 (value-symbol (string->symbol "char?")))

(define literal.362 (value-symbol (string->symbol "char->integer")))

(define literal.363 (value-symbol (string->symbol "integer->char")))

(define literal.364 (value-symbol (string->symbol "string?")))

(define literal.365 (value-symbol (string->symbol "vector?")))

(define literal.366 (value-symbol (string->symbol "make-vector")))

(define literal.367 (value-symbol (string->symbol "vector-length")))

(define literal.368 (value-symbol (string->symbol "vector-ref")))

(define literal.369 (value-symbol (string->symbol "vector-set!")))

(define literal.370 (value-symbol (string->symbol "procedure?")))

(define literal.371 (value-symbol (string->symbol "map")))

(define literal.372 (value-symbol (string->symbol "foreach")))

(define literal.373 (value-symbol (string->symbol "call-with-current-continuation")))

(define literal.374 (value-symbol (string->symbol ":")))

(define source/gen-binding (ref (value-uninitialized)))

(ref-set! source/gen-binding primitive-value/cons)

(define source/binding-key (ref (value-uninitialized)))

(ref-set! source/binding-key primitive-value/car)

(define source/binding-value (ref (value-uninitialized)))

(ref-set! source/binding-value primitive-value/cdr)

(define source/key-show (ref (value-uninitialized)))

(define body/source/key-show (lambda (source/key) source/key))

(ref-set! source/key-show (value-procedure (ref (unit)) (function-1 body/source/key-show)))

(define source/value-show (ref (value-uninitialized)))

(define body/source/value-show (lambda (source/value) source/value))

(ref-set! source/value-show (value-procedure (ref (unit)) (function-1 body/source/value-show)))

(define source/binding-show (ref (value-uninitialized)))

(define body/source/binding-show
  (lambda (source/binding)
    (primitive/cons/2
      (body/source/key-show (invoke-1 (binding-value source/binding-key) source/binding))
      (primitive/cons/2
        literal
        (body/source/value-show (invoke-1 (binding-value source/binding-value) source/binding))))))

(ref-set! source/binding-show (value-procedure (ref (unit)) (function-1 body/source/binding-show)))

(define source/dynamic-empty-env (ref (value-uninitialized)))

(ref-set! source/dynamic-empty-env (value-null))

(define source/extend-env-with-binding (ref (value-uninitialized)))

(define body/source/extend-env-with-binding
  (lambda (source/env source/binding.1) (primitive/cons/2 source/binding.1 source/env)))

(ref-set!
  source/extend-env-with-binding
  (value-procedure (ref (unit)) (function-2 body/source/extend-env-with-binding)))

(define source/extend-env-with-env (ref (value-uninitialized)))

(define body/source/extend-env-with-env
  (lambda (source/env.1 source/ext-env) (primitive/append/2 source/ext-env source/env.1)))

(ref-set!
  source/extend-env-with-env
  (value-procedure (ref (unit)) (function-2 body/source/extend-env-with-env)))

(define source/dynamic-lookup (ref (value-uninitialized)))

(define body/source/dynamic-lookup
  (lambda (source/x source/l) (primitive/assv/2 source/x source/l)))

(ref-set!
  source/dynamic-lookup
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-lookup)))

(define source/env->list (ref (value-uninitialized)))

(define body/source/env->list (lambda (source/e) source/e))

(ref-set! source/env->list (value-procedure (ref (unit)) (function-1 body/source/env->list)))

(define source/env-show (ref (value-uninitialized)))

(define body/source/env-show
  (lambda (source/env.2) (primitive/map/2 (binding-value source/binding-show) source/env.2)))

(ref-set! source/env-show (value-procedure (ref (unit)) (function-1 body/source/env-show)))

(define source/syntactic-keywords (ref (value-uninitialized)))

(ref-set! source/syntactic-keywords literal.1)

(define source/dynamic-parse-datum (ref (value-uninitialized)))

(define body/source/dynamic-parse-datum
  (lambda (source/e.1)
    (if (value-truth? (primitive/null?/1 source/e.1))
      (body/source/dynamic-parse-action-null-const)
      (if (value-truth? (primitive/boolean?/1 source/e.1))
        (body/source/dynamic-parse-action-boolean-const source/e.1)
        (if (value-truth? (primitive/char?/1 source/e.1))
          (body/source/dynamic-parse-action-char-const source/e.1)
          (if (value-truth? (primitive/number?/1 source/e.1))
            (body/source/dynamic-parse-action-number-const source/e.1)
            (if (value-truth? (primitive/string?/1 source/e.1))
              (body/source/dynamic-parse-action-string-const source/e.1)
              (if (value-truth? (primitive/symbol?/1 source/e.1))
                (body/source/dynamic-parse-action-symbol-const source/e.1)
                (if (value-truth? (primitive/vector?/1 source/e.1))
                  (body/source/dynamic-parse-action-vector-const
                    (primitive/map/2
                      (binding-value source/dynamic-parse-datum)
                      (primitive/vector->list/1 source/e.1)))
                  (if (value-truth? (primitive/pair?/1 source/e.1))
                    (body/source/dynamic-parse-action-pair-const
                      (body/source/dynamic-parse-datum (primitive/car/1 source/e.1))
                      (body/source/dynamic-parse-datum (primitive/cdr/1 source/e.1)))
                    (primitive/error/3 literal.2 literal.3 source/e.1)))))))))))

(ref-set!
  source/dynamic-parse-datum
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-datum)))

(define source/dynamic-parse-formal (ref (value-uninitialized)))

(define body/source/dynamic-parse-formal
  (lambda (source/f-env source/e.2)
    (if (value-truth? (primitive/symbol?/1 source/e.2))
      (if (value-truth? (primitive/memq/2 source/e.2 (binding-value source/syntactic-keywords)))
        (primitive/error/3 literal.8 literal.9 source/e.2)
        (if (value-truth? (body/source/dynamic-lookup source/e.2 source/f-env))
          (primitive/error/3 literal.6 literal.7 source/e.2)
          ((lambda (source/dynamic-parse-action-result) (primitive/cons/2 (invoke-2 (binding-value source/gen-binding) source/e.2 source/dynamic-parse-action-result) source/dynamic-parse-action-result))
            (body/source/dynamic-parse-action-var-def source/e.2))))
      (primitive/error/3 literal.4 literal.5 source/e.2))))

(ref-set!
  source/dynamic-parse-formal
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-formal)))

(define source/dynamic-parse-formal* (ref (value-uninitialized)))

(define body/source/dynamic-parse-formal*
  (lambda (source/formals)
    ((lambda () (let ((source/pf* #f) (body/source/pf* #f)) (set! source/pf* (ref (value-uninitialized))) (set! body/source/pf* (lambda (source/f-env.1 source/results source/formals.1) (if (value-truth? (primitive/null?/1 source/formals.1)) (primitive/cons/2 source/f-env.1 source/results) (if (value-truth? (primitive/pair?/1 source/formals.1)) ((lambda (source/fst-formal) ((lambda (source/binding-result) ((lambda (source/binding.2) ((lambda (source/var-result) ((lambda () (body/source/pf* (body/source/extend-env-with-binding source/f-env.1 source/binding.2) (primitive/cons/2 source/var-result source/results) (primitive/cdr/1 source/formals.1))))) (primitive/cdr/1 source/binding-result))) (primitive/car/1 source/binding-result))) (body/source/dynamic-parse-formal source/f-env.1 source/fst-formal))) (primitive/car/1 source/formals.1)) (primitive/error/3 literal.10 literal.11 source/formals.1))))) (ref-set! source/pf* (value-procedure (ref (unit)) (function-3 body/source/pf*))) ((lambda (source/renv-rres) (primitive/cons/2 (primitive/car/1 source/renv-rres) (primitive/reverse/1 (primitive/cdr/1 source/renv-rres)))) (body/source/pf* (binding-value source/dynamic-empty-env) (value-null) source/formals))))
)))

(ref-set!
  source/dynamic-parse-formal*
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-formal*)))

(define source/dynamic-parse-formals (ref (value-uninitialized)))

(define body/source/dynamic-parse-formals
  (lambda (source/formals.2)
    ((lambda () (let ((source/pfs #f) (body/source/pfs #f)) (set! source/pfs (ref (value-uninitialized))) (set! body/source/pfs (lambda (source/f-env.2 source/formals.3) (if (value-truth? (primitive/null?/1 source/formals.3)) (primitive/cons/2 (binding-value source/dynamic-empty-env) (body/source/dynamic-parse-action-null-formal)) (if (value-truth? (primitive/pair?/1 source/formals.3)) ((lambda (source/fst-formal.1) ((lambda (source/rem-formals) ((lambda (source/bind-res.1) ((lambda (source/bind.1) ((lambda (source/res.1) ((lambda (source/nf-env) ((lambda (source/renv-res*) ((lambda (source/renv) ((lambda (source/res*) ((lambda () (primitive/cons/2 (body/source/extend-env-with-binding source/renv source/bind.1) (body/source/dynamic-parse-action-pair-formal source/res.1 source/res*))))) (primitive/cdr/1 source/renv-res*))) (primitive/car/1 source/renv-res*))) (body/source/pfs source/nf-env source/rem-formals))) (body/source/extend-env-with-binding source/f-env.2 source/bind.1))) (primitive/cdr/1 source/bind-res.1))) (primitive/car/1 source/bind-res.1))) (body/source/dynamic-parse-formal source/f-env.2 source/fst-formal.1))) (primitive/cdr/1 source/formals.3))) (primitive/car/1 source/formals.3)) ((lambda (source/bind-res) ((lambda (source/bind) ((lambda (source/res) ((lambda () (primitive/cons/2 (body/source/extend-env-with-binding (binding-value source/dynamic-empty-env) source/bind) source/res)))) (primitive/cdr/1 source/bind-res))) (primitive/car/1 source/bind-res))) (body/source/dynamic-parse-formal source/f-env.2 source/formals.3)))))) (ref-set! source/pfs (value-procedure (ref (unit)) (function-2 body/source/pfs))) (body/source/pfs (binding-value source/dynamic-empty-env) source/formals.2)))
)))

(ref-set!
  source/dynamic-parse-formals
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-formals)))

(define source/dynamic-parse-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-expression
  (lambda (source/env.3 source/e.3)
    (if (value-truth? (primitive/symbol?/1 source/e.3))
      (body/source/dynamic-parse-variable source/env.3 source/e.3)
      (if (value-truth? (primitive/pair?/1 source/e.3))
        ((lambda (source/op source/args) ((lambda (source/value.1) (if (value-truth? (primitive/memv/2 source/value.1 literal.25)) (body/source/dynamic-parse-quote source/env.3 source/args) ((lambda (source/value.2) (if (value-truth? (primitive/memv/2 source/value.2 literal.24)) (body/source/dynamic-parse-lambda source/env.3 source/args) ((lambda (source/value.3) (if (value-truth? (primitive/memv/2 source/value.3 literal.23)) (body/source/dynamic-parse-if source/env.3 source/args) ((lambda (source/value.4) (if (value-truth? (primitive/memv/2 source/value.4 literal.22)) (body/source/dynamic-parse-set source/env.3 source/args) ((lambda (source/value.5) (if (value-truth? (primitive/memv/2 source/value.5 literal.21)) (body/source/dynamic-parse-begin source/env.3 source/args) ((lambda (source/value.6) (if (value-truth? (primitive/memv/2 source/value.6 literal.20)) (body/source/dynamic-parse-cond source/env.3 source/args) ((lambda (source/value.7) (if (value-truth? (primitive/memv/2 source/value.7 literal.19)) (body/source/dynamic-parse-case source/env.3 source/args) ((lambda (source/value.8) (if (value-truth? (primitive/memv/2 source/value.8 literal.18)) (body/source/dynamic-parse-and source/env.3 source/args) ((lambda (source/value.9) (if (value-truth? (primitive/memv/2 source/value.9 literal.17)) (body/source/dynamic-parse-or source/env.3 source/args) ((lambda (source/value.10) (if (value-truth? (primitive/memv/2 source/value.10 literal.16)) (body/source/dynamic-parse-let source/env.3 source/args) ((lambda (source/value.11) (if (value-truth? (primitive/memv/2 source/value.11 literal.15)) (body/source/dynamic-parse-let* source/env.3 source/args) ((lambda (source/value.12) (if (value-truth? (primitive/memv/2 source/value.12 literal.14)) (body/source/dynamic-parse-letrec source/env.3 source/args) ((lambda (source/value.13) (if (value-truth? (primitive/memv/2 source/value.13 literal.13)) (body/source/dynamic-parse-do source/env.3 source/args) ((lambda (source/value.14) (if (value-truth? (primitive/memv/2 source/value.14 literal.12)) (body/source/dynamic-parse-quasiquote source/env.3 source/args) ((lambda (source/value.15) (body/source/dynamic-parse-procedure-call source/env.3 source/op source/args)) source/value.14))) source/value.13))) source/value.12))) source/value.11))) source/value.10))) source/value.9))) source/value.8))) source/value.7))) source/value.6))) source/value.5))) source/value.4))) source/value.3))) source/value.2))) source/value.1))) source/op))
          (primitive/car/1 source/e.3)
          (primitive/cdr/1 source/e.3))
        (body/source/dynamic-parse-datum source/e.3)))))

(ref-set!
  source/dynamic-parse-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-expression)))

(define source/dynamic-parse-expression* (ref (value-uninitialized)))

(define body/source/dynamic-parse-expression*
  (lambda (source/env.4 source/exprs)
    ((lambda () (let ((source/pe* #f) (body/source/pe* #f)) (set! source/pe* (ref (value-uninitialized))) (set! body/source/pe* (lambda (source/results.1 source/es) (if (value-truth? (primitive/null?/1 source/es)) source/results.1 (if (value-truth? (primitive/pair?/1 source/es)) (body/source/pe* (primitive/cons/2 (body/source/dynamic-parse-expression source/env.4 (primitive/car/1 source/es)) source/results.1) (primitive/cdr/1 source/es)) (primitive/error/3 literal.26 literal.27 source/es))))) (ref-set! source/pe* (value-procedure (ref (unit)) (function-2 body/source/pe*))) (primitive/reverse/1 (body/source/pe* (value-null) source/exprs))))
)))

(ref-set!
  source/dynamic-parse-expression*
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-expression*)))

(define source/dynamic-parse-expressions (ref (value-uninitialized)))

(define body/source/dynamic-parse-expressions
  (lambda (source/env.5 source/exprs.1)
    (if (value-truth? (primitive/null?/1 source/exprs.1))
      (body/source/dynamic-parse-action-null-arg)
      (if (value-truth? (primitive/pair?/1 source/exprs.1))
        ((lambda (source/fst-expr) ((lambda (source/rem-exprs) ((lambda (source/fst-res) ((lambda (source/rem-res) ((lambda () (body/source/dynamic-parse-action-pair-arg source/fst-res source/rem-res)))) (body/source/dynamic-parse-expressions source/env.5 source/rem-exprs))) (body/source/dynamic-parse-expression source/env.5 source/fst-expr))) (primitive/cdr/1 source/exprs.1)))
          (primitive/car/1 source/exprs.1))
        (primitive/error/3 literal.28 literal.29 source/exprs.1)))))

(ref-set!
  source/dynamic-parse-expressions
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-expressions)))

(define source/dynamic-parse-variable (ref (value-uninitialized)))

(define body/source/dynamic-parse-variable
  (lambda (source/env.6 source/e.4)
    (if (value-truth? (primitive/symbol?/1 source/e.4))
      (if (value-truth? (primitive/memq/2 source/e.4 (binding-value source/syntactic-keywords)))
        (primitive/error/3 literal.32 literal.33 source/e.4)
        ((lambda (source/assoc-var-def) (if (value-truth? source/assoc-var-def) (body/source/dynamic-parse-action-variable (invoke-1 (binding-value source/binding-value) source/assoc-var-def)) (body/source/dynamic-parse-action-identifier source/e.4)))
          (body/source/dynamic-lookup source/e.4 source/env.6)))
      (primitive/error/3 literal.30 literal.31 source/e.4))))

(ref-set!
  source/dynamic-parse-variable
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-variable)))

(define source/dynamic-parse-procedure-call (ref (value-uninitialized)))

(define body/source/dynamic-parse-procedure-call
  (lambda (source/env.7 source/op.1 source/args.1)
    (body/source/dynamic-parse-action-procedure-call
      (body/source/dynamic-parse-expression source/env.7 source/op.1)
      (body/source/dynamic-parse-expressions source/env.7 source/args.1))))

(ref-set!
  source/dynamic-parse-procedure-call
  (value-procedure (ref (unit)) (function-3 body/source/dynamic-parse-procedure-call)))

(define source/dynamic-parse-quote (ref (value-uninitialized)))

(define body/source/dynamic-parse-quote
  (lambda (source/env.8 source/args.2)
    (if (value-truth? (body/source/list-of-1? source/args.2))
      (body/source/dynamic-parse-datum (primitive/car/1 source/args.2))
      (primitive/error/3 literal.34 literal.35 source/args.2))))

(ref-set!
  source/dynamic-parse-quote
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-quote)))

(define source/dynamic-parse-lambda (ref (value-uninitialized)))

(define body/source/dynamic-parse-lambda
  (lambda (source/env.9 source/args.3)
    (if (value-truth? (primitive/pair?/1 source/args.3))
      ((lambda (source/formals.4) ((lambda (source/body) ((lambda (source/nenv-fresults) ((lambda (source/nenv) ((lambda (source/fresults) ((lambda () (body/source/dynamic-parse-action-lambda-expression source/fresults (body/source/dynamic-parse-body (body/source/extend-env-with-env source/env.9 source/nenv) source/body))))) (primitive/cdr/1 source/nenv-fresults))) (primitive/car/1 source/nenv-fresults))) (body/source/dynamic-parse-formals source/formals.4))) (primitive/cdr/1 source/args.3)))
        (primitive/car/1 source/args.3))
      (primitive/error/3 literal.36 literal.37 source/args.3))))

(ref-set!
  source/dynamic-parse-lambda
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-lambda)))

(define source/dynamic-parse-body (ref (value-uninitialized)))

(define body/source/dynamic-parse-body
  (lambda (source/env.10 source/body.1)
    (let ((source/def-var* #f) (body/source/def-var* #f) (source/def-var #f) (body/source/def-var #f))
      (set! source/def-var* (ref (value-uninitialized)))
      (set!
        body/source/def-var*
        (lambda (source/f-env.3 source/body.2)
          (if (value-truth? (primitive/pair?/1 source/body.2))
            ((lambda (source/n-env) (if (value-truth? source/n-env) (body/source/def-var* source/n-env (primitive/cdr/1 source/body.2)) source/f-env.3))
              (body/source/def-var source/f-env.3 (primitive/car/1 source/body.2)))
            source/f-env.3)))
      (ref-set! source/def-var* (value-procedure (ref (unit)) (function-2 body/source/def-var*)))
      (set! source/def-var (ref (value-uninitialized)))
      (set!
        body/source/def-var
        (lambda (source/f-env.4 source/clause)
          (if (value-truth? (primitive/pair?/1 source/clause))
            ((lambda (source/value.16) (if (value-truth? (primitive/memv/2 source/value.16 literal.39)) (if (value-truth? (primitive/pair?/1 (primitive/cdr/1 source/clause))) ((lambda (source/pattern) (if (value-truth? (primitive/symbol?/1 source/pattern)) (body/source/extend-env-with-binding source/f-env.4 (invoke-2 (binding-value source/gen-binding) source/pattern (body/source/dynamic-parse-action-var-def source/pattern))) (if (value-truth? (if (value-truth? (primitive/pair?/1 source/pattern)) (primitive/symbol?/1 (primitive/car/1 source/pattern)) (value-boolean #f))) (body/source/extend-env-with-binding source/f-env.4 (invoke-2 (binding-value source/gen-binding) (primitive/car/1 source/pattern) (body/source/dynamic-parse-action-var-def (primitive/car/1 source/pattern)))) source/f-env.4))) (primitive/cadr/1 source/clause)) source/f-env.4) ((lambda (source/value.17) (if (value-truth? (primitive/memv/2 source/value.17 literal.38)) (body/source/def-var* source/f-env.4 (primitive/cdr/1 source/clause)) ((lambda (source/value.18) (value-boolean #f)) source/value.17))) source/value.16)))
              (primitive/car/1 source/clause))
            (value-boolean #f))))
      (ref-set! source/def-var (value-procedure (ref (unit)) (function-2 body/source/def-var)))
      (if (value-truth? (primitive/pair?/1 source/body.1))
        (body/source/dynamic-parse-command*
          (body/source/def-var* source/env.10 source/body.1)
          source/body.1)
        (primitive/error/3 literal.40 literal.41 source/body.1)))))

(ref-set!
  source/dynamic-parse-body
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-body)))

(define source/dynamic-parse-if (ref (value-uninitialized)))

(define body/source/dynamic-parse-if
  (lambda (source/env.11 source/args.4)
    (if (value-truth? (body/source/list-of-3? source/args.4))
      (body/source/dynamic-parse-action-conditional
        (body/source/dynamic-parse-expression source/env.11 (primitive/car/1 source/args.4))
        (body/source/dynamic-parse-expression source/env.11 (primitive/cadr/1 source/args.4))
        (body/source/dynamic-parse-expression source/env.11 (primitive/caddr/1 source/args.4)))
      (if (value-truth? (body/source/list-of-2? source/args.4))
        (body/source/dynamic-parse-action-conditional
          (body/source/dynamic-parse-expression source/env.11 (primitive/car/1 source/args.4))
          (body/source/dynamic-parse-expression source/env.11 (primitive/cadr/1 source/args.4))
          (body/source/dynamic-parse-action-empty))
        (primitive/error/3 literal.42 literal.43 source/args.4)))))

(ref-set!
  source/dynamic-parse-if
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-if)))

(define source/dynamic-parse-set (ref (value-uninitialized)))

(define body/source/dynamic-parse-set
  (lambda (source/env.12 source/args.5)
    (if (value-truth? (body/source/list-of-2? source/args.5))
      (body/source/dynamic-parse-action-assignment
        (body/source/dynamic-parse-variable source/env.12 (primitive/car/1 source/args.5))
        (body/source/dynamic-parse-expression source/env.12 (primitive/cadr/1 source/args.5)))
      (primitive/error/3 literal.44 literal.45 source/args.5))))

(ref-set!
  source/dynamic-parse-set
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-set)))

(define source/dynamic-parse-begin (ref (value-uninitialized)))

(define body/source/dynamic-parse-begin
  (lambda (source/env.13 source/args.6)
    (body/source/dynamic-parse-action-begin-expression
      (body/source/dynamic-parse-body source/env.13 source/args.6))))

(ref-set!
  source/dynamic-parse-begin
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-begin)))

(define source/dynamic-parse-cond (ref (value-uninitialized)))

(define body/source/dynamic-parse-cond
  (lambda (source/env.14 source/args.7)
    (if (value-truth? (if (value-truth? (primitive/pair?/1 source/args.7)) (primitive/list?/1 source/args.7) (value-boolean #f)))
      (body/source/dynamic-parse-action-cond-expression
        (primitive/map/2
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/e.5) (body/source/dynamic-parse-cond-clause source/env.14 source/e.5))))
          source/args.7))
      (primitive/error/3 literal.46 literal.47 source/args.7))))

(ref-set!
  source/dynamic-parse-cond
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-cond)))

(define source/dynamic-parse-cond-clause (ref (value-uninitialized)))

(define body/source/dynamic-parse-cond-clause
  (lambda (source/env.15 source/e.6)
    (if (value-truth? (primitive/pair?/1 source/e.6))
      (primitive/cons/2
        (if (value-truth? (primitive/eqv?/2 (primitive/car/1 source/e.6) literal.50))
          (body/source/dynamic-parse-action-empty)
          (body/source/dynamic-parse-expression source/env.15 (primitive/car/1 source/e.6)))
        (body/source/dynamic-parse-body source/env.15 (primitive/cdr/1 source/e.6)))
      (primitive/error/3 literal.48 literal.49 source/e.6))))

(ref-set!
  source/dynamic-parse-cond-clause
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-cond-clause)))

(define source/dynamic-parse-and (ref (value-uninitialized)))

(define body/source/dynamic-parse-and
  (lambda (source/env.16 source/args.8)
    (if (value-truth? (primitive/list?/1 source/args.8))
      (body/source/dynamic-parse-action-and-expression
        (body/source/dynamic-parse-expression* source/env.16 source/args.8))
      (primitive/error/3 literal.51 literal.52 source/args.8))))

(ref-set!
  source/dynamic-parse-and
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-and)))

(define source/dynamic-parse-or (ref (value-uninitialized)))

(define body/source/dynamic-parse-or
  (lambda (source/env.17 source/args.9)
    (if (value-truth? (primitive/list?/1 source/args.9))
      (body/source/dynamic-parse-action-or-expression
        (body/source/dynamic-parse-expression* source/env.17 source/args.9))
      (primitive/error/3 literal.53 literal.54 source/args.9))))

(ref-set!
  source/dynamic-parse-or
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-or)))

(define source/dynamic-parse-case (ref (value-uninitialized)))

(define body/source/dynamic-parse-case
  (lambda (source/env.18 source/args.10)
    (if (value-truth? (if (value-truth? (primitive/list?/1 source/args.10)) (primitive/>/2 (primitive/length/1 source/args.10) (value-number (exact-number 1))) (value-boolean #f)))
      (body/source/dynamic-parse-action-case-expression
        (body/source/dynamic-parse-expression source/env.18 (primitive/car/1 source/args.10))
        (primitive/map/2
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/e.7) (body/source/dynamic-parse-case-clause source/env.18 source/e.7))))
          (primitive/cdr/1 source/args.10)))
      (primitive/error/3 literal.55 literal.56 source/args.10))))

(ref-set!
  source/dynamic-parse-case
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-case)))

(define source/dynamic-parse-case-clause (ref (value-uninitialized)))

(define body/source/dynamic-parse-case-clause
  (lambda (source/env.19 source/e.8)
    (if (value-truth? (primitive/pair?/1 source/e.8))
      (primitive/cons/2
        (if (value-truth? (primitive/eqv?/2 (primitive/car/1 source/e.8) literal.61))
          (primitive/list/1 (body/source/dynamic-parse-action-empty))
          (if (value-truth? (primitive/list?/1 (primitive/car/1 source/e.8)))
            (primitive/map/2
              (binding-value source/dynamic-parse-datum)
              (primitive/car/1 source/e.8))
            (primitive/error/3 literal.59 literal.60 (primitive/car/1 source/e.8))))
        (body/source/dynamic-parse-body source/env.19 (primitive/cdr/1 source/e.8)))
      (primitive/error/3 literal.57 literal.58 source/e.8))))

(ref-set!
  source/dynamic-parse-case-clause
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-case-clause)))

(define source/dynamic-parse-let (ref (value-uninitialized)))

(define body/source/dynamic-parse-let
  (lambda (source/env.20 source/args.11)
    (if (value-truth? (primitive/pair?/1 source/args.11))
      (if (value-truth? (primitive/symbol?/1 (primitive/car/1 source/args.11)))
        (body/source/dynamic-parse-named-let source/env.20 source/args.11)
        (body/source/dynamic-parse-normal-let source/env.20 source/args.11))
      (primitive/error/3 literal.62 literal.63 source/args.11))))

(ref-set!
  source/dynamic-parse-let
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-let)))

(define source/dynamic-parse-normal-let (ref (value-uninitialized)))

(define body/source/dynamic-parse-normal-let
  (lambda (source/env.21 source/args.12)
    ((lambda (source/bindings) ((lambda (source/body.3) ((lambda (source/env-ast) ((lambda (source/nenv.1) ((lambda (source/bresults) ((lambda () (body/source/dynamic-parse-action-let-expression source/bresults (body/source/dynamic-parse-body (body/source/extend-env-with-env source/env.21 source/nenv.1) source/body.3))))) (primitive/cdr/1 source/env-ast))) (primitive/car/1 source/env-ast))) (body/source/dynamic-parse-parallel-bindings source/env.21 source/bindings))) (primitive/cdr/1 source/args.12)))
      (primitive/car/1 source/args.12))))

(ref-set!
  source/dynamic-parse-normal-let
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-normal-let)))

(define source/dynamic-parse-named-let (ref (value-uninitialized)))

(define body/source/dynamic-parse-named-let
  (lambda (source/env.22 source/args.13)
    (if (value-truth? (primitive/pair?/1 (primitive/cdr/1 source/args.13)))
      ((lambda (source/variable.1) ((lambda (source/bindings.1) ((lambda (source/body.4) ((lambda (source/vbind-vres) ((lambda (source/vbind) ((lambda (source/vres) ((lambda (source/env-ast.1) ((lambda (source/nenv.2) ((lambda (source/bresults.1) ((lambda () (body/source/dynamic-parse-action-named-let-expression source/vres source/bresults.1 (body/source/dynamic-parse-body (body/source/extend-env-with-env (body/source/extend-env-with-binding source/env.22 source/vbind) source/nenv.2) source/body.4))))) (primitive/cdr/1 source/env-ast.1))) (primitive/car/1 source/env-ast.1))) (body/source/dynamic-parse-parallel-bindings source/env.22 source/bindings.1))) (primitive/cdr/1 source/vbind-vres))) (primitive/car/1 source/vbind-vres))) (body/source/dynamic-parse-formal (binding-value source/dynamic-empty-env) source/variable.1))) (primitive/cddr/1 source/args.13))) (primitive/cadr/1 source/args.13)))
        (primitive/car/1 source/args.13))
      (primitive/error/3 literal.64 literal.65 source/args.13))))

(ref-set!
  source/dynamic-parse-named-let
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-named-let)))

(define source/dynamic-parse-parallel-bindings (ref (value-uninitialized)))

(define body/source/dynamic-parse-parallel-bindings
  (lambda (source/env.23 source/bindings.2)
    (if (value-truth? (body/source/list-of-list-of-2s? source/bindings.2))
      ((lambda (source/env-formals-asg) ((lambda (source/nenv.3) ((lambda (source/bresults.2) ((lambda (source/exprs-asg) ((lambda () (primitive/cons/2 source/nenv.3 (primitive/cons/2 source/bresults.2 source/exprs-asg))))) (body/source/dynamic-parse-expression* source/env.23 (primitive/map/2 primitive-value/cadr source/bindings.2)))) (primitive/cdr/1 source/env-formals-asg))) (primitive/car/1 source/env-formals-asg)))
        (body/source/dynamic-parse-formal* (primitive/map/2 primitive-value/car source/bindings.2)))
      (primitive/error/3 literal.66 literal.67 source/bindings.2))))

(ref-set!
  source/dynamic-parse-parallel-bindings
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-parallel-bindings)))

(define source/dynamic-parse-let* (ref (value-uninitialized)))

(define body/source/dynamic-parse-let*
  (lambda (source/env.24 source/args.14)
    (if (value-truth? (primitive/pair?/1 source/args.14))
      ((lambda (source/bindings.3) ((lambda (source/body.5) ((lambda (source/env-ast.2) ((lambda (source/nenv.4) ((lambda (source/bresults.3) ((lambda () (body/source/dynamic-parse-action-let*-expression source/bresults.3 (body/source/dynamic-parse-body (body/source/extend-env-with-env source/env.24 source/nenv.4) source/body.5))))) (primitive/cdr/1 source/env-ast.2))) (primitive/car/1 source/env-ast.2))) (body/source/dynamic-parse-sequential-bindings source/env.24 source/bindings.3))) (primitive/cdr/1 source/args.14)))
        (primitive/car/1 source/args.14))
      (primitive/error/3 literal.68 literal.69 source/args.14))))

(ref-set!
  source/dynamic-parse-let*
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-let*)))

(define source/dynamic-parse-sequential-bindings (ref (value-uninitialized)))

(define body/source/dynamic-parse-sequential-bindings
  (lambda (source/env.25 source/bindings.4)
    ((lambda () (let ((source/psb #f) (body/source/psb #f)) (set! source/psb (ref (value-uninitialized))) (set! body/source/psb (lambda (source/f-env.5 source/c-env source/var-defs source/expr-asgs source/binds) (if (value-truth? (primitive/null?/1 source/binds)) (primitive/cons/2 source/f-env.5 (primitive/cons/2 source/var-defs source/expr-asgs)) (if (value-truth? (primitive/pair?/1 source/binds)) ((lambda (source/fst-bind) (if (value-truth? (body/source/list-of-2? source/fst-bind)) ((lambda (source/fbinding-bres) ((lambda (source/fbind) ((lambda (source/bres) ((lambda (source/new-expr-asg) ((lambda () (body/source/psb (body/source/extend-env-with-binding source/f-env.5 source/fbind) (body/source/extend-env-with-binding source/c-env source/fbind) (primitive/cons/2 source/bres source/var-defs) (primitive/cons/2 source/new-expr-asg source/expr-asgs) (primitive/cdr/1 source/binds))))) (body/source/dynamic-parse-expression source/c-env (primitive/cadr/1 source/fst-bind)))) (primitive/cdr/1 source/fbinding-bres))) (primitive/car/1 source/fbinding-bres))) (body/source/dynamic-parse-formal source/f-env.5 (primitive/car/1 source/fst-bind))) (primitive/error/3 literal.72 literal.73 source/fst-bind))) (primitive/car/1 source/binds)) (primitive/error/3 literal.70 literal.71 source/binds))))) (ref-set! source/psb (value-procedure (ref (unit)) (function-5 body/source/psb))) ((lambda (source/env-vdefs-easgs) (primitive/cons/2 (primitive/car/1 source/env-vdefs-easgs) (primitive/cons/2 (primitive/reverse/1 (primitive/cadr/1 source/env-vdefs-easgs)) (primitive/reverse/1 (primitive/cddr/1 source/env-vdefs-easgs))))) (body/source/psb (binding-value source/dynamic-empty-env) source/env.25 (value-null) (value-null) source/bindings.4))))
)))

(ref-set!
  source/dynamic-parse-sequential-bindings
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-sequential-bindings)))

(define source/dynamic-parse-letrec (ref (value-uninitialized)))

(define body/source/dynamic-parse-letrec
  (lambda (source/env.26 source/args.15)
    (if (value-truth? (primitive/pair?/1 source/args.15))
      ((lambda (source/bindings.5) ((lambda (source/body.6) ((lambda (source/env-ast.3) ((lambda (source/nenv.5) ((lambda (source/bresults.4) ((lambda () (body/source/dynamic-parse-action-letrec-expression source/bresults.4 (body/source/dynamic-parse-body (body/source/extend-env-with-env source/env.26 source/nenv.5) source/body.6))))) (primitive/cdr/1 source/env-ast.3))) (primitive/car/1 source/env-ast.3))) (body/source/dynamic-parse-recursive-bindings source/env.26 source/bindings.5))) (primitive/cdr/1 source/args.15)))
        (primitive/car/1 source/args.15))
      (primitive/error/3 literal.74 literal.75 source/args.15))))

(ref-set!
  source/dynamic-parse-letrec
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-letrec)))

(define source/dynamic-parse-recursive-bindings (ref (value-uninitialized)))

(define body/source/dynamic-parse-recursive-bindings
  (lambda (source/env.27 source/bindings.6)
    (if (value-truth? (body/source/list-of-list-of-2s? source/bindings.6))
      ((lambda (source/env-formals-asg.1) ((lambda (source/formals-env) ((lambda (source/formals-res) ((lambda (source/exprs-asg.1) ((lambda () (primitive/cons/2 source/formals-env (primitive/cons/2 source/formals-res source/exprs-asg.1))))) (body/source/dynamic-parse-expression* (body/source/extend-env-with-env source/env.27 source/formals-env) (primitive/map/2 primitive-value/cadr source/bindings.6)))) (primitive/cdr/1 source/env-formals-asg.1))) (primitive/car/1 source/env-formals-asg.1)))
        (body/source/dynamic-parse-formal* (primitive/map/2 primitive-value/car source/bindings.6)))
      (primitive/error/3 literal.76 literal.77 source/bindings.6))))

(ref-set!
  source/dynamic-parse-recursive-bindings
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-recursive-bindings)))

(define source/dynamic-parse-do (ref (value-uninitialized)))

(define body/source/dynamic-parse-do
  (lambda (source/env.28 source/args.16) (primitive/error/2 literal.78 literal.79)))

(ref-set!
  source/dynamic-parse-do
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-do)))

(define source/dynamic-parse-quasiquote (ref (value-uninitialized)))

(define body/source/dynamic-parse-quasiquote
  (lambda (source/env.29 source/args.17) (primitive/error/2 literal.80 literal.81)))

(ref-set!
  source/dynamic-parse-quasiquote
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-quasiquote)))

(define source/dynamic-parse-command (ref (value-uninitialized)))

(define body/source/dynamic-parse-command
  (lambda (source/env.30 source/c)
    (if (value-truth? (primitive/pair?/1 source/c))
      ((lambda (source/op.2 source/args.18) ((lambda (source/value.19) (if (value-truth? (primitive/memv/2 source/value.19 literal.83)) (body/source/dynamic-parse-define source/env.30 source/args.18) ((lambda (source/value.20) (if (value-truth? (primitive/memv/2 source/value.20 literal.82)) (body/source/dynamic-parse-action-begin-expression (body/source/dynamic-parse-command* source/env.30 source/args.18)) ((lambda (source/value.21) (body/source/dynamic-parse-expression source/env.30 source/c)) source/value.20))) source/value.19))) source/op.2))
        (primitive/car/1 source/c)
        (primitive/cdr/1 source/c))
      (body/source/dynamic-parse-expression source/env.30 source/c))))

(ref-set!
  source/dynamic-parse-command
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-command)))

(define source/dynamic-parse-command* (ref (value-uninitialized)))

(define body/source/dynamic-parse-command*
  (lambda (source/env.31 source/commands)
    (if (value-truth? (primitive/list?/1 source/commands))
      (primitive/map/2
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/command)
              (body/source/dynamic-parse-command source/env.31 source/command))))
        source/commands)
      (primitive/error/3 literal.84 literal.85 source/commands))))

(ref-set!
  source/dynamic-parse-command*
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-command*)))

(define source/dynamic-parse-define (ref (value-uninitialized)))

(define body/source/dynamic-parse-define
  (lambda (source/env.32 source/args.19)
    (if (value-truth? (primitive/pair?/1 source/args.19))
      ((lambda (source/pattern.1 source/exp-or-body) (if (value-truth? (primitive/symbol?/1 source/pattern.1)) (if (value-truth? (body/source/list-of-1? source/exp-or-body)) (body/source/dynamic-parse-action-definition (body/source/dynamic-parse-variable source/env.32 source/pattern.1) (body/source/dynamic-parse-expression source/env.32 (primitive/car/1 source/exp-or-body))) (primitive/error/3 literal.90 literal.91 source/exp-or-body)) (if (value-truth? (primitive/pair?/1 source/pattern.1)) ((lambda (source/function-name) ((lambda (source/function-arg-names) ((lambda (source/env-ast.4) ((lambda (source/formals-env.1) ((lambda (source/formals-ast) ((lambda () (body/source/dynamic-parse-action-function-definition (body/source/dynamic-parse-variable source/env.32 source/function-name) source/formals-ast (body/source/dynamic-parse-body (body/source/extend-env-with-env source/env.32 source/formals-env.1) source/exp-or-body))))) (primitive/cdr/1 source/env-ast.4))) (primitive/car/1 source/env-ast.4))) (body/source/dynamic-parse-formals source/function-arg-names))) (primitive/cdr/1 source/pattern.1))) (primitive/car/1 source/pattern.1)) (primitive/error/3 literal.88 literal.89 source/pattern.1))))
        (primitive/car/1 source/args.19)
        (primitive/cdr/1 source/args.19))
      (primitive/error/3 literal.86 literal.87 source/args.19))))

(ref-set!
  source/dynamic-parse-define
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-define)))

(define source/forall? (ref (value-uninitialized)))

(define body/source/forall?
  (lambda (source/pred source/list)
    (if (value-truth? (primitive/null?/1 source/list))
      (value-boolean #t)
      (if (value-truth? (invoke-1 source/pred (primitive/car/1 source/list)))
        (body/source/forall? source/pred (primitive/cdr/1 source/list))
        (value-boolean #f)))))

(ref-set! source/forall? (value-procedure (ref (unit)) (function-2 body/source/forall?)))

(define source/list-of-1? (ref (value-uninitialized)))

(define body/source/list-of-1?
  (lambda (source/l.1)
    (if (value-truth? (primitive/pair?/1 source/l.1))
      (primitive/null?/1 (primitive/cdr/1 source/l.1))
      (value-boolean #f))))

(ref-set! source/list-of-1? (value-procedure (ref (unit)) (function-1 body/source/list-of-1?)))

(define source/list-of-2? (ref (value-uninitialized)))

(define body/source/list-of-2?
  (lambda (source/l.2)
    (if (value-truth? (primitive/pair?/1 source/l.2))
      (if (value-truth? (primitive/pair?/1 (primitive/cdr/1 source/l.2)))
        (primitive/null?/1 (primitive/cddr/1 source/l.2))
        (value-boolean #f))
      (value-boolean #f))))

(ref-set! source/list-of-2? (value-procedure (ref (unit)) (function-1 body/source/list-of-2?)))

(define source/list-of-3? (ref (value-uninitialized)))

(define body/source/list-of-3?
  (lambda (source/l.3)
    (if (value-truth? (primitive/pair?/1 source/l.3))
      (if (value-truth? (primitive/pair?/1 (primitive/cdr/1 source/l.3)))
        (if (value-truth? (primitive/pair?/1 (primitive/cddr/1 source/l.3)))
          (primitive/null?/1 (primitive/cdddr/1 source/l.3))
          (value-boolean #f))
        (value-boolean #f))
      (value-boolean #f))))

(ref-set! source/list-of-3? (value-procedure (ref (unit)) (function-1 body/source/list-of-3?)))

(define source/list-of-list-of-2s? (ref (value-uninitialized)))

(define body/source/list-of-list-of-2s?
  (lambda (source/e.9)
    (if (value-truth? (primitive/null?/1 source/e.9))
      (value-boolean #t)
      (if (value-truth? (primitive/pair?/1 source/e.9))
        (if (value-truth? (body/source/list-of-2? (primitive/car/1 source/e.9)))
          (body/source/list-of-list-of-2s? (primitive/cdr/1 source/e.9))
          (value-boolean #f))
        (value-boolean #f)))))

(ref-set!
  source/list-of-list-of-2s?
  (value-procedure (ref (unit)) (function-1 body/source/list-of-list-of-2s?)))

(define source/dynamic-parse-from-port (ref (value-uninitialized)))

(define body/source/dynamic-parse-from-port
  (lambda (source/port)
    ((lambda (source/next-input) (if (value-truth? (primitive/eof-object?/1 source/next-input)) (value-null) (body/source/dynamic-parse-action-commands (body/source/dynamic-parse-command (binding-value source/dynamic-empty-env) source/next-input) (body/source/dynamic-parse-from-port source/port))))
      (primitive/read/1 source/port))))

(ref-set!
  source/dynamic-parse-from-port
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-from-port)))

(define source/dynamic-parse-file (ref (value-uninitialized)))

(define body/source/dynamic-parse-file
  (lambda (source/file-name)
    ((lambda (source/input-port) (body/source/dynamic-parse-from-port source/input-port))
      (primitive/open-input-file/1 source/file-name))))

(ref-set!
  source/dynamic-parse-file
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-file)))

(define source/gen-element (ref (value-uninitialized)))

(define body/source/gen-element
  (lambda (source/info.1)
    (primitive/cons/2 (value-null) (primitive/cons/2 (value-number (exact-number 0)) source/info.1))))

(ref-set! source/gen-element (value-procedure (ref (unit)) (function-1 body/source/gen-element)))

(define source/info (ref (value-uninitialized)))

(define body/source/info (lambda (source/l.4) (primitive/cddr/1 source/l.4)))

(ref-set! source/info (value-procedure (ref (unit)) (function-1 body/source/info)))

(define source/set-info! (ref (value-uninitialized)))

(define body/source/set-info!
  (lambda (source/elem source/info.2)
    (primitive/set-cdr!/2 (primitive/cdr/1 source/elem) source/info.2)))

(ref-set! source/set-info! (value-procedure (ref (unit)) (function-2 body/source/set-info!)))

(define source/find! (ref (value-uninitialized)))

(define body/source/find!
  (lambda (source/elem.1)
    ((lambda (source/p-elem) (if (value-truth? (primitive/null?/1 source/p-elem)) source/elem.1 ((lambda (source/rep-elem) (begin (primitive/set-car!/2 source/elem.1 source/rep-elem) source/rep-elem)) (body/source/find! source/p-elem))))
      (primitive/car/1 source/elem.1))))

(ref-set! source/find! (value-procedure (ref (unit)) (function-1 body/source/find!)))

(define source/link! (ref (value-uninitialized)))

(define body/source/link!
  (lambda (source/elem-1 source/elem-2)
    ((lambda (source/rank-1 source/rank-2) (if (value-truth? (primitive/=/2 source/rank-1 source/rank-2)) (begin (primitive/set-car!/2 (primitive/cdr/1 source/elem-2) (primitive/+/2 source/rank-2 (value-number (exact-number 1)))) (primitive/set-car!/2 source/elem-1 source/elem-2) source/elem-2) (if (value-truth? (primitive/>/2 source/rank-1 source/rank-2)) (begin (primitive/set-car!/2 source/elem-2 source/elem-1) source/elem-1) (begin (primitive/set-car!/2 source/elem-1 source/elem-2) source/elem-2))))
      (primitive/cadr/1 source/elem-1)
      (primitive/cadr/1 source/elem-2))))

(ref-set! source/link! (value-procedure (ref (unit)) (function-2 body/source/link!)))

(define source/asymm-link! (ref (value-uninitialized)))

(define body/source/asymm-link!
  (lambda (source/l.5 source/x.1) (primitive/set-car!/2 source/l.5 source/x.1)))

(ref-set! source/asymm-link! (value-procedure (ref (unit)) (function-2 body/source/asymm-link!)))

(define source/counter (ref (value-uninitialized)))

(ref-set! source/counter (value-number (exact-number 0)))

(define source/gen-id (ref (value-uninitialized)))

(define body/source/gen-id
  (lambda ()
    (begin
      (begin
        (ref-set!
          source/counter
          (primitive/+/2 (binding-value source/counter) (value-number (exact-number 1))))
        (value-unspecified))
      (binding-value source/counter))))

(ref-set! source/gen-id (value-procedure (ref (unit)) (function-0 body/source/gen-id)))

(define source/gen-tvar (ref (value-uninitialized)))

(define body/source/gen-tvar
  (lambda () (body/source/gen-element (primitive/cons/2 (body/source/gen-id) (value-null)))))

(ref-set! source/gen-tvar (value-procedure (ref (unit)) (function-0 body/source/gen-tvar)))

(define source/gen-type (ref (value-uninitialized)))

(define body/source/gen-type
  (lambda (source/tcon source/targs)
    (body/source/gen-element
      (primitive/cons/2 (body/source/gen-id) (primitive/cons/2 source/tcon source/targs)))))

(ref-set! source/gen-type (value-procedure (ref (unit)) (function-2 body/source/gen-type)))

(define source/dynamic (ref (value-uninitialized)))

(ref-set!
  source/dynamic
  (body/source/gen-element (primitive/cons/2 (value-number (exact-number 0)) (value-null))))

(define source/tvar-id (ref (value-uninitialized)))

(define body/source/tvar-id (lambda (source/tvar) (primitive/car/1 (body/source/info source/tvar))))

(ref-set! source/tvar-id (value-procedure (ref (unit)) (function-1 body/source/tvar-id)))

(define source/tvar-def (ref (value-uninitialized)))

(define body/source/tvar-def
  (lambda (source/tvar.1) (primitive/cdr/1 (body/source/info source/tvar.1))))

(ref-set! source/tvar-def (value-procedure (ref (unit)) (function-1 body/source/tvar-def)))

(define source/set-def! (ref (value-uninitialized)))

(define body/source/set-def!
  (lambda (source/tvar.2 source/tcon.1 source/targs.1)
    (begin
      (primitive/set-cdr!/2
        (body/source/info source/tvar.2)
        (primitive/cons/2 source/tcon.1 source/targs.1))
      (value-null))))

(ref-set! source/set-def! (value-procedure (ref (unit)) (function-3 body/source/set-def!)))

(define source/reset-def! (ref (value-uninitialized)))

(define body/source/reset-def!
  (lambda (source/tvar.3) (primitive/set-cdr!/2 (body/source/info source/tvar.3) (value-null))))

(ref-set! source/reset-def! (value-procedure (ref (unit)) (function-1 body/source/reset-def!)))

(define source/type-con (ref (value-uninitialized)))

(define body/source/type-con (lambda (source/l.6) (primitive/car/1 source/l.6)))

(ref-set! source/type-con (value-procedure (ref (unit)) (function-1 body/source/type-con)))

(define source/type-args (ref (value-uninitialized)))

(define body/source/type-args (lambda (source/l.7) (primitive/cdr/1 source/l.7)))

(ref-set! source/type-args (value-procedure (ref (unit)) (function-1 body/source/type-args)))

(define source/tvar->string (ref (value-uninitialized)))

(define body/source/tvar->string
  (lambda (source/tvar.4)
    (if (value-truth? (primitive/eqv?/2 (body/source/tvar-id source/tvar.4) (value-number (exact-number 0))))
      literal.93
      (primitive/string-append/2
        literal.92
        (primitive/number->string/2
          (body/source/tvar-id source/tvar.4)
          (value-number (exact-number 10)))))))

(ref-set! source/tvar->string (value-procedure (ref (unit)) (function-1 body/source/tvar->string)))

(define source/tvar-show (ref (value-uninitialized)))

(define body/source/tvar-show
  (lambda (source/tv)
    ((lambda (source/tv-rep) ((lambda (source/tv-def) ((lambda () (primitive/cons/2 (body/source/tvar->string source/tv-rep) (if (value-truth? (primitive/null?/1 source/tv-def)) (value-null) (primitive/cons/2 literal.94 (body/source/type-show source/tv-def))))))) (body/source/tvar-def source/tv-rep)))
      (body/source/find! source/tv))))

(ref-set! source/tvar-show (value-procedure (ref (unit)) (function-1 body/source/tvar-show)))

(define source/type-show (ref (value-uninitialized)))

(define body/source/type-show
  (lambda (source/type)
    (if (value-truth? (primitive/eqv?/2 (body/source/type-con source/type) (binding-value source/ptype-con)))
      ((lambda (source/new-tvar) (primitive/cons/2 (binding-value source/ptype-con) (primitive/cons/2 (body/source/tvar-show source/new-tvar) (body/source/tvar-show (invoke-1 (body/source/type-args source/type) source/new-tvar)))))
        (body/source/gen-tvar))
      (primitive/cons/2
        (body/source/type-con source/type)
        (primitive/map/2
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/tv.1) (body/source/tvar->string (body/source/find! source/tv.1)))))
          (body/source/type-args source/type))))))

(ref-set! source/type-show (value-procedure (ref (unit)) (function-1 body/source/type-show)))

(define source/boolean-con (ref (value-uninitialized)))

(ref-set! source/boolean-con literal.95)

(define source/char-con (ref (value-uninitialized)))

(ref-set! source/char-con literal.96)

(define source/null-con (ref (value-uninitialized)))

(ref-set! source/null-con literal.97)

(define source/number-con (ref (value-uninitialized)))

(ref-set! source/number-con literal.98)

(define source/pair-con (ref (value-uninitialized)))

(ref-set! source/pair-con literal.99)

(define source/procedure-con (ref (value-uninitialized)))

(ref-set! source/procedure-con literal.100)

(define source/string-con (ref (value-uninitialized)))

(ref-set! source/string-con literal.101)

(define source/symbol-con (ref (value-uninitialized)))

(ref-set! source/symbol-con literal.102)

(define source/vector-con (ref (value-uninitialized)))

(ref-set! source/vector-con literal.103)

(define source/null (ref (value-uninitialized)))

(define body/source/null
  (lambda () (body/source/pair (body/source/gen-tvar) (body/source/gen-tvar))))

(ref-set! source/null (value-procedure (ref (unit)) (function-0 body/source/null)))

(define source/boolean (ref (value-uninitialized)))

(define body/source/boolean
  (lambda () (body/source/gen-type (binding-value source/boolean-con) (value-null))))

(ref-set! source/boolean (value-procedure (ref (unit)) (function-0 body/source/boolean)))

(define source/character (ref (value-uninitialized)))

(define body/source/character
  (lambda () (body/source/gen-type (binding-value source/char-con) (value-null))))

(ref-set! source/character (value-procedure (ref (unit)) (function-0 body/source/character)))

(define source/number (ref (value-uninitialized)))

(define body/source/number
  (lambda () (body/source/gen-type (binding-value source/number-con) (value-null))))

(ref-set! source/number (value-procedure (ref (unit)) (function-0 body/source/number)))

(define source/charseq (ref (value-uninitialized)))

(define body/source/charseq
  (lambda () (body/source/gen-type (binding-value source/string-con) (value-null))))

(ref-set! source/charseq (value-procedure (ref (unit)) (function-0 body/source/charseq)))

(define source/symbol (ref (value-uninitialized)))

(define body/source/symbol
  (lambda () (body/source/gen-type (binding-value source/symbol-con) (value-null))))

(ref-set! source/symbol (value-procedure (ref (unit)) (function-0 body/source/symbol)))

(define source/pair (ref (value-uninitialized)))

(define body/source/pair
  (lambda (source/tvar-1 source/tvar-2)
    (body/source/gen-type
      (binding-value source/pair-con)
      (primitive/list/2 source/tvar-1 source/tvar-2))))

(ref-set! source/pair (value-procedure (ref (unit)) (function-2 body/source/pair)))

(define source/array (ref (value-uninitialized)))

(define body/source/array
  (lambda (source/tvar.5)
    (body/source/gen-type (binding-value source/vector-con) (primitive/list/1 source/tvar.5))))

(ref-set! source/array (value-procedure (ref (unit)) (function-1 body/source/array)))

(define source/procedure (ref (value-uninitialized)))

(define body/source/procedure
  (lambda (source/arg-tvar source/res-tvar)
    (body/source/gen-type
      (binding-value source/procedure-con)
      (primitive/list/2 source/arg-tvar source/res-tvar))))

(ref-set! source/procedure (value-procedure (ref (unit)) (function-2 body/source/procedure)))

(define source/equiv! (ref (value-uninitialized)))

(define body/source/equiv!
  (lambda (source/tv1 source/tv2)
    (begin
      ((lambda (source/tv1-rep) ((lambda (source/tv2-rep) ((lambda (source/tv1-def) ((lambda (source/tv2-def) ((lambda () (if (value-truth? (primitive/eqv?/2 source/tv1-rep source/tv2-rep)) (value-null) (if (value-truth? (primitive/eqv?/2 source/tv2-rep (binding-value source/dynamic))) (body/source/equiv-with-dynamic! source/tv1-rep) (if (value-truth? (primitive/eqv?/2 source/tv1-rep (binding-value source/dynamic))) (body/source/equiv-with-dynamic! source/tv2-rep) (if (value-truth? (primitive/null?/1 source/tv1-def)) (if (value-truth? (primitive/null?/1 source/tv2-def)) (body/source/link! source/tv1-rep source/tv2-rep) (body/source/asymm-link! source/tv1-rep source/tv2-rep)) (if (value-truth? (primitive/null?/1 source/tv2-def)) (body/source/asymm-link! source/tv2-rep source/tv1-rep) (if (value-truth? (primitive/eqv?/2 (body/source/type-con source/tv1-def) (body/source/type-con source/tv2-def))) (begin (body/source/link! source/tv1-rep source/tv2-rep) (primitive/map/3 (binding-value source/equiv!) (body/source/type-args source/tv1-def) (body/source/type-args source/tv2-def))) (begin (body/source/equiv-with-dynamic! source/tv1-rep) (body/source/equiv-with-dynamic! source/tv2-rep))))))))))) (body/source/tvar-def source/tv2-rep))) (body/source/tvar-def source/tv1-rep))) (body/source/find! source/tv2)))
        (body/source/find! source/tv1))
      (value-null))))

(ref-set! source/equiv! (value-procedure (ref (unit)) (function-2 body/source/equiv!)))

(define source/equiv-with-dynamic! (ref (value-uninitialized)))

(define body/source/equiv-with-dynamic!
  (lambda (source/tv.2)
    (begin
      ((lambda (source/tv-rep.1) (if (value-truth? (primitive/not/1 (primitive/eqv?/2 source/tv-rep.1 (binding-value source/dynamic)))) ((lambda (source/tv-def.1) (begin (body/source/asymm-link! source/tv-rep.1 (binding-value source/dynamic)) (if (value-truth? (primitive/not/1 (primitive/null?/1 source/tv-def.1))) (primitive/map/2 (binding-value source/equiv-with-dynamic!) (body/source/type-args source/tv-def.1)) (value-unspecified)))) (body/source/tvar-def source/tv-rep.1)) (value-unspecified)))
        (body/source/find! source/tv.2))
      (value-null))))

(ref-set!
  source/equiv-with-dynamic!
  (value-procedure (ref (unit)) (function-1 body/source/equiv-with-dynamic!)))

(define source/ptype-con (ref (value-uninitialized)))

(ref-set! source/ptype-con literal.104)

(define source/forall (ref (value-uninitialized)))

(define body/source/forall
  (lambda (source/tv-func) (body/source/gen-type (binding-value source/ptype-con) source/tv-func)))

(ref-set! source/forall (value-procedure (ref (unit)) (function-1 body/source/forall)))

(define source/forall2 (ref (value-uninitialized)))

(define body/source/forall2
  (lambda (source/tv-func2)
    (body/source/forall
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/tv1.1)
            (body/source/forall
              (value-procedure
                (ref (unit))
                (function-1
                  (lambda (source/tv2.1) (invoke-2 source/tv-func2 source/tv1.1 source/tv2.1)))))))))))

(ref-set! source/forall2 (value-procedure (ref (unit)) (function-1 body/source/forall2)))

(define source/forall3 (ref (value-uninitialized)))

(define body/source/forall3
  (lambda (source/tv-func3)
    (body/source/forall
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/tv1.2)
            (body/source/forall2
              (value-procedure
                (ref (unit))
                (function-2
                  (lambda (source/tv2.2 source/tv3)
                    (invoke-3 source/tv-func3 source/tv1.2 source/tv2.2 source/tv3)))))))))))

(ref-set! source/forall3 (value-procedure (ref (unit)) (function-1 body/source/forall3)))

(define source/forall4 (ref (value-uninitialized)))

(define body/source/forall4
  (lambda (source/tv-func4)
    (body/source/forall
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/tv1.3)
            (body/source/forall3
              (value-procedure
                (ref (unit))
                (function-3
                  (lambda (source/tv2.3 source/tv3.1 source/tv4)
                    (invoke-4 source/tv-func4 source/tv1.3 source/tv2.3 source/tv3.1 source/tv4)))))))))))

(ref-set! source/forall4 (value-procedure (ref (unit)) (function-1 body/source/forall4)))

(define source/forall5 (ref (value-uninitialized)))

(define body/source/forall5
  (lambda (source/tv-func5)
    (body/source/forall
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/tv1.4)
            (body/source/forall4
              (value-procedure
                (ref (unit))
                (function-4
                  (lambda (source/tv2.4 source/tv3.2 source/tv4.1 source/tv5)
                    (invoke-5
                      source/tv-func5
                      source/tv1.4
                      source/tv2.4
                      source/tv3.2
                      source/tv4.1
                      source/tv5)))))))))))

(ref-set! source/forall5 (value-procedure (ref (unit)) (function-1 body/source/forall5)))

(define source/instantiate-type (ref (value-uninitialized)))

(define body/source/instantiate-type
  (lambda (source/tv.3)
    ((lambda (source/tv-rep.2) ((lambda (source/tv-def.2) ((lambda () (if (value-truth? (primitive/null?/1 source/tv-def.2)) source/tv-rep.2 (if (value-truth? (primitive/eqv?/2 (body/source/type-con source/tv-def.2) (binding-value source/ptype-con))) (body/source/instantiate-type (invoke-1 (body/source/type-args source/tv-def.2) (body/source/gen-tvar))) source/tv-rep.2))))) (body/source/tvar-def source/tv-rep.2)))
      (body/source/find! source/tv.3))))

(ref-set!
  source/instantiate-type
  (value-procedure (ref (unit)) (function-1 body/source/instantiate-type)))

(define source/fix (ref (value-uninitialized)))

(define body/source/fix
  (lambda (source/tv-func.1)
    ((lambda (source/new-tvar.1) ((lambda (source/inst-tvar) ((lambda (source/inst-def) ((lambda () (if (value-truth? (primitive/null?/1 source/inst-def)) (primitive/error/3 literal.105 literal.106 (primitive/list/3 (body/source/tvar-show source/new-tvar.1) literal.107 (body/source/tvar-show source/inst-tvar))) (begin (body/source/set-def! source/new-tvar.1 (body/source/type-con source/inst-def) (body/source/type-args source/inst-def)) source/new-tvar.1))))) (body/source/tvar-def source/inst-tvar))) (invoke-1 source/tv-func.1 source/new-tvar.1)))
      (body/source/gen-tvar))))

(ref-set! source/fix (value-procedure (ref (unit)) (function-1 body/source/fix)))

(define source/gen-constr (ref (value-uninitialized)))

(define body/source/gen-constr (lambda (source/a source/b) (primitive/cons/2 source/a source/b)))

(ref-set! source/gen-constr (value-procedure (ref (unit)) (function-2 body/source/gen-constr)))

(define source/constr-lhs (ref (value-uninitialized)))

(define body/source/constr-lhs (lambda (source/c.1) (primitive/car/1 source/c.1)))

(ref-set! source/constr-lhs (value-procedure (ref (unit)) (function-1 body/source/constr-lhs)))

(define source/constr-rhs (ref (value-uninitialized)))

(define body/source/constr-rhs (lambda (source/c.2) (primitive/cdr/1 source/c.2)))

(ref-set! source/constr-rhs (value-procedure (ref (unit)) (function-1 body/source/constr-rhs)))

(define source/constr-show (ref (value-uninitialized)))

(define body/source/constr-show
  (lambda (source/c.3)
    (primitive/cons/2
      (body/source/tvar-show (primitive/car/1 source/c.3))
      (primitive/cons/2
        literal.108
        (primitive/cons/2 (body/source/tvar-show (primitive/cdr/1 source/c.3)) (value-null))))))

(ref-set! source/constr-show (value-procedure (ref (unit)) (function-1 body/source/constr-show)))

(define source/global-constraints (ref (value-uninitialized)))

(ref-set! source/global-constraints (value-null))

(define source/init-global-constraints! (ref (value-uninitialized)))

(define body/source/init-global-constraints!
  (lambda () (begin (ref-set! source/global-constraints (value-null)) (value-unspecified))))

(ref-set!
  source/init-global-constraints!
  (value-procedure (ref (unit)) (function-0 body/source/init-global-constraints!)))

(define source/add-constr! (ref (value-uninitialized)))

(define body/source/add-constr!
  (lambda (source/lhs source/rhs)
    (begin
      (begin
        (ref-set!
          source/global-constraints
          (primitive/cons/2
            (body/source/gen-constr source/lhs source/rhs)
            (binding-value source/global-constraints)))
        (value-unspecified))
      (value-null))))

(ref-set! source/add-constr! (value-procedure (ref (unit)) (function-2 body/source/add-constr!)))

(define source/glob-constr-show (ref (value-uninitialized)))

(define body/source/glob-constr-show
  (lambda ()
    (primitive/map/2 (binding-value source/constr-show) (binding-value source/global-constraints))))

(ref-set!
  source/glob-constr-show
  (value-procedure (ref (unit)) (function-0 body/source/glob-constr-show)))

(define source/normalize-global-constraints! (ref (value-uninitialized)))

(define body/source/normalize-global-constraints!
  (lambda ()
    (begin
      (body/source/normalize! (binding-value source/global-constraints))
      (body/source/init-global-constraints!))))

(ref-set!
  source/normalize-global-constraints!
  (value-procedure (ref (unit)) (function-0 body/source/normalize-global-constraints!)))

(define source/normalize! (ref (value-uninitialized)))

(define body/source/normalize!
  (lambda (source/constraints)
    (primitive/map/2
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/c.4)
            (body/source/equiv!
              (body/source/constr-lhs source/c.4)
              (body/source/constr-rhs source/c.4)))))
      source/constraints)))

(ref-set! source/normalize! (value-procedure (ref (unit)) (function-1 body/source/normalize!)))

(define source/null-const (ref (value-uninitialized)))

(ref-set! source/null-const (value-number (exact-number 0)))

(define source/boolean-const (ref (value-uninitialized)))

(ref-set! source/boolean-const (value-number (exact-number 1)))

(define source/char-const (ref (value-uninitialized)))

(ref-set! source/char-const (value-number (exact-number 2)))

(define source/number-const (ref (value-uninitialized)))

(ref-set! source/number-const (value-number (exact-number 3)))

(define source/string-const (ref (value-uninitialized)))

(ref-set! source/string-const (value-number (exact-number 4)))

(define source/symbol-const (ref (value-uninitialized)))

(ref-set! source/symbol-const (value-number (exact-number 5)))

(define source/vector-const (ref (value-uninitialized)))

(ref-set! source/vector-const (value-number (exact-number 6)))

(define source/pair-const (ref (value-uninitialized)))

(ref-set! source/pair-const (value-number (exact-number 7)))

(define source/var-def (ref (value-uninitialized)))

(ref-set! source/var-def (value-number (exact-number 8)))

(define source/null-def (ref (value-uninitialized)))

(ref-set! source/null-def (value-number (exact-number 29)))

(define source/pair-def (ref (value-uninitialized)))

(ref-set! source/pair-def (value-number (exact-number 30)))

(define source/variable (ref (value-uninitialized)))

(ref-set! source/variable (value-number (exact-number 9)))

(define source/identifier (ref (value-uninitialized)))

(ref-set! source/identifier (value-number (exact-number 10)))

(define source/procedure-call (ref (value-uninitialized)))

(ref-set! source/procedure-call (value-number (exact-number 11)))

(define source/lambda-expression (ref (value-uninitialized)))

(ref-set! source/lambda-expression (value-number (exact-number 12)))

(define source/conditional (ref (value-uninitialized)))

(ref-set! source/conditional (value-number (exact-number 13)))

(define source/assignment (ref (value-uninitialized)))

(ref-set! source/assignment (value-number (exact-number 14)))

(define source/cond-expression (ref (value-uninitialized)))

(ref-set! source/cond-expression (value-number (exact-number 15)))

(define source/case-expression (ref (value-uninitialized)))

(ref-set! source/case-expression (value-number (exact-number 16)))

(define source/and-expression (ref (value-uninitialized)))

(ref-set! source/and-expression (value-number (exact-number 17)))

(define source/or-expression (ref (value-uninitialized)))

(ref-set! source/or-expression (value-number (exact-number 18)))

(define source/let-expression (ref (value-uninitialized)))

(ref-set! source/let-expression (value-number (exact-number 19)))

(define source/named-let-expression (ref (value-uninitialized)))

(ref-set! source/named-let-expression (value-number (exact-number 20)))

(define source/let*-expression (ref (value-uninitialized)))

(ref-set! source/let*-expression (value-number (exact-number 21)))

(define source/letrec-expression (ref (value-uninitialized)))

(ref-set! source/letrec-expression (value-number (exact-number 22)))

(define source/begin-expression (ref (value-uninitialized)))

(ref-set! source/begin-expression (value-number (exact-number 23)))

(define source/do-expression (ref (value-uninitialized)))

(ref-set! source/do-expression (value-number (exact-number 24)))

(define source/empty (ref (value-uninitialized)))

(ref-set! source/empty (value-number (exact-number 25)))

(define source/null-arg (ref (value-uninitialized)))

(ref-set! source/null-arg (value-number (exact-number 31)))

(define source/pair-arg (ref (value-uninitialized)))

(ref-set! source/pair-arg (value-number (exact-number 32)))

(define source/definition (ref (value-uninitialized)))

(ref-set! source/definition (value-number (exact-number 26)))

(define source/function-definition (ref (value-uninitialized)))

(ref-set! source/function-definition (value-number (exact-number 27)))

(define source/begin-command (ref (value-uninitialized)))

(ref-set! source/begin-command (value-number (exact-number 28)))

(define source/dynamic-parse-action-null-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-null-const
  (lambda () (body/source/ast-gen (binding-value source/null-const) (value-null))))

(ref-set!
  source/dynamic-parse-action-null-const
  (value-procedure (ref (unit)) (function-0 body/source/dynamic-parse-action-null-const)))

(define source/dynamic-parse-action-boolean-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-boolean-const
  (lambda (source/e.10) (body/source/ast-gen (binding-value source/boolean-const) source/e.10)))

(ref-set!
  source/dynamic-parse-action-boolean-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-boolean-const)))

(define source/dynamic-parse-action-char-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-char-const
  (lambda (source/e.11) (body/source/ast-gen (binding-value source/char-const) source/e.11)))

(ref-set!
  source/dynamic-parse-action-char-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-char-const)))

(define source/dynamic-parse-action-number-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-number-const
  (lambda (source/e.12) (body/source/ast-gen (binding-value source/number-const) source/e.12)))

(ref-set!
  source/dynamic-parse-action-number-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-number-const)))

(define source/dynamic-parse-action-string-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-string-const
  (lambda (source/e.13) (body/source/ast-gen (binding-value source/string-const) source/e.13)))

(ref-set!
  source/dynamic-parse-action-string-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-string-const)))

(define source/dynamic-parse-action-symbol-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-symbol-const
  (lambda (source/e.14) (body/source/ast-gen (binding-value source/symbol-const) source/e.14)))

(ref-set!
  source/dynamic-parse-action-symbol-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-symbol-const)))

(define source/dynamic-parse-action-vector-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-vector-const
  (lambda (source/e.15) (body/source/ast-gen (binding-value source/vector-const) source/e.15)))

(ref-set!
  source/dynamic-parse-action-vector-const
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-vector-const)))

(define source/dynamic-parse-action-pair-const (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-pair-const
  (lambda (source/e1 source/e2)
    (body/source/ast-gen (binding-value source/pair-const) (primitive/cons/2 source/e1 source/e2))))

(ref-set!
  source/dynamic-parse-action-pair-const
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-pair-const)))

(define source/dynamic-parse-action-var-def (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-var-def
  (lambda (source/e.16) (body/source/ast-gen (binding-value source/var-def) source/e.16)))

(ref-set!
  source/dynamic-parse-action-var-def
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-var-def)))

(define source/dynamic-parse-action-null-formal (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-null-formal
  (lambda () (body/source/ast-gen (binding-value source/null-def) (value-null))))

(ref-set!
  source/dynamic-parse-action-null-formal
  (value-procedure (ref (unit)) (function-0 body/source/dynamic-parse-action-null-formal)))

(define source/dynamic-parse-action-pair-formal (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-pair-formal
  (lambda (source/d1 source/d2)
    (body/source/ast-gen (binding-value source/pair-def) (primitive/cons/2 source/d1 source/d2))))

(ref-set!
  source/dynamic-parse-action-pair-formal
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-pair-formal)))

(define source/dynamic-parse-action-variable (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-variable
  (lambda (source/e.17) (body/source/ast-gen (binding-value source/variable) source/e.17)))

(ref-set!
  source/dynamic-parse-action-variable
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-variable)))

(define source/dynamic-parse-action-identifier (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-identifier
  (lambda (source/e.18) (body/source/ast-gen (binding-value source/identifier) source/e.18)))

(ref-set!
  source/dynamic-parse-action-identifier
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-identifier)))

(define source/dynamic-parse-action-null-arg (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-null-arg
  (lambda () (body/source/ast-gen (binding-value source/null-arg) (value-null))))

(ref-set!
  source/dynamic-parse-action-null-arg
  (value-procedure (ref (unit)) (function-0 body/source/dynamic-parse-action-null-arg)))

(define source/dynamic-parse-action-pair-arg (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-pair-arg
  (lambda (source/a1 source/a2)
    (body/source/ast-gen (binding-value source/pair-arg) (primitive/cons/2 source/a1 source/a2))))

(ref-set!
  source/dynamic-parse-action-pair-arg
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-pair-arg)))

(define source/dynamic-parse-action-procedure-call (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-procedure-call
  (lambda (source/op.3 source/args.20)
    (body/source/ast-gen
      (binding-value source/procedure-call)
      (primitive/cons/2 source/op.3 source/args.20))))

(ref-set!
  source/dynamic-parse-action-procedure-call
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-procedure-call)))

(define source/dynamic-parse-action-lambda-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-lambda-expression
  (lambda (source/formals.5 source/body.7)
    (body/source/ast-gen
      (binding-value source/lambda-expression)
      (primitive/cons/2 source/formals.5 source/body.7))))

(ref-set!
  source/dynamic-parse-action-lambda-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-lambda-expression)))

(define source/dynamic-parse-action-conditional (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-conditional
  (lambda (source/test source/then-branch source/else-branch)
    (body/source/ast-gen
      (binding-value source/conditional)
      (primitive/cons/2 source/test (primitive/cons/2 source/then-branch source/else-branch)))))

(ref-set!
  source/dynamic-parse-action-conditional
  (value-procedure (ref (unit)) (function-3 body/source/dynamic-parse-action-conditional)))

(define source/dynamic-parse-action-empty (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-empty
  (lambda () (body/source/ast-gen (binding-value source/empty) (value-null))))

(ref-set!
  source/dynamic-parse-action-empty
  (value-procedure (ref (unit)) (function-0 body/source/dynamic-parse-action-empty)))

(define source/dynamic-parse-action-assignment (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-assignment
  (lambda (source/lhs.1 source/rhs.1)
    (body/source/ast-gen
      (binding-value source/assignment)
      (primitive/cons/2 source/lhs.1 source/rhs.1))))

(ref-set!
  source/dynamic-parse-action-assignment
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-assignment)))

(define source/dynamic-parse-action-begin-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-begin-expression
  (lambda (source/body.8)
    (body/source/ast-gen (binding-value source/begin-expression) source/body.8)))

(ref-set!
  source/dynamic-parse-action-begin-expression
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-begin-expression)))

(define source/dynamic-parse-action-cond-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-cond-expression
  (lambda (source/clauses)
    (body/source/ast-gen (binding-value source/cond-expression) source/clauses)))

(ref-set!
  source/dynamic-parse-action-cond-expression
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-cond-expression)))

(define source/dynamic-parse-action-and-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-and-expression
  (lambda (source/args.21)
    (body/source/ast-gen (binding-value source/and-expression) source/args.21)))

(ref-set!
  source/dynamic-parse-action-and-expression
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-and-expression)))

(define source/dynamic-parse-action-or-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-or-expression
  (lambda (source/args.22)
    (body/source/ast-gen (binding-value source/or-expression) source/args.22)))

(ref-set!
  source/dynamic-parse-action-or-expression
  (value-procedure (ref (unit)) (function-1 body/source/dynamic-parse-action-or-expression)))

(define source/dynamic-parse-action-case-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-case-expression
  (lambda (source/key.1 source/clauses.1)
    (body/source/ast-gen
      (binding-value source/case-expression)
      (primitive/cons/2 source/key.1 source/clauses.1))))

(ref-set!
  source/dynamic-parse-action-case-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-case-expression)))

(define source/dynamic-parse-action-let-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-let-expression
  (lambda (source/bindings.7 source/body.9)
    (body/source/ast-gen
      (binding-value source/let-expression)
      (primitive/cons/2 source/bindings.7 source/body.9))))

(ref-set!
  source/dynamic-parse-action-let-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-let-expression)))

(define source/dynamic-parse-action-named-let-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-named-let-expression
  (lambda (source/variable.2 source/bindings.8 source/body.10)
    (body/source/ast-gen
      (binding-value source/named-let-expression)
      (primitive/cons/2 source/variable.2 (primitive/cons/2 source/bindings.8 source/body.10)))))

(ref-set!
  source/dynamic-parse-action-named-let-expression
  (value-procedure (ref (unit)) (function-3 body/source/dynamic-parse-action-named-let-expression)))

(define source/dynamic-parse-action-let*-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-let*-expression
  (lambda (source/bindings.9 source/body.11)
    (body/source/ast-gen
      (binding-value source/let*-expression)
      (primitive/cons/2 source/bindings.9 source/body.11))))

(ref-set!
  source/dynamic-parse-action-let*-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-let*-expression)))

(define source/dynamic-parse-action-letrec-expression (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-letrec-expression
  (lambda (source/bindings.10 source/body.12)
    (body/source/ast-gen
      (binding-value source/letrec-expression)
      (primitive/cons/2 source/bindings.10 source/body.12))))

(ref-set!
  source/dynamic-parse-action-letrec-expression
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-letrec-expression)))

(define source/dynamic-parse-action-definition (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-definition
  (lambda (source/variable.3 source/expr)
    (body/source/ast-gen
      (binding-value source/definition)
      (primitive/cons/2 source/variable.3 source/expr))))

(ref-set!
  source/dynamic-parse-action-definition
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-definition)))

(define source/dynamic-parse-action-function-definition (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-function-definition
  (lambda (source/variable.4 source/formals.6 source/body.13)
    (body/source/ast-gen
      (binding-value source/function-definition)
      (primitive/cons/2 source/variable.4 (primitive/cons/2 source/formals.6 source/body.13)))))

(ref-set!
  source/dynamic-parse-action-function-definition
  (value-procedure (ref (unit)) (function-3 body/source/dynamic-parse-action-function-definition)))

(define source/dynamic-parse-action-commands (ref (value-uninitialized)))

(define body/source/dynamic-parse-action-commands
  (lambda (source/a.1 source/b.1) (primitive/cons/2 source/a.1 source/b.1)))

(ref-set!
  source/dynamic-parse-action-commands
  (value-procedure (ref (unit)) (function-2 body/source/dynamic-parse-action-commands)))

(define source/ast-show (ref (value-uninitialized)))

(define body/source/ast-show
  (lambda (source/ast)
    ((lambda (source/syntax-op source/syntax-arg) ((lambda (source/value.22) (if (value-truth? (primitive/memv/2 source/value.22 literal.158)) source/syntax-arg ((lambda (source/value.23) (if (value-truth? (primitive/memv/2 source/value.23 literal.157)) (value-null) ((lambda (source/value.24) (if (value-truth? (primitive/memv/2 source/value.24 literal.156)) (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cdr/1 source/syntax-arg))) ((lambda (source/value.25) (if (value-truth? (primitive/memv/2 source/value.25 literal.155)) (primitive/list/2 literal.154 source/syntax-arg) ((lambda (source/value.26) (if (value-truth? (primitive/memv/2 source/value.26 literal.153)) (primitive/list->vector/1 (primitive/map/2 (binding-value source/ast-show) source/syntax-arg)) ((lambda (source/value.27) (if (value-truth? (primitive/memv/2 source/value.27 literal.152)) (primitive/list/3 literal.151 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cdr/1 source/syntax-arg))) ((lambda (source/value.28) (if (value-truth? (primitive/memv/2 source/value.28 literal.150)) (invoke-1 (binding-value source/ast-arg) source/syntax-arg) ((lambda (source/value.29) (if (value-truth? (primitive/memv/2 source/value.29 literal.149)) (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cdr/1 source/syntax-arg))) ((lambda (source/value.30) (if (value-truth? (primitive/memv/2 source/value.30 literal.148)) (primitive/cons/2 literal.147 (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/syntax-arg)))) ((lambda (source/value.31) (if (value-truth? (primitive/memv/2 source/value.31 literal.146)) (primitive/cons/2 literal.145 (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (primitive/cons/2 (body/source/ast-show (primitive/cadr/1 source/syntax-arg)) ((lambda (source/alt) (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/alt) (binding-value source/empty))) (value-null) (primitive/list/1 (body/source/ast-show source/alt)))) (primitive/cddr/1 source/syntax-arg))))) ((lambda (source/value.32) (if (value-truth? (primitive/memv/2 source/value.32 literal.144)) (primitive/list/3 literal.143 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cdr/1 source/syntax-arg))) ((lambda (source/value.33) (if (value-truth? (primitive/memv/2 source/value.33 literal.142)) (primitive/cons/2 literal.140 (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc.1) ((lambda (source/guard source/body.14) (primitive/cons/2 (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/guard) (binding-value source/empty))) literal.141 (body/source/ast-show source/guard)) (primitive/map/2 (binding-value source/ast-show) source/body.14))) (primitive/car/1 source/cc.1) (primitive/cdr/1 source/cc.1))))) source/syntax-arg)) ((lambda (source/value.34) (if (value-truth? (primitive/memv/2 source/value.34 literal.139)) (primitive/cons/2 literal.137 (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc) ((lambda (source/data) (if (value-truth? (if (value-truth? (primitive/pair?/1 source/data)) (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) (primitive/car/1 source/data)) (binding-value source/empty)) (value-boolean #f))) (primitive/cons/2 literal.138 (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/cc))) (primitive/cons/2 (primitive/map/2 (binding-value source/datum-show) source/data) (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/cc))))) (primitive/car/1 source/cc))))) (primitive/cdr/1 source/syntax-arg)))) ((lambda (source/value.35) (if (value-truth? (primitive/memv/2 source/value.35 literal.136)) (primitive/cons/2 literal.135 (primitive/map/2 (binding-value source/ast-show) source/syntax-arg)) ((lambda (source/value.36) (if (value-truth? (primitive/memv/2 source/value.36 literal.134)) (primitive/cons/2 literal.133 (primitive/map/2 (binding-value source/ast-show) source/syntax-arg)) ((lambda (source/value.37) (if (value-truth? (primitive/memv/2 source/value.37 literal.132)) (primitive/cons/2 literal.131 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.3 source/e.22) (primitive/list/2 (body/source/ast-show source/vd.3) (body/source/ast-show source/e.22))))) (primitive/caar/1 source/syntax-arg) (primitive/cdar/1 source/syntax-arg)) (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/syntax-arg)))) ((lambda (source/value.38) (if (value-truth? (primitive/memv/2 source/value.38 literal.130)) (primitive/cons/2 literal.129 (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.2 source/e.21) (primitive/list/2 (body/source/ast-show source/vd.2) (body/source/ast-show source/e.21))))) (primitive/caadr/1 source/syntax-arg) (primitive/cdadr/1 source/syntax-arg)) (primitive/map/2 (binding-value source/ast-show) (primitive/cddr/1 source/syntax-arg))))) ((lambda (source/value.39) (if (value-truth? (primitive/memv/2 source/value.39 literal.128)) (primitive/cons/2 literal.127 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.1 source/e.20) (primitive/list/2 (body/source/ast-show source/vd.1) (body/source/ast-show source/e.20))))) (primitive/caar/1 source/syntax-arg) (primitive/cdar/1 source/syntax-arg)) (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/syntax-arg)))) ((lambda (source/value.40) (if (value-truth? (primitive/memv/2 source/value.40 literal.126)) (primitive/cons/2 literal.125 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd source/e.19) (primitive/list/2 (body/source/ast-show source/vd) (body/source/ast-show source/e.19))))) (primitive/caar/1 source/syntax-arg) (primitive/cdar/1 source/syntax-arg)) (primitive/map/2 (binding-value source/ast-show) (primitive/cdr/1 source/syntax-arg)))) ((lambda (source/value.41) (if (value-truth? (primitive/memv/2 source/value.41 literal.124)) (primitive/cons/2 literal.123 (primitive/map/2 (binding-value source/ast-show) source/syntax-arg)) ((lambda (source/value.42) (if (value-truth? (primitive/memv/2 source/value.42 literal.122)) (primitive/error/3 literal.120 literal.121 source/syntax-arg) ((lambda (source/value.43) (if (value-truth? (primitive/memv/2 source/value.43 literal.119)) (primitive/error/2 literal.117 literal.118) ((lambda (source/value.44) (if (value-truth? (primitive/memv/2 source/value.44 literal.116)) (primitive/list/3 literal.115 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cdr/1 source/syntax-arg))) ((lambda (source/value.45) (if (value-truth? (primitive/memv/2 source/value.45 literal.114)) (primitive/cons/2 literal.113 (primitive/cons/2 (primitive/cons/2 (body/source/ast-show (primitive/car/1 source/syntax-arg)) (body/source/ast-show (primitive/cadr/1 source/syntax-arg))) (primitive/map/2 (binding-value source/ast-show) (primitive/cddr/1 source/syntax-arg)))) ((lambda (source/value.46) (if (value-truth? (primitive/memv/2 source/value.46 literal.112)) (primitive/cons/2 literal.111 (primitive/map/2 (binding-value source/ast-show) source/syntax-arg)) ((lambda (source/value.47) (primitive/error/3 literal.109 literal.110 source/syntax-op)) source/value.46))) source/value.45))) source/value.44))) source/value.43))) source/value.42))) source/value.41))) source/value.40))) source/value.39))) source/value.38))) source/value.37))) source/value.36))) source/value.35))) source/value.34))) source/value.33))) source/value.32))) source/value.31))) source/value.30))) source/value.29))) source/value.28))) source/value.27))) source/value.26))) source/value.25))) source/value.24))) source/value.23))) source/value.22))) source/syntax-op))
      (invoke-1 (binding-value source/ast-con) source/ast)
      (invoke-1 (binding-value source/ast-arg) source/ast))))

(ref-set! source/ast-show (value-procedure (ref (unit)) (function-1 body/source/ast-show)))

(define source/ast*-show (ref (value-uninitialized)))

(define body/source/ast*-show
  (lambda (source/p) (primitive/map/2 (binding-value source/ast-show) source/p)))

(ref-set! source/ast*-show (value-procedure (ref (unit)) (function-1 body/source/ast*-show)))

(define source/datum-show (ref (value-uninitialized)))

(define body/source/datum-show
  (lambda (source/ast.1)
    ((lambda (source/value.48) (if (value-truth? (primitive/memv/2 source/value.48 literal.163)) (invoke-1 (binding-value source/ast-arg) source/ast.1) ((lambda (source/value.49) (if (value-truth? (primitive/memv/2 source/value.49 literal.162)) (primitive/list->vector/1 (primitive/map/2 (binding-value source/datum-show) (invoke-1 (binding-value source/ast-arg) source/ast.1))) ((lambda (source/value.50) (if (value-truth? (primitive/memv/2 source/value.50 literal.161)) (primitive/cons/2 (body/source/datum-show (primitive/car/1 (invoke-1 (binding-value source/ast-arg) source/ast.1))) (body/source/datum-show (primitive/cdr/1 (invoke-1 (binding-value source/ast-arg) source/ast.1)))) ((lambda (source/value.51) (primitive/error/2 literal.159 literal.160)) source/value.50))) source/value.49))) source/value.48)))
      (invoke-1 (binding-value source/ast-con) source/ast.1))))

(ref-set! source/datum-show (value-procedure (ref (unit)) (function-1 body/source/datum-show)))

(define source/write-to-port (ref (value-uninitialized)))

(define body/source/write-to-port
  (lambda (source/prog source/port.1)
    (begin
      (primitive/for-each/2
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/command.1)
              (begin
                (primitive/write/2 source/command.1 source/port.1)
                (primitive/newline/1 source/port.1)))))
        source/prog)
      (value-null))))

(ref-set!
  source/write-to-port
  (value-procedure (ref (unit)) (function-2 body/source/write-to-port)))

(define source/write-to-file (ref (value-uninitialized)))

(define body/source/write-to-file
  (lambda (source/prog.1 source/filename)
    ((lambda (source/port.2) (begin (body/source/write-to-port source/prog.1 source/port.2) (primitive/close-output-port/1 source/port.2) (value-null)))
      (primitive/open-output-file/1 source/filename))))

(ref-set!
  source/write-to-file
  (value-procedure (ref (unit)) (function-2 body/source/write-to-file)))

(define source/ast-gen (ref (value-uninitialized)))

(define body/source/ast-gen
  (lambda (source/syntax-op.1 source/arg)
    ((lambda (source/ntvar) (primitive/cons/2 source/syntax-op.1 (primitive/cons/2 source/ntvar source/arg)))
      ((lambda (source/value.52) (if (value-truth? (primitive/memv/2 source/value.52 literal.193)) (body/source/null) ((lambda (source/value.53) (if (value-truth? (primitive/memv/2 source/value.53 literal.192)) (body/source/boolean) ((lambda (source/value.54) (if (value-truth? (primitive/memv/2 source/value.54 literal.191)) (body/source/character) ((lambda (source/value.55) (if (value-truth? (primitive/memv/2 source/value.55 literal.190)) (body/source/number) ((lambda (source/value.56) (if (value-truth? (primitive/memv/2 source/value.56 literal.189)) (body/source/charseq) ((lambda (source/value.57) (if (value-truth? (primitive/memv/2 source/value.57 literal.188)) (body/source/symbol) ((lambda (source/value.58) (if (value-truth? (primitive/memv/2 source/value.58 literal.187)) ((lambda (source/aux-tvar) (begin (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/t) (body/source/add-constr! source/t source/aux-tvar)))) (primitive/map/2 (binding-value source/ast-tvar) source/arg)) (body/source/array source/aux-tvar))) (body/source/gen-tvar)) ((lambda (source/value.59) (if (value-truth? (primitive/memv/2 source/value.59 literal.186)) ((lambda (source/t1 source/t2) (body/source/pair source/t1 source/t2)) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cdr/1 source/arg))) ((lambda (source/value.60) (if (value-truth? (primitive/memv/2 source/value.60 literal.185)) (body/source/gen-tvar) ((lambda (source/value.61) (if (value-truth? (primitive/memv/2 source/value.61 literal.184)) (invoke-1 (binding-value source/ast-tvar) source/arg) ((lambda (source/value.62) (if (value-truth? (primitive/memv/2 source/value.62 literal.183)) ((lambda (source/in-env) (if (value-truth? source/in-env) (body/source/instantiate-type (invoke-1 (binding-value source/binding-value) source/in-env)) ((lambda (source/new-tvar.5) (begin (begin (ref-set! source/dynamic-top-level-env (body/source/extend-env-with-binding (binding-value source/dynamic-top-level-env) (invoke-2 (binding-value source/gen-binding) source/arg source/new-tvar.5))) (value-unspecified)) source/new-tvar.5)) (body/source/gen-tvar)))) (body/source/dynamic-lookup source/arg (binding-value source/dynamic-top-level-env))) ((lambda (source/value.63) (if (value-truth? (primitive/memv/2 source/value.63 literal.182)) ((lambda (source/new-tvar.4) (begin (body/source/add-constr! (body/source/procedure (invoke-1 (binding-value source/ast-tvar) (primitive/cdr/1 source/arg)) source/new-tvar.4) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg))) source/new-tvar.4)) (body/source/gen-tvar)) ((lambda (source/value.64) (if (value-truth? (primitive/memv/2 source/value.64 literal.181)) (body/source/procedure (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (body/source/tail (primitive/cdr/1 source/arg)))) ((lambda (source/value.65) (if (value-truth? (primitive/memv/2 source/value.65 literal.180)) ((lambda (source/t-test source/t-consequent source/t-alternate) (begin (body/source/add-constr! (body/source/boolean) source/t-test) (body/source/add-constr! source/t-consequent source/t-alternate) source/t-consequent)) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cadr/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cddr/1 source/arg))) ((lambda (source/value.66) (if (value-truth? (primitive/memv/2 source/value.66 literal.179)) ((lambda (source/var-tvar source/exp-tvar) (begin (body/source/add-constr! source/var-tvar source/exp-tvar) source/var-tvar)) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cdr/1 source/arg))) ((lambda (source/value.67) (if (value-truth? (primitive/memv/2 source/value.67 literal.178)) ((lambda (source/new-tvar.3) (begin (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/body.16) (body/source/add-constr! (invoke-1 (binding-value source/ast-tvar) (body/source/tail source/body.16)) source/new-tvar.3)))) (primitive/map/2 primitive-value/cdr source/arg)) (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/e.25) (body/source/add-constr! (body/source/boolean) (invoke-1 (binding-value source/ast-tvar) source/e.25))))) (primitive/map/2 primitive-value/car source/arg)) source/new-tvar.3)) (body/source/gen-tvar)) ((lambda (source/value.68) (if (value-truth? (primitive/memv/2 source/value.68 literal.177)) ((lambda (source/new-tvar.2) ((lambda (source/t-key) ((lambda (source/case-clauses) ((lambda () (begin (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/exprs.2) (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/e.24) (body/source/add-constr! (invoke-1 (binding-value source/ast-tvar) source/e.24) source/t-key)))) source/exprs.2)))) (primitive/map/2 primitive-value/car source/case-clauses)) (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/body.15) (body/source/add-constr! (invoke-1 (binding-value source/ast-tvar) (body/source/tail source/body.15)) source/new-tvar.2)))) (primitive/map/2 primitive-value/cdr source/case-clauses)) source/new-tvar.2)))) (primitive/cdr/1 source/arg))) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)))) (body/source/gen-tvar)) ((lambda (source/value.69) (if (value-truth? (primitive/memv/2 source/value.69 literal.176)) (begin (primitive/for-each/2 (value-procedure (ref (unit)) (function-1 (lambda (source/e.23) (body/source/add-constr! (body/source/boolean) (invoke-1 (binding-value source/ast-tvar) source/e.23))))) source/arg) (body/source/boolean)) ((lambda (source/value.70) (if (value-truth? (primitive/memv/2 source/value.70 literal.175)) ((lambda (source/var-def-tvars.1 source/def-expr-types.1 source/body-type.1) (begin (primitive/for-each/3 (binding-value source/add-constr!) source/var-def-tvars.1 source/def-expr-types.1) source/body-type.1)) (primitive/map/2 (binding-value source/ast-tvar) (primitive/caar/1 source/arg)) (primitive/map/2 (binding-value source/ast-tvar) (primitive/cdar/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (body/source/tail (primitive/cdr/1 source/arg)))) ((lambda (source/value.71) (if (value-truth? (primitive/memv/2 source/value.71 literal.174)) ((lambda (source/var-def-tvars source/def-expr-types source/body-type source/named-var-type) (begin (primitive/for-each/3 (binding-value source/add-constr!) source/var-def-tvars source/def-expr-types) (body/source/add-constr! (body/source/procedure (body/source/convert-tvars source/var-def-tvars) source/body-type) source/named-var-type) source/body-type)) (primitive/map/2 (binding-value source/ast-tvar) (primitive/caadr/1 source/arg)) (primitive/map/2 (binding-value source/ast-tvar) (primitive/cdadr/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (body/source/tail (primitive/cddr/1 source/arg))) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg))) ((lambda (source/value.72) (if (value-truth? (primitive/memv/2 source/value.72 literal.173)) (invoke-1 (binding-value source/ast-tvar) (body/source/tail source/arg)) ((lambda (source/value.73) (if (value-truth? (primitive/memv/2 source/value.73 literal.172)) (primitive/error/2 literal.170 literal.171) ((lambda (source/value.74) (if (value-truth? (primitive/memv/2 source/value.74 literal.169)) (body/source/gen-tvar) ((lambda (source/value.75) (if (value-truth? (primitive/memv/2 source/value.75 literal.168)) ((lambda (source/t-var.1 source/t-exp) (begin (body/source/add-constr! source/t-var.1 source/t-exp) source/t-var.1)) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cdr/1 source/arg))) ((lambda (source/value.76) (if (value-truth? (primitive/memv/2 source/value.76 literal.167)) ((lambda (source/t-var source/t-formals source/t-body) (begin (body/source/add-constr! (body/source/procedure source/t-formals source/t-body) source/t-var) source/t-var)) (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (primitive/cadr/1 source/arg)) (invoke-1 (binding-value source/ast-tvar) (body/source/tail (primitive/cddr/1 source/arg)))) ((lambda (source/value.77) (if (value-truth? (primitive/memv/2 source/value.77 literal.166)) (body/source/gen-tvar) ((lambda (source/value.78) (primitive/error/3 literal.164 literal.165 source/syntax-op.1)) source/value.77))) source/value.76))) source/value.75))) source/value.74))) source/value.73))) source/value.72))) source/value.71))) source/value.70))) source/value.69))) source/value.68))) source/value.67))) source/value.66))) source/value.65))) source/value.64))) source/value.63))) source/value.62))) source/value.61))) source/value.60))) source/value.59))) source/value.58))) source/value.57))) source/value.56))) source/value.55))) source/value.54))) source/value.53))) source/value.52)))
        source/syntax-op.1))))

(ref-set! source/ast-gen (value-procedure (ref (unit)) (function-2 body/source/ast-gen)))

(define source/ast-con (ref (value-uninitialized)))

(ref-set! source/ast-con primitive-value/car)

(define source/ast-arg (ref (value-uninitialized)))

(ref-set! source/ast-arg primitive-value/cddr)

(define source/ast-tvar (ref (value-uninitialized)))

(ref-set! source/ast-tvar primitive-value/cadr)

(define source/tail (ref (value-uninitialized)))

(define body/source/tail
  (lambda (source/l.8)
    (if (value-truth? (primitive/null?/1 (primitive/cdr/1 source/l.8)))
      (primitive/car/1 source/l.8)
      (body/source/tail (primitive/cdr/1 source/l.8)))))

(ref-set! source/tail (value-procedure (ref (unit)) (function-1 body/source/tail)))

(define source/convert-tvars (ref (value-uninitialized)))

(define body/source/convert-tvars
  (lambda (source/tvar-list)
    (if (value-truth? (primitive/null?/1 source/tvar-list))
      (body/source/null)
      (if (value-truth? (primitive/pair?/1 source/tvar-list))
        (body/source/pair
          (primitive/car/1 source/tvar-list)
          (body/source/convert-tvars (primitive/cdr/1 source/tvar-list)))
        (primitive/error/3 literal.194 literal.195 source/tvar-list)))))

(ref-set!
  source/convert-tvars
  (value-procedure (ref (unit)) (function-1 body/source/convert-tvars)))

(define source/tast-show (ref (value-uninitialized)))

(define body/source/tast-show
  (lambda (source/ast.2)
    ((lambda (source/syntax-op.2 source/syntax-tvar source/syntax-arg.1) (primitive/cons/2 ((lambda (source/value.79) (if (value-truth? (primitive/memv/2 source/value.79 literal.245)) source/syntax-arg.1 ((lambda (source/value.80) (if (value-truth? (primitive/memv/2 source/value.80 literal.244)) (value-null) ((lambda (source/value.81) (if (value-truth? (primitive/memv/2 source/value.81 literal.243)) (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cdr/1 source/syntax-arg.1))) ((lambda (source/value.82) (if (value-truth? (primitive/memv/2 source/value.82 literal.242)) (primitive/list/2 literal.241 source/syntax-arg.1) ((lambda (source/value.83) (if (value-truth? (primitive/memv/2 source/value.83 literal.240)) (primitive/list->vector/1 (primitive/map/2 (binding-value source/tast-show) source/syntax-arg.1)) ((lambda (source/value.84) (if (value-truth? (primitive/memv/2 source/value.84 literal.239)) (primitive/list/3 literal.238 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cdr/1 source/syntax-arg.1))) ((lambda (source/value.85) (if (value-truth? (primitive/memv/2 source/value.85 literal.237)) (invoke-1 (binding-value source/ast-arg) source/syntax-arg.1) ((lambda (source/value.86) (if (value-truth? (primitive/memv/2 source/value.86 literal.236)) (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cdr/1 source/syntax-arg.1))) ((lambda (source/value.87) (if (value-truth? (primitive/memv/2 source/value.87 literal.235)) (primitive/cons/2 literal.234 (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/syntax-arg.1)))) ((lambda (source/value.88) (if (value-truth? (primitive/memv/2 source/value.88 literal.233)) (primitive/cons/2 literal.232 (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (primitive/cons/2 (body/source/tast-show (primitive/cadr/1 source/syntax-arg.1)) ((lambda (source/alt.1) (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/alt.1) (binding-value source/empty))) (value-null) (primitive/list/1 (body/source/tast-show source/alt.1)))) (primitive/cddr/1 source/syntax-arg.1))))) ((lambda (source/value.89) (if (value-truth? (primitive/memv/2 source/value.89 literal.231)) (primitive/list/3 literal.230 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cdr/1 source/syntax-arg.1))) ((lambda (source/value.90) (if (value-truth? (primitive/memv/2 source/value.90 literal.229)) (primitive/cons/2 literal.227 (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc.3) ((lambda (source/guard.1 source/body.17) (primitive/cons/2 (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/guard.1) (binding-value source/empty))) literal.228 (body/source/tast-show source/guard.1)) (primitive/map/2 (binding-value source/tast-show) source/body.17))) (primitive/car/1 source/cc.3) (primitive/cdr/1 source/cc.3))))) source/syntax-arg.1)) ((lambda (source/value.91) (if (value-truth? (primitive/memv/2 source/value.91 literal.226)) (primitive/cons/2 literal.224 (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc.2) ((lambda (source/data.1) (if (value-truth? (if (value-truth? (primitive/pair?/1 source/data.1)) (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) (primitive/car/1 source/data.1)) (binding-value source/empty)) (value-boolean #f))) (primitive/cons/2 literal.225 (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/cc.2))) (primitive/cons/2 (primitive/map/2 (binding-value source/datum-show) source/data.1) (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/cc.2))))) (primitive/car/1 source/cc.2))))) (primitive/cdr/1 source/syntax-arg.1)))) ((lambda (source/value.92) (if (value-truth? (primitive/memv/2 source/value.92 literal.223)) (primitive/cons/2 literal.222 (primitive/map/2 (binding-value source/tast-show) source/syntax-arg.1)) ((lambda (source/value.93) (if (value-truth? (primitive/memv/2 source/value.93 literal.221)) (primitive/cons/2 literal.220 (primitive/map/2 (binding-value source/tast-show) source/syntax-arg.1)) ((lambda (source/value.94) (if (value-truth? (primitive/memv/2 source/value.94 literal.219)) (primitive/cons/2 literal.218 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.7 source/e.29) (primitive/list/2 (body/source/tast-show source/vd.7) (body/source/tast-show source/e.29))))) (primitive/caar/1 source/syntax-arg.1) (primitive/cdar/1 source/syntax-arg.1)) (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/syntax-arg.1)))) ((lambda (source/value.95) (if (value-truth? (primitive/memv/2 source/value.95 literal.217)) (primitive/cons/2 literal.216 (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.6 source/e.28) (primitive/list/2 (body/source/tast-show source/vd.6) (body/source/tast-show source/e.28))))) (primitive/caadr/1 source/syntax-arg.1) (primitive/cdadr/1 source/syntax-arg.1)) (primitive/map/2 (binding-value source/tast-show) (primitive/cddr/1 source/syntax-arg.1))))) ((lambda (source/value.96) (if (value-truth? (primitive/memv/2 source/value.96 literal.215)) (primitive/cons/2 literal.214 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.5 source/e.27) (primitive/list/2 (body/source/tast-show source/vd.5) (body/source/tast-show source/e.27))))) (primitive/caar/1 source/syntax-arg.1) (primitive/cdar/1 source/syntax-arg.1)) (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/syntax-arg.1)))) ((lambda (source/value.97) (if (value-truth? (primitive/memv/2 source/value.97 literal.213)) (primitive/cons/2 literal.212 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.4 source/e.26) (primitive/list/2 (body/source/tast-show source/vd.4) (body/source/tast-show source/e.26))))) (primitive/caar/1 source/syntax-arg.1) (primitive/cdar/1 source/syntax-arg.1)) (primitive/map/2 (binding-value source/tast-show) (primitive/cdr/1 source/syntax-arg.1)))) ((lambda (source/value.98) (if (value-truth? (primitive/memv/2 source/value.98 literal.211)) (primitive/cons/2 literal.210 (primitive/map/2 (binding-value source/tast-show) source/syntax-arg.1)) ((lambda (source/value.99) (if (value-truth? (primitive/memv/2 source/value.99 literal.209)) (primitive/error/3 literal.207 literal.208 source/syntax-arg.1) ((lambda (source/value.100) (if (value-truth? (primitive/memv/2 source/value.100 literal.206)) (primitive/error/2 literal.204 literal.205) ((lambda (source/value.101) (if (value-truth? (primitive/memv/2 source/value.101 literal.203)) (primitive/list/3 literal.202 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cdr/1 source/syntax-arg.1))) ((lambda (source/value.102) (if (value-truth? (primitive/memv/2 source/value.102 literal.201)) (primitive/cons/2 literal.200 (primitive/cons/2 (primitive/cons/2 (body/source/tast-show (primitive/car/1 source/syntax-arg.1)) (body/source/tast-show (primitive/cadr/1 source/syntax-arg.1))) (primitive/map/2 (binding-value source/tast-show) (primitive/cddr/1 source/syntax-arg.1)))) ((lambda (source/value.103) (if (value-truth? (primitive/memv/2 source/value.103 literal.199)) (primitive/cons/2 literal.198 (primitive/map/2 (binding-value source/tast-show) source/syntax-arg.1)) ((lambda (source/value.104) (primitive/error/3 literal.196 literal.197 source/syntax-op.2)) source/value.103))) source/value.102))) source/value.101))) source/value.100))) source/value.99))) source/value.98))) source/value.97))) source/value.96))) source/value.95))) source/value.94))) source/value.93))) source/value.92))) source/value.91))) source/value.90))) source/value.89))) source/value.88))) source/value.87))) source/value.86))) source/value.85))) source/value.84))) source/value.83))) source/value.82))) source/value.81))) source/value.80))) source/value.79))) source/syntax-op.2) source/syntax-tvar))
      (invoke-1 (binding-value source/ast-con) source/ast.2)
      (body/source/tvar-show (invoke-1 (binding-value source/ast-tvar) source/ast.2))
      (invoke-1 (binding-value source/ast-arg) source/ast.2))))

(ref-set! source/tast-show (value-procedure (ref (unit)) (function-1 body/source/tast-show)))

(define source/tast*-show (ref (value-uninitialized)))

(define body/source/tast*-show
  (lambda (source/p.1) (primitive/map/2 (binding-value source/tast-show) source/p.1)))

(ref-set! source/tast*-show (value-procedure (ref (unit)) (function-1 body/source/tast*-show)))

(define source/untag-counter (ref (value-uninitialized)))

(ref-set! source/untag-counter (value-number (exact-number 0)))

(define source/no-untag-counter (ref (value-uninitialized)))

(ref-set! source/no-untag-counter (value-number (exact-number 0)))

(define source/tag-counter (ref (value-uninitialized)))

(ref-set! source/tag-counter (value-number (exact-number 0)))

(define source/no-tag-counter (ref (value-uninitialized)))

(ref-set! source/no-tag-counter (value-number (exact-number 0)))

(define source/may-untag-counter (ref (value-uninitialized)))

(ref-set! source/may-untag-counter (value-number (exact-number 0)))

(define source/no-may-untag-counter (ref (value-uninitialized)))

(ref-set! source/no-may-untag-counter (value-number (exact-number 0)))

(define source/reset-counters! (ref (value-uninitialized)))

(define body/source/reset-counters!
  (lambda ()
    (begin
      (begin (ref-set! source/untag-counter (value-number (exact-number 0))) (value-unspecified))
      (begin (ref-set! source/no-untag-counter (value-number (exact-number 0))) (value-unspecified))
      (begin (ref-set! source/tag-counter (value-number (exact-number 0))) (value-unspecified))
      (begin (ref-set! source/no-tag-counter (value-number (exact-number 0))) (value-unspecified))
      (begin
        (ref-set! source/may-untag-counter (value-number (exact-number 0)))
        (value-unspecified))
      (begin
        (ref-set! source/no-may-untag-counter (value-number (exact-number 0)))
        (value-unspecified)))))

(ref-set!
  source/reset-counters!
  (value-procedure (ref (unit)) (function-0 body/source/reset-counters!)))

(define source/counters-show (ref (value-uninitialized)))

(define body/source/counters-show
  (lambda ()
    (primitive/list/3
      (primitive/cons/2 (binding-value source/tag-counter) (binding-value source/no-tag-counter))
      (primitive/cons/2
        (binding-value source/untag-counter)
        (binding-value source/no-untag-counter))
      (primitive/cons/2
        (binding-value source/may-untag-counter)
        (binding-value source/no-may-untag-counter)))))

(ref-set!
  source/counters-show
  (value-procedure (ref (unit)) (function-0 body/source/counters-show)))

(define source/tag-show (ref (value-uninitialized)))

(define body/source/tag-show
  (lambda (source/tvar-rep source/prog.2)
    (if (value-truth? (primitive/eqv?/2 source/tvar-rep (binding-value source/dynamic)))
      (begin
        (begin
          (ref-set!
            source/tag-counter
            (primitive/+/2 (binding-value source/tag-counter) (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.247 source/prog.2))
      (begin
        (begin
          (ref-set!
            source/no-tag-counter
            (primitive/+/2 (binding-value source/no-tag-counter) (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.246 source/prog.2)))))

(ref-set! source/tag-show (value-procedure (ref (unit)) (function-2 body/source/tag-show)))

(define source/untag-show (ref (value-uninitialized)))

(define body/source/untag-show
  (lambda (source/tvar-rep.1 source/prog.3)
    (if (value-truth? (primitive/eqv?/2 source/tvar-rep.1 (binding-value source/dynamic)))
      (begin
        (begin
          (ref-set!
            source/untag-counter
            (primitive/+/2 (binding-value source/untag-counter) (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.249 source/prog.3))
      (begin
        (begin
          (ref-set!
            source/no-untag-counter
            (primitive/+/2 (binding-value source/no-untag-counter) (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.248 source/prog.3)))))

(ref-set! source/untag-show (value-procedure (ref (unit)) (function-2 body/source/untag-show)))

(define source/may-untag-show (ref (value-uninitialized)))

(define body/source/may-untag-show
  (lambda (source/tvar-rep.2 source/prog.4)
    (if (value-truth? (primitive/eqv?/2 source/tvar-rep.2 (binding-value source/dynamic)))
      (begin
        (begin
          (ref-set!
            source/may-untag-counter
            (primitive/+/2 (binding-value source/may-untag-counter) (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.251 source/prog.4))
      (begin
        (begin
          (ref-set!
            source/no-may-untag-counter
            (primitive/+/2
              (binding-value source/no-may-untag-counter)
              (value-number (exact-number 1))))
          (value-unspecified))
        (primitive/list/2 literal.250 source/prog.4)))))

(ref-set!
  source/may-untag-show
  (value-procedure (ref (unit)) (function-2 body/source/may-untag-show)))

(define source/tag-ast-show (ref (value-uninitialized)))

(define body/source/tag-ast-show
  (lambda (source/ast.3)
    ((lambda (source/syntax-op.3 source/syntax-tvar.1 source/syntax-arg.2) ((lambda (source/value.105) (if (value-truth? (primitive/memv/2 source/value.105 literal.304)) (body/source/tag-show source/syntax-tvar.1 source/syntax-arg.2) ((lambda (source/value.106) (if (value-truth? (primitive/memv/2 source/value.106 literal.303)) source/syntax-arg.2 ((lambda (source/value.107) (if (value-truth? (primitive/memv/2 source/value.107 literal.302)) (value-null) ((lambda (source/value.108) (if (value-truth? (primitive/memv/2 source/value.108 literal.301)) (primitive/cons/2 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2))) ((lambda (source/value.109) (if (value-truth? (primitive/memv/2 source/value.109 literal.300)) (primitive/cons/2 (body/source/may-untag-show (body/source/find! (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/syntax-arg.2))) (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2))) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2))) ((lambda (source/value.110) (if (value-truth? (primitive/memv/2 source/value.110 literal.299)) (body/source/tag-show source/syntax-tvar.1 (primitive/list/2 literal.298 source/syntax-arg.2)) ((lambda (source/value.111) (if (value-truth? (primitive/memv/2 source/value.111 literal.297)) (body/source/tag-show source/syntax-tvar.1 (primitive/list->vector/1 (primitive/map/2 (binding-value source/tag-ast-show) source/syntax-arg.2))) ((lambda (source/value.112) (if (value-truth? (primitive/memv/2 source/value.112 literal.296)) (body/source/tag-show source/syntax-tvar.1 (primitive/list/3 literal.295 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2)))) ((lambda (source/value.113) (if (value-truth? (primitive/memv/2 source/value.113 literal.294)) (invoke-1 (binding-value source/ast-arg) source/syntax-arg.2) ((lambda (source/value.114) (if (value-truth? (primitive/memv/2 source/value.114 literal.293)) ((lambda (source/proc-tvar) (primitive/cons/2 (body/source/untag-show source/proc-tvar (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2))) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2)))) (body/source/find! (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/syntax-arg.2)))) ((lambda (source/value.115) (if (value-truth? (primitive/memv/2 source/value.115 literal.292)) (body/source/tag-show source/syntax-tvar.1 (primitive/cons/2 literal.291 (primitive/cons/2 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/syntax-arg.2))))) ((lambda (source/value.116) (if (value-truth? (primitive/memv/2 source/value.116 literal.290)) ((lambda (source/test-tvar) (primitive/cons/2 literal.289 (primitive/cons/2 (body/source/untag-show source/test-tvar (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2))) (primitive/cons/2 (body/source/tag-ast-show (primitive/cadr/1 source/syntax-arg.2)) ((lambda (source/alt.2) (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/alt.2) (binding-value source/empty))) (value-null) (primitive/list/1 (body/source/tag-ast-show source/alt.2)))) (primitive/cddr/1 source/syntax-arg.2)))))) (body/source/find! (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/syntax-arg.2)))) ((lambda (source/value.117) (if (value-truth? (primitive/memv/2 source/value.117 literal.288)) (primitive/list/3 literal.287 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2))) ((lambda (source/value.118) (if (value-truth? (primitive/memv/2 source/value.118 literal.286)) (primitive/cons/2 literal.284 (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc.5) ((lambda (source/guard.2 source/body.18) (primitive/cons/2 (if (value-truth? (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) source/guard.2) (binding-value source/empty))) literal.285 (body/source/untag-show (body/source/find! (invoke-1 (binding-value source/ast-tvar) source/guard.2)) (body/source/tag-ast-show source/guard.2))) (primitive/map/2 (binding-value source/tag-ast-show) source/body.18))) (primitive/car/1 source/cc.5) (primitive/cdr/1 source/cc.5))))) source/syntax-arg.2)) ((lambda (source/value.119) (if (value-truth? (primitive/memv/2 source/value.119 literal.283)) (primitive/cons/2 literal.281 (primitive/cons/2 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/cc.4) ((lambda (source/data.2) (if (value-truth? (if (value-truth? (primitive/pair?/1 source/data.2)) (primitive/eqv?/2 (invoke-1 (binding-value source/ast-con) (primitive/car/1 source/data.2)) (binding-value source/empty)) (value-boolean #f))) (primitive/cons/2 literal.282 (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/cc.4))) (primitive/cons/2 (primitive/map/2 (binding-value source/datum-show) source/data.2) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/cc.4))))) (primitive/car/1 source/cc.4))))) (primitive/cdr/1 source/syntax-arg.2)))) ((lambda (source/value.120) (if (value-truth? (primitive/memv/2 source/value.120 literal.280)) (primitive/cons/2 literal.279 (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/ast.5) ((lambda (source/bool-tvar.1) (body/source/untag-show source/bool-tvar.1 (body/source/tag-ast-show source/ast.5))) (body/source/find! (invoke-1 (binding-value source/ast-tvar) source/ast.5)))))) source/syntax-arg.2)) ((lambda (source/value.121) (if (value-truth? (primitive/memv/2 source/value.121 literal.278)) (primitive/cons/2 literal.277 (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/ast.4) ((lambda (source/bool-tvar) (body/source/untag-show source/bool-tvar (body/source/tag-ast-show source/ast.4))) (body/source/find! (invoke-1 (binding-value source/ast-tvar) source/ast.4)))))) source/syntax-arg.2)) ((lambda (source/value.122) (if (value-truth? (primitive/memv/2 source/value.122 literal.276)) (primitive/cons/2 literal.275 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.11 source/e.33) (primitive/list/2 (body/source/tag-ast-show source/vd.11) (body/source/tag-ast-show source/e.33))))) (primitive/caar/1 source/syntax-arg.2) (primitive/cdar/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/syntax-arg.2)))) ((lambda (source/value.123) (if (value-truth? (primitive/memv/2 source/value.123 literal.274)) (primitive/cons/2 literal.273 (primitive/cons/2 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.10 source/e.32) (primitive/list/2 (body/source/tag-ast-show source/vd.10) (body/source/tag-ast-show source/e.32))))) (primitive/caadr/1 source/syntax-arg.2) (primitive/cdadr/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cddr/1 source/syntax-arg.2))))) ((lambda (source/value.124) (if (value-truth? (primitive/memv/2 source/value.124 literal.272)) (primitive/cons/2 literal.271 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.9 source/e.31) (primitive/list/2 (body/source/tag-ast-show source/vd.9) (body/source/tag-ast-show source/e.31))))) (primitive/caar/1 source/syntax-arg.2) (primitive/cdar/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/syntax-arg.2)))) ((lambda (source/value.125) (if (value-truth? (primitive/memv/2 source/value.125 literal.270)) (primitive/cons/2 literal.269 (primitive/cons/2 (primitive/map/3 (value-procedure (ref (unit)) (function-2 (lambda (source/vd.8 source/e.30) (primitive/list/2 (body/source/tag-ast-show source/vd.8) (body/source/tag-ast-show source/e.30))))) (primitive/caar/1 source/syntax-arg.2) (primitive/cdar/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cdr/1 source/syntax-arg.2)))) ((lambda (source/value.126) (if (value-truth? (primitive/memv/2 source/value.126 literal.268)) (primitive/cons/2 literal.267 (primitive/map/2 (binding-value source/tag-ast-show) source/syntax-arg.2)) ((lambda (source/value.127) (if (value-truth? (primitive/memv/2 source/value.127 literal.266)) (primitive/error/3 literal.264 literal.265 source/syntax-arg.2) ((lambda (source/value.128) (if (value-truth? (primitive/memv/2 source/value.128 literal.263)) (primitive/error/2 literal.261 literal.262) ((lambda (source/value.129) (if (value-truth? (primitive/memv/2 source/value.129 literal.260)) (primitive/list/3 literal.259 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (body/source/tag-ast-show (primitive/cdr/1 source/syntax-arg.2))) ((lambda (source/value.130) (if (value-truth? (primitive/memv/2 source/value.130 literal.258)) ((lambda (source/func-tvar) (primitive/list/3 literal.256 (body/source/tag-ast-show (primitive/car/1 source/syntax-arg.2)) (body/source/tag-show source/func-tvar (primitive/cons/2 literal.257 (primitive/cons/2 (body/source/tag-ast-show (primitive/cadr/1 source/syntax-arg.2)) (primitive/map/2 (binding-value source/tag-ast-show) (primitive/cddr/1 source/syntax-arg.2))))))) (body/source/find! (invoke-1 (binding-value source/ast-tvar) (primitive/car/1 source/syntax-arg.2)))) ((lambda (source/value.131) (if (value-truth? (primitive/memv/2 source/value.131 literal.255)) (primitive/cons/2 literal.254 (primitive/map/2 (binding-value source/tag-ast-show) source/syntax-arg.2)) ((lambda (source/value.132) (primitive/error/3 literal.252 literal.253 source/syntax-op.3)) source/value.131))) source/value.130))) source/value.129))) source/value.128))) source/value.127))) source/value.126))) source/value.125))) source/value.124))) source/value.123))) source/value.122))) source/value.121))) source/value.120))) source/value.119))) source/value.118))) source/value.117))) source/value.116))) source/value.115))) source/value.114))) source/value.113))) source/value.112))) source/value.111))) source/value.110))) source/value.109))) source/value.108))) source/value.107))) source/value.106))) source/value.105))) source/syntax-op.3))
      (invoke-1 (binding-value source/ast-con) source/ast.3)
      (body/source/find! (invoke-1 (binding-value source/ast-tvar) source/ast.3))
      (invoke-1 (binding-value source/ast-arg) source/ast.3))))

(ref-set! source/tag-ast-show (value-procedure (ref (unit)) (function-1 body/source/tag-ast-show)))

(define source/tag-ast*-show (ref (value-uninitialized)))

(define body/source/tag-ast*-show
  (lambda (source/p.2) (primitive/map/2 (binding-value source/tag-ast-show) source/p.2)))

(ref-set!
  source/tag-ast*-show
  (value-procedure (ref (unit)) (function-1 body/source/tag-ast*-show)))

(define source/misc-env (ref (value-uninitialized)))

(ref-set!
  source/misc-env
  (primitive/list/4
    (primitive/cons/2
      literal.305
      (body/source/forall
        (value-procedure (ref (unit)) (function-1 (lambda (source/tv.4) source/tv.4)))))
    (primitive/cons/2
      literal.306
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.5)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/2 source/tv.5 source/tv.5))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.307
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.6)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/2 source/tv.6 source/tv.6))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.308
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.7)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/2 source/tv.7 source/tv.7))
                (body/source/boolean)))))))))

(define source/io-env (ref (value-uninitialized)))

(ref-set!
  source/io-env
  (primitive/list/7
    (primitive/cons/2
      literal.309
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/charseq)))
        (binding-value source/dynamic)))
    (primitive/cons/2
      literal.310
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (binding-value source/dynamic)))
        (body/source/boolean)))
    (primitive/cons/2
      literal.311
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.8)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.8))
                (binding-value source/dynamic)))))))
    (primitive/cons/2
      literal.312
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.9)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.9))
                (binding-value source/dynamic)))))))
    (primitive/cons/2
      literal.313
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.10)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.10))
                (binding-value source/dynamic)))))))
    (primitive/cons/2
      literal.314
      (body/source/procedure (body/source/null) (binding-value source/dynamic)))
    (primitive/cons/2
      literal.315
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.11)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.11))
                (binding-value source/dynamic)))))))))

(define source/boolean-env (ref (value-uninitialized)))

(ref-set!
  source/boolean-env
  (primitive/list/3
    (primitive/cons/2
      literal.316
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.12)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.12))
                (body/source/boolean)))))))
    (primitive/cons/2 (value-boolean #t) (body/source/boolean))
    (primitive/cons/2
      literal.317
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/boolean)))
        (body/source/boolean)))))

(define source/list-type (ref (value-uninitialized)))

(define body/source/list-type
  (lambda (source/tv.13)
    (body/source/fix
      (value-procedure
        (ref (unit))
        (function-1 (lambda (source/tv2.5) (body/source/pair source/tv.13 source/tv2.5)))))))

(ref-set! source/list-type (value-procedure (ref (unit)) (function-1 body/source/list-type)))

(define source/list-env (ref (value-uninitialized)))

(ref-set!
  source/list-env
  (primitive/list/33
    (primitive/cons/2
      literal.318
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.5 source/tv2.6)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1 (body/source/pair source/tv1.5 source/tv2.6)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.319
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.6 source/tv2.7)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1 (body/source/pair source/tv1.6 source/tv2.7)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.320
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.7 source/tv2.8)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1 (body/source/pair source/tv1.7 source/tv2.8)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.321
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.8 source/tv2.9)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/2 source/tv1.8 source/tv2.9))
                (body/source/pair source/tv1.8 source/tv2.9)))))))
    (primitive/cons/2
      literal.322
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.9 source/tv2.10)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1 (body/source/pair source/tv1.9 source/tv2.10)))
                source/tv1.9))))))
    (primitive/cons/2
      literal.323
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.10 source/tv2.11)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1 (body/source/pair source/tv1.10 source/tv2.11)))
                source/tv2.11))))))
    (primitive/cons/2
      literal.324
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.11 source/tv2.12)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 (body/source/pair source/tv1.11 source/tv2.12) source/tv1.11))
                (binding-value source/dynamic)))))))
    (primitive/cons/2
      literal.325
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.12 source/tv2.13)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 (body/source/pair source/tv1.12 source/tv2.13) source/tv2.13))
                (binding-value source/dynamic)))))))
    (primitive/cons/2
      literal.326
      (body/source/forall3
        (value-procedure
          (ref (unit))
          (function-3
            (lambda (source/tv1.13 source/tv2.14 source/tv3.3)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair (body/source/pair source/tv1.13 source/tv2.14) source/tv3.3)))
                source/tv1.13))))))
    (primitive/cons/2
      literal.327
      (body/source/forall3
        (value-procedure
          (ref (unit))
          (function-3
            (lambda (source/tv1.14 source/tv2.15 source/tv3.4)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair (body/source/pair source/tv1.14 source/tv2.15) source/tv3.4)))
                source/tv2.15))))))
    (primitive/cons/2
      literal.328
      (body/source/forall3
        (value-procedure
          (ref (unit))
          (function-3
            (lambda (source/tv1.15 source/tv2.16 source/tv3.5)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair source/tv1.15 (body/source/pair source/tv2.16 source/tv3.5))))
                source/tv2.16))))))
    (primitive/cons/2
      literal.329
      (body/source/forall3
        (value-procedure
          (ref (unit))
          (function-3
            (lambda (source/tv1.16 source/tv2.17 source/tv3.6)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair source/tv1.16 (body/source/pair source/tv2.17 source/tv3.6))))
                source/tv3.6))))))
    (primitive/cons/2
      literal.330
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.17 source/tv2.18 source/tv3.7 source/tv4.2)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      (body/source/pair (body/source/pair source/tv1.17 source/tv2.18) source/tv3.7)
                      source/tv4.2)))
                source/tv1.17))))))
    (primitive/cons/2
      literal.331
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.18 source/tv2.19 source/tv3.8 source/tv4.3)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      (body/source/pair (body/source/pair source/tv1.18 source/tv2.19) source/tv3.8)
                      source/tv4.3)))
                source/tv2.19))))))
    (primitive/cons/2
      literal.332
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.19 source/tv2.20 source/tv3.9 source/tv4.4)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      (body/source/pair source/tv1.19 (body/source/pair source/tv2.20 source/tv3.9))
                      source/tv4.4)))
                source/tv2.20))))))
    (primitive/cons/2
      literal.333
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.20 source/tv2.21 source/tv3.10 source/tv4.5)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      (body/source/pair
                        source/tv1.20
                        (body/source/pair source/tv2.21 source/tv3.10))
                      source/tv4.5)))
                source/tv3.10))))))
    (primitive/cons/2
      literal.334
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.21 source/tv2.22 source/tv3.11 source/tv4.6)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.21
                      (body/source/pair (body/source/pair source/tv2.22 source/tv3.11) source/tv4.6))))
                source/tv2.22))))))
    (primitive/cons/2
      literal.335
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.22 source/tv2.23 source/tv3.12 source/tv4.7)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.22
                      (body/source/pair (body/source/pair source/tv2.23 source/tv3.12) source/tv4.7))))
                source/tv3.12))))))
    (primitive/cons/2
      literal.336
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.23 source/tv2.24 source/tv3.13 source/tv4.8)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.23
                      (body/source/pair source/tv2.24 (body/source/pair source/tv3.13 source/tv4.8)))))
                source/tv3.13))))))
    (primitive/cons/2
      literal.337
      (body/source/forall4
        (value-procedure
          (ref (unit))
          (function-4
            (lambda (source/tv1.24 source/tv2.25 source/tv3.14 source/tv4.9)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.24
                      (body/source/pair source/tv2.25 (body/source/pair source/tv3.14 source/tv4.9)))))
                source/tv4.9))))))
    (primitive/cons/2
      literal.338
      (body/source/forall5
        (value-procedure
          (ref (unit))
          (function-5
            (lambda (source/tv1.25 source/tv2.26 source/tv3.15 source/tv4.10 source/tv5.1)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.25
                      (body/source/pair
                        source/tv2.26
                        (body/source/pair
                          source/tv3.15
                          (body/source/pair source/tv4.10 source/tv5.1))))))
                source/tv4.10))))))
    (primitive/cons/2
      literal.339
      (body/source/forall5
        (value-procedure
          (ref (unit))
          (function-5
            (lambda (source/tv1.26 source/tv2.27 source/tv3.16 source/tv4.11 source/tv5.2)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/pair
                      source/tv1.26
                      (body/source/pair
                        source/tv2.27
                        (body/source/pair
                          source/tv3.16
                          (body/source/pair source/tv4.11 source/tv5.2))))))
                source/tv5.2))))))
    (primitive/cons/2
      literal.340
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1 (lambda (source/tv.14) (body/source/procedure source/tv.14 source/tv.14))))))
    (primitive/cons/2
      literal.341
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.15)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 (body/source/list-type source/tv.15)))
                (body/source/number)))))))
    (primitive/cons/2
      literal.342
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.16)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    (body/source/list-type source/tv.16)
                    (body/source/list-type source/tv.16)))
                (body/source/list-type source/tv.16)))))))
    (primitive/cons/2
      literal.343
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.17)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 (body/source/list-type source/tv.17)))
                (body/source/list-type source/tv.17)))))))
    (primitive/cons/2
      literal.344
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.18)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 (body/source/list-type source/tv.18) (body/source/number)))
                source/tv.18))))))
    (primitive/cons/2
      literal.345
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.19)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 source/tv.19 (body/source/list-type source/tv.19)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.346
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.20)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 source/tv.20 (body/source/list-type source/tv.20)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.347
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.21)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 source/tv.21 (body/source/list-type source/tv.21)))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.348
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.27 source/tv2.28)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    source/tv1.27
                    (body/source/list-type (body/source/pair source/tv1.27 source/tv2.28))))
                (body/source/pair source/tv1.27 source/tv2.28)))))))
    (primitive/cons/2
      literal.349
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.28 source/tv2.29)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    source/tv1.28
                    (body/source/list-type (body/source/pair source/tv1.28 source/tv2.29))))
                (body/source/pair source/tv1.28 source/tv2.29)))))))
    (primitive/cons/2
      literal.350
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.29 source/tv2.30)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    source/tv1.29
                    (body/source/list-type (body/source/pair source/tv1.29 source/tv2.30))))
                (body/source/pair source/tv1.29 source/tv2.30)))))))))

(define source/symbol-env (ref (value-uninitialized)))

(ref-set!
  source/symbol-env
  (primitive/list/3
    (primitive/cons/2
      literal.351
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.22)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.22))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.352
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/symbol)))
        (body/source/charseq)))
    (primitive/cons/2
      literal.353
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/charseq)))
        (body/source/symbol)))))

(define source/number-env (ref (value-uninitialized)))

(ref-set!
  source/number-env
  (primitive/list/7
    (primitive/cons/2
      literal.354
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.23)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.23))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.355
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/2 (body/source/number) (body/source/number)))
        (body/source/number)))
    (primitive/cons/2
      literal.356
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/2 (body/source/number) (body/source/number)))
        (body/source/number)))
    (primitive/cons/2
      literal.357
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/2 (body/source/number) (body/source/number)))
        (body/source/number)))
    (primitive/cons/2
      literal.358
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/2 (body/source/number) (body/source/number)))
        (body/source/number)))
    (primitive/cons/2
      literal.359
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/number)))
        (body/source/charseq)))
    (primitive/cons/2
      literal.360
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/charseq)))
        (body/source/number)))))

(define source/char-env (ref (value-uninitialized)))

(ref-set!
  source/char-env
  (primitive/list/3
    (primitive/cons/2
      literal.361
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.24)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.24))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.362
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/character)))
        (body/source/number)))
    (primitive/cons/2
      literal.363
      (body/source/procedure
        (body/source/convert-tvars (primitive/list/1 (body/source/number)))
        (body/source/character)))))

(define source/string-env (ref (value-uninitialized)))

(ref-set!
  source/string-env
  (primitive/list/1
    (primitive/cons/2
      literal.364
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.25)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.25))
                (body/source/boolean)))))))))

(define source/vector-env (ref (value-uninitialized)))

(ref-set!
  source/vector-env
  (primitive/list/5
    (primitive/cons/2
      literal.365
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.26)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.26))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.366
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.27)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 (body/source/number)))
                (body/source/array source/tv.27)))))))
    (primitive/cons/2
      literal.367
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.28)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 (body/source/array source/tv.28)))
                (body/source/number)))))))
    (primitive/cons/2
      literal.368
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.29)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2 (body/source/array source/tv.29) (body/source/number)))
                source/tv.29))))))
    (primitive/cons/2
      literal.369
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.30)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/3
                    (body/source/array source/tv.30)
                    (body/source/number)
                    source/tv.30))
                (binding-value source/dynamic)))))))))

(define source/procedure-env (ref (value-uninitialized)))

(ref-set!
  source/procedure-env
  (primitive/list/4
    (primitive/cons/2
      literal.370
      (body/source/forall
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/tv.31)
              (body/source/procedure
                (body/source/convert-tvars (primitive/list/1 source/tv.31))
                (body/source/boolean)))))))
    (primitive/cons/2
      literal.371
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.30 source/tv2.31)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    (body/source/procedure
                      (body/source/convert-tvars (primitive/list/1 source/tv1.30))
                      source/tv2.31)
                    (body/source/list-type source/tv1.30)))
                (body/source/list-type source/tv2.31)))))))
    (primitive/cons/2
      literal.372
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.31 source/tv2.32)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/2
                    (body/source/procedure
                      (body/source/convert-tvars (primitive/list/1 source/tv1.31))
                      source/tv2.32)
                    (body/source/list-type source/tv1.31)))
                (body/source/list-type source/tv2.32)))))))
    (primitive/cons/2
      literal.373
      (body/source/forall2
        (value-procedure
          (ref (unit))
          (function-2
            (lambda (source/tv1.32 source/tv2.33)
              (body/source/procedure
                (body/source/convert-tvars
                  (primitive/list/1
                    (body/source/procedure
                      (body/source/convert-tvars
                        (primitive/list/1
                          (body/source/procedure
                            (body/source/convert-tvars (primitive/list/1 source/tv1.32))
                            source/tv2.33)))
                      source/tv2.33)))
                source/tv2.33))))))))

(define source/global-env (ref (value-uninitialized)))

(define body/source/global-env
  (lambda ()
    (primitive/append/10
      (binding-value source/misc-env)
      (binding-value source/io-env)
      (binding-value source/boolean-env)
      (binding-value source/symbol-env)
      (binding-value source/number-env)
      (binding-value source/char-env)
      (binding-value source/string-env)
      (binding-value source/vector-env)
      (binding-value source/procedure-env)
      (binding-value source/list-env))))

(ref-set! source/global-env (value-procedure (ref (unit)) (function-0 body/source/global-env)))

(define source/dynamic-top-level-env (ref (value-uninitialized)))

(ref-set! source/dynamic-top-level-env (body/source/global-env))

(define source/init-dynamic-top-level-env! (ref (value-uninitialized)))

(define body/source/init-dynamic-top-level-env!
  (lambda ()
    (begin
      (begin (ref-set! source/dynamic-top-level-env (body/source/global-env)) (value-unspecified))
      (value-null))))

(ref-set!
  source/init-dynamic-top-level-env!
  (value-procedure (ref (unit)) (function-0 body/source/init-dynamic-top-level-env!)))

(define source/dynamic-top-level-env-show (ref (value-uninitialized)))

(define body/source/dynamic-top-level-env-show
  (lambda ()
    (primitive/map/2
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/binding.3)
            (primitive/cons/2
              (body/source/key-show (invoke-1 (binding-value source/binding-key) source/binding.3))
              (primitive/cons/2
                literal.374
                (body/source/tvar-show
                  (invoke-1 (binding-value source/binding-value) source/binding.3)))))))
      (body/source/env->list (binding-value source/dynamic-top-level-env)))))

(ref-set!
  source/dynamic-top-level-env-show
  (value-procedure (ref (unit)) (function-0 body/source/dynamic-top-level-env-show)))

(define source/ic! (ref (value-uninitialized)))

(define body/source/ic! (lambda () (body/source/init-global-constraints!)))

(ref-set! source/ic! (value-procedure (ref (unit)) (function-0 body/source/ic!)))

(define source/pc (ref (value-uninitialized)))

(define body/source/pc (lambda () (body/source/glob-constr-show)))

(ref-set! source/pc (value-procedure (ref (unit)) (function-0 body/source/pc)))

(define source/lc (ref (value-uninitialized)))

(define body/source/lc (lambda () (primitive/length/1 (binding-value source/global-constraints))))

(ref-set! source/lc (value-procedure (ref (unit)) (function-0 body/source/lc)))

(define source/n! (ref (value-uninitialized)))

(define body/source/n! (lambda () (body/source/normalize-global-constraints!)))

(ref-set! source/n! (value-procedure (ref (unit)) (function-0 body/source/n!)))

(define source/pt (ref (value-uninitialized)))

(define body/source/pt (lambda () (body/source/dynamic-top-level-env-show)))

(ref-set! source/pt (value-procedure (ref (unit)) (function-0 body/source/pt)))

(define source/it! (ref (value-uninitialized)))

(define body/source/it! (lambda () (body/source/init-dynamic-top-level-env!)))

(ref-set! source/it! (value-procedure (ref (unit)) (function-0 body/source/it!)))

(define source/io! (ref (value-uninitialized)))

(define body/source/io!
  (lambda ()
    (begin
      (begin (ref-set! source/tag-ops (value-number (exact-number 0))) (value-unspecified))
      (begin (ref-set! source/no-ops (value-number (exact-number 0))) (value-unspecified)))))

(ref-set! source/io! (value-procedure (ref (unit)) (function-0 body/source/io!)))

(define source/i! (ref (value-uninitialized)))

(define body/source/i!
  (lambda () (begin (body/source/ic!) (body/source/it!) (body/source/io!) (value-null))))

(ref-set! source/i! (value-procedure (ref (unit)) (function-0 body/source/i!)))

(define source/tag-ops (ref (value-uninitialized)))

(ref-set! source/tag-ops (value-number (exact-number 0)))

(define source/no-ops (ref (value-uninitialized)))

(ref-set! source/no-ops (value-number (exact-number 0)))

(define source/doit (ref (value-uninitialized)))

(define body/source/doit
  (lambda (source/input-file)
    (begin
      (body/source/i!)
      ((lambda (source/foo) (begin (body/source/normalize-global-constraints!) (body/source/reset-counters!) (body/source/tag-ast*-show source/foo) (body/source/counters-show)))
        (body/source/dynamic-parse-file source/input-file)))))

(ref-set! source/doit (value-procedure (ref (unit)) (function-1 body/source/doit)))

(begin
  (host:define-record-type
    (specification/record specification is-specification)
    (fields
      (immutable count specification-count)
      (immutable input specification-input)
      (immutable expected specification-expected))))

(define read-specification
  (lambda (port)
    (let ((count (integer->i64 (number->integer (datum-number-value (read-value! (read port)))))))
      (let ((input (datum->value (read-value! (read port)))))
        (specification count input (datum->value (read-value! (read port))))))))

(define configured (call-with-input-file "input.txt" read-specification))

(define configured-count (lambda () (specification-count configured)))

(define barrier (lambda () #t))

(define bench
  (lambda (count)
    (let ((repeat #f))
      (set!
        repeat
        (lambda (index result)
          (if (< index count)
            (repeat
              (+ index 1)
              (body/source/doit (if (barrier) (specification-input configured) (unreachable))))
            (if (value-equal? result (specification-expected configured)) 1 0))))
      (repeat 0 (value-boolean #f)))))

(unit)

;; ---- The canonical count and original predicate govern the control ----
(define (monotonic-nanoseconds)
 (let ((now (current-time 'time-monotonic))) (+ (* (time-second now) 1000000000) (time-nanosecond now))))
(let* ((count (configured-count)) (start (monotonic-nanoseconds)) (result (bench count))
       (seconds (inexact (/ (- (monotonic-nanoseconds) start) 1000000000))))
 (unless (= result 1) (error 'dynamic "incorrect result" result))
 (display "+!CSVLINE!+chez-adapted,dynamic:") (display count) (display ",") (write seconds) (newline))
