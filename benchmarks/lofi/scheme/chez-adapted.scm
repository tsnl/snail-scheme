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
    (function-rest-0/record function-rest-0 is-function-rest-0)
    (fields (immutable body function-rest-0-body)))
  (host:define-record-type
    (function-rest-1/record function-rest-1 is-function-rest-1)
    (fields (immutable body function-rest-1-body)))
  (host:define-record-type
    (function-rest-2/record function-rest-2 is-function-rest-2)
    (fields (immutable body function-rest-2-body)))
  (host:define-record-type
    (function-rest-3/record function-rest-3 is-function-rest-3)
    (fields (immutable body function-rest-3-body))))

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

(define invoke-0
  (lambda (procedure)
    (let ((matched-value.8 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.8) (let ((body (function-0-body matched-value.8))) (body)))
        ((is-function-1 matched-value.8)
          (let ((body (function-1-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.8)
          (let ((body (function-2-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.8)
          (let ((body (function-3-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.8)
          (let ((body (function-4-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-0 matched-value.8)
          (let ((body (function-rest-0-body matched-value.8))) (body (value-null))))
        ((is-function-rest-1 matched-value.8)
          (let ((body (function-rest-1-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-2 matched-value.8)
          (let ((body (function-rest-2-body matched-value.8)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-3 matched-value.8)
          (let ((body (function-rest-3-body matched-value.8)))
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

(define invoke-1
  (lambda (procedure a0)
    (let ((matched-value.10 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.10)
          (let ((body (function-0-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.10)
          (let ((body (function-1-body matched-value.10))) (body a0)))
        ((is-function-2 matched-value.10)
          (let ((body (function-2-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-3 matched-value.10)
          (let ((body (function-3-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.10)
          (let ((body (function-4-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-0 matched-value.10)
          (let ((body (function-rest-0-body matched-value.10))) (body (value-cons a0 (value-null)))))
        ((is-function-rest-1 matched-value.10)
          (let ((body (function-rest-1-body matched-value.10))) (body a0 (value-null))))
        ((is-function-rest-2 matched-value.10)
          (let ((body (function-rest-2-body matched-value.10)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-3 matched-value.10)
          (let ((body (function-rest-3-body matched-value.10)))
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

(define invoke-2
  (lambda (procedure a0 a1)
    (let ((matched-value.12 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.12)
          (let ((body (function-0-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-1 matched-value.12)
          (let ((body (function-1-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-2 matched-value.12)
          (let ((body (function-2-body matched-value.12))) (body a0 a1)))
        ((is-function-3 matched-value.12)
          (let ((body (function-3-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-4 matched-value.12)
          (let ((body (function-4-body matched-value.12)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-0 matched-value.12)
          (let ((body (function-rest-0-body matched-value.12)))
            (body (value-cons a0 (value-cons a1 (value-null))))))
        ((is-function-rest-1 matched-value.12)
          (let ((body (function-rest-1-body matched-value.12)))
            (body a0 (value-cons a1 (value-null)))))
        ((is-function-rest-2 matched-value.12)
          (let ((body (function-rest-2-body matched-value.12))) (body a0 a1 (value-null))))
        ((is-function-rest-3 matched-value.12)
          (let ((body (function-rest-3-body matched-value.12)))
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

(define invoke-3
  (lambda (procedure a0 a1 a2)
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
          (let ((body (function-3-body matched-value.14))) (body a0 a1 a2)))
        ((is-function-4 matched-value.14)
          (let ((body (function-4-body matched-value.14)))
            (datum-fail "procedure argument count mismatch")))
        ((is-function-rest-0 matched-value.14)
          (let ((body (function-rest-0-body matched-value.14)))
            (body (value-cons a0 (value-cons a1 (value-cons a2 (value-null)))))))
        ((is-function-rest-1 matched-value.14)
          (let ((body (function-rest-1-body matched-value.14)))
            (body a0 (value-cons a1 (value-cons a2 (value-null))))))
        ((is-function-rest-2 matched-value.14)
          (let ((body (function-rest-2-body matched-value.14)))
            (body a0 a1 (value-cons a2 (value-null)))))
        ((is-function-rest-3 matched-value.14)
          (let ((body (function-rest-3-body matched-value.14))) (body a0 a1 a2 (value-null))))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            14
            (debug-source-stack)
            (if (host:record? matched-value.14)
              (host:record-type-name (host:record-rtd matched-value.14))
              "nonrecord")))))))

(define invoke-4
  (lambda (procedure a0 a1 a2 a3)
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
          (let ((body (function-4-body matched-value.16))) (body a0 a1 a2 a3)))
        ((is-function-rest-0 matched-value.16)
          (let ((body (function-rest-0-body matched-value.16)))
            (body (value-cons a0 (value-cons a1 (value-cons a2 (value-cons a3 (value-null))))))))
        ((is-function-rest-1 matched-value.16)
          (let ((body (function-rest-1-body matched-value.16)))
            (body a0 (value-cons a1 (value-cons a2 (value-cons a3 (value-null)))))))
        ((is-function-rest-2 matched-value.16)
          (let ((body (function-rest-2-body matched-value.16)))
            (body a0 a1 (value-cons a2 (value-cons a3 (value-null))))))
        ((is-function-rest-3 matched-value.16)
          (let ((body (function-rest-3-body matched-value.16)))
            (body a0 a1 a2 (value-cons a3 (value-null)))))
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

(define primitive/-/2
  (lambda (a0 a1)
    (value-number (number-subtract (value-number-number a0) (value-number-number a1)))))

(define primitive/</2
  (lambda (a0 a1) (value-boolean (number<? (value-number-number a0) (value-number-number a1)))))

(define primitive/<=/2
  (lambda (a0 a1) (value-boolean (number<=? (value-number-number a0) (value-number-number a1)))))

(define primitive/=/2
  (lambda (a0 a1) (value-boolean (number=? (value-number-number a0) (value-number-number a1)))))

(define primitive/abs/1 (lambda (a0) (value-number (number-abs (value-number-number a0)))))

(define primitive/acos/1 (lambda (a0) (value-number (numeric-acos (value-number-number a0)))))

(define primitive/append/2 (lambda (a0 a1) (value-append a0 a1)))

(define primitive/apply/2 (lambda (a0 a1) (invoke-list a0 a1)))

(define primitive/asin/1 (lambda (a0) (value-number (numeric-asin (value-number-number a0)))))

(define primitive/assoc/2 (lambda (a0 a1) (value-assoc a0 a1 value-equal?)))

(define primitive/assq/2 (lambda (a0 a1) (value-assoc a0 a1 value-eq?)))

(define primitive/assv/2 (lambda (a0 a1) (value-assoc a0 a1 value-eq?)))

(define primitive/atan/1 (lambda (a0) (value-number (numeric-atan (value-number-number a0)))))

(define primitive/atan/2
  (lambda (a0 a1)
    (value-number
      (inexact-number
        (atan2 (number->f64 (value-number-number a0)) (number->f64 (value-number-number a1)))))))

(define primitive/boolean?/1 (lambda (a0) (value-boolean (value-boolean? a0))))

(define primitive/caaaar/1 (lambda (a0) (value-car (value-car (value-car (value-car a0))))))

(define primitive/caaadr/1 (lambda (a0) (value-car (value-car (value-car (value-cdr a0))))))

(define primitive/caaar/1 (lambda (a0) (value-car (value-car (value-car a0)))))

(define primitive/caadar/1 (lambda (a0) (value-car (value-car (value-cdr (value-car a0))))))

(define primitive/caaddr/1 (lambda (a0) (value-car (value-car (value-cdr (value-cdr a0))))))

(define primitive/caadr/1 (lambda (a0) (value-car (value-car (value-cdr a0)))))

(define primitive/caar/1 (lambda (a0) (value-car (value-car a0))))

(define primitive/cadaar/1 (lambda (a0) (value-car (value-cdr (value-car (value-car a0))))))

(define primitive/cadadr/1 (lambda (a0) (value-car (value-cdr (value-car (value-cdr a0))))))

(define primitive/cadar/1 (lambda (a0) (value-car (value-cdr (value-car a0)))))

(define primitive/caddar/1 (lambda (a0) (value-car (value-cdr (value-cdr (value-car a0))))))

(define primitive/cadddr/1 (lambda (a0) (value-car (value-cdr (value-cdr (value-cdr a0))))))

(define primitive/caddr/1 (lambda (a0) (value-car (value-cdr (value-cdr a0)))))

(define primitive/cadr/1 (lambda (a0) (value-car (value-cdr a0))))

(define primitive/call-with-input-file/2
  (lambda (a0 a1)
    (call-with-input-file
      (value-string-string a0)
      (lambda (port) (invoke-1 a1 (value-input (ref (unit)) port))))))

(define primitive/call-with-output-file/2
  (lambda (a0 a1)
    (call-with-output-file
      (value-string-string a0)
      (lambda (port) (invoke-1 a1 (value-output port))))))

(define primitive/car/1 (lambda (a0) (value-car a0)))

(define primitive/cdaaar/1 (lambda (a0) (value-cdr (value-car (value-car (value-car a0))))))

(define primitive/cdaadr/1 (lambda (a0) (value-cdr (value-car (value-car (value-cdr a0))))))

(define primitive/cdaar/1 (lambda (a0) (value-cdr (value-car (value-car a0)))))

(define primitive/cdadar/1 (lambda (a0) (value-cdr (value-car (value-cdr (value-car a0))))))

(define primitive/cdaddr/1 (lambda (a0) (value-cdr (value-car (value-cdr (value-cdr a0))))))

(define primitive/cdadr/1 (lambda (a0) (value-cdr (value-car (value-cdr a0)))))

(define primitive/cdar/1 (lambda (a0) (value-cdr (value-car a0))))

(define primitive/cddaar/1 (lambda (a0) (value-cdr (value-cdr (value-car (value-car a0))))))

(define primitive/cddadr/1 (lambda (a0) (value-cdr (value-cdr (value-car (value-cdr a0))))))

(define primitive/cddar/1 (lambda (a0) (value-cdr (value-cdr (value-car a0)))))

(define primitive/cdddar/1 (lambda (a0) (value-cdr (value-cdr (value-cdr (value-car a0))))))

(define primitive/cddddr/1 (lambda (a0) (value-cdr (value-cdr (value-cdr (value-cdr a0))))))

(define primitive/cdddr/1 (lambda (a0) (value-cdr (value-cdr (value-cdr a0)))))

(define primitive/cddr/1 (lambda (a0) (value-cdr (value-cdr a0))))

(define primitive/cdr/1 (lambda (a0) (value-cdr a0)))

(define primitive/ceiling/1 (lambda (a0) (value-number (numeric-ceiling (value-number-number a0)))))

(define primitive/char->integer/1
  (lambda (a0) (value-number (exact-number (char->integer (value-character-character a0))))))

(define primitive/char-alphabetic?/1
  (lambda (a0) (value-boolean (char-alphabetic? (value-character-character a0)))))

(define primitive/char-ci<=?/2
  (lambda (a0 a1)
    (value-boolean
      (char<=?
        (char-foldcase (value-character-character a0))
        (char-foldcase (value-character-character a1))))))

(define primitive/char-ci<?/2
  (lambda (a0 a1)
    (value-boolean
      (char<?
        (char-foldcase (value-character-character a0))
        (char-foldcase (value-character-character a1))))))

(define primitive/char-ci=?/2
  (lambda (a0 a1)
    (value-boolean
      (char=?
        (char-foldcase (value-character-character a0))
        (char-foldcase (value-character-character a1))))))

(define primitive/char-ci>=?/2
  (lambda (a0 a1)
    (value-boolean
      (char>=?
        (char-foldcase (value-character-character a0))
        (char-foldcase (value-character-character a1))))))

(define primitive/char-ci>?/2
  (lambda (a0 a1)
    (value-boolean
      (char>?
        (char-foldcase (value-character-character a0))
        (char-foldcase (value-character-character a1))))))

(define primitive/char-downcase/1
  (lambda (a0) (value-character (char-downcase (value-character-character a0)))))

(define primitive/char-lower-case?/1
  (lambda (a0) (value-boolean (char-lower-case? (value-character-character a0)))))

(define primitive/char-numeric?/1
  (lambda (a0) (value-boolean (char-numeric? (value-character-character a0)))))

(define primitive/char-upcase/1
  (lambda (a0) (value-character (char-upcase (value-character-character a0)))))

(define primitive/char-whitespace?/1
  (lambda (a0) (value-boolean (char-whitespace? (value-character-character a0)))))

(define primitive/char<=?/2
  (lambda (a0 a1)
    (value-boolean (char<=? (value-character-character a0) (value-character-character a1)))))

(define primitive/char<?/2
  (lambda (a0 a1)
    (value-boolean (char<? (value-character-character a0) (value-character-character a1)))))

(define primitive/char=?/2
  (lambda (a0 a1)
    (value-boolean (char=? (value-character-character a0) (value-character-character a1)))))

(define primitive/char>=?/2
  (lambda (a0 a1)
    (value-boolean (char>=? (value-character-character a0) (value-character-character a1)))))

(define primitive/char>?/2
  (lambda (a0 a1)
    (value-boolean (char>? (value-character-character a0) (value-character-character a1)))))

(define primitive/char?/1 (lambda (a0) (value-boolean (value-character? a0))))

(define primitive/close-input-port/1
  (lambda (a0) (begin (close-input-port (value-input-port a0)) (value-unspecified))))

(define primitive/close-output-port/1
  (lambda (a0) (begin (close-output-port (value-output-port a0)) (value-unspecified))))

(define primitive/complex?/1 (lambda (a0) (value-boolean (value-number? a0))))

(define primitive/cons/2 (lambda (a0 a1) (value-cons a0 a1)))

(define primitive/cos/1 (lambda (a0) (value-number (numeric-cos (value-number-number a0)))))

(define primitive/current-input-port/0 (lambda () standard-input-value))

(define primitive/current-output-port/0 (lambda () (value-output (current-output-port))))

(define primitive/display/1 (lambda (a0) (begin (display (value->datum a0)) (value-unspecified))))

(define primitive/display/2
  (lambda (a0 a1) (begin (display (value->datum a0) (value-output-port a1)) (value-unspecified))))

(define primitive/eof-object?/1 (lambda (a0) (value-boolean (value-eof? a0))))

(define primitive/eq?/2 (lambda (a0 a1) (value-boolean (value-eq? a0 a1))))

(define primitive/equal?/2 (lambda (a0 a1) (value-boolean (value-equal? a0 a1))))

(define primitive/eqv?/2 (lambda (a0 a1) (value-boolean (value-eq? a0 a1))))

(define primitive/error/3
  (lambda (a0 a1 a2) (value-error (value-cons a0 (value-cons a1 (value-cons a2 (value-null)))))))

(define primitive/exact/1 (lambda (a0) (value-number (number-exact (value-number-number a0)))))

(define primitive/exact?/1 (lambda (a0) (value-boolean (number-exact? (value-number-number a0)))))

(define primitive/exp/1 (lambda (a0) (value-number (numeric-exp (value-number-number a0)))))

(define primitive/expt/2
  (lambda (a0 a1) (value-number (numeric-expt (value-number-number a0) (value-number-number a1)))))

(define primitive/floor/1 (lambda (a0) (value-number (numeric-floor (value-number-number a0)))))

(define primitive/inexact/1 (lambda (a0) (value-number (number-inexact (value-number-number a0)))))

(define primitive/inexact?/1
  (lambda (a0) (value-boolean (not (number-exact? (value-number-number a0))))))

(define primitive/input-port?/1 (lambda (a0) (value-boolean (value-input? a0))))

(define primitive/integer->char/1
  (lambda (a0)
    (value-character (integer->char (integer->i64 (number->integer (value-number-number a0)))))))

(define primitive/integer?/1
  (lambda (a0)
    (value-boolean (if (value-number? a0) (number-integer? (value-number-number a0)) #f))))

(define primitive/length/1 (lambda (a0) (value-number (exact-number (value-length a0)))))

(define primitive/list/1 (lambda (a0) (value-cons a0 (value-null))))

(define primitive/list/2 (lambda (a0 a1) (value-cons a0 (value-cons a1 (value-null)))))

(define primitive/list/3
  (lambda (a0 a1 a2) (value-cons a0 (value-cons a1 (value-cons a2 (value-null))))))

(define primitive/list-ref/2
  (lambda (a0 a1)
    (value-car (value-tail a0 (integer->i64 (number->integer (value-number-number a1)))))))

(define primitive/list?/1 (lambda (a0) (value-boolean (value-list? a0))))

(define primitive/log/1 (lambda (a0) (value-number (numeric-log (value-number-number a0)))))

(define primitive/log/2
  (lambda (a0 a1)
    (value-number
      (number-divide (numeric-log (value-number-number a0)) (numeric-log (value-number-number a1))))))

(define primitive/make-string/1
  (lambda (a0)
    (value-string (make-string (integer->i64 (number->integer (value-number-number a0)))))))

(define primitive/make-string/2
  (lambda (a0 a1)
    (value-string
      (make-string
        (integer->i64 (number->integer (value-number-number a0)))
        (value-character-character a1)))))

(define primitive/make-vector/1
  (lambda (a0)
    (value-vector
      (make-vector (integer->i64 (number->integer (value-number-number a0))) (value-unspecified)))))

(define primitive/make-vector/2
  (lambda (a0 a1)
    (value-vector (make-vector (integer->i64 (number->integer (value-number-number a0))) a1))))

(define primitive/member/2 (lambda (a0 a1) (value-member a0 a1 value-equal?)))

(define primitive/memq/2 (lambda (a0 a1) (value-member a0 a1 value-eq?)))

(define primitive/memv/2 (lambda (a0 a1) (value-member a0 a1 value-eq?)))

(define primitive/newline/0 (lambda () (begin (newline) (value-unspecified))))

(define primitive/newline/1
  (lambda (a0) (begin (newline (value-output-port a0)) (value-unspecified))))

(define primitive/not/1 (lambda (a0) (value-boolean (not (value-truth? a0)))))

(define primitive/null?/1 (lambda (a0) (value-boolean (value-null? a0))))

(define primitive/number->string/1
  (lambda (a0) (value-string (number->string (value-number-number a0)))))

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

(define primitive/output-port?/1 (lambda (a0) (value-boolean (value-output? a0))))

(define primitive/pair?/1 (lambda (a0) (value-boolean (value-pair? a0))))

(define primitive/peek-char/0
  (lambda ()
    (let ((matched-value.20 (peek-char (current-input-port))))
      (cond
        ((is-character-end matched-value.20) (let () (value-eof)))
        ((is-character-value matched-value.20)
          (let ((c (character-value-character matched-value.20))) (value-character c)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            20
            (debug-source-stack)
            (if (host:record? matched-value.20)
              (host:record-type-name (host:record-rtd matched-value.20))
              "nonrecord")))))))

(define primitive/peek-char/1
  (lambda (a0)
    (let ((matched-value.22 (peek-char (value-input-port a0))))
      (cond
        ((is-character-end matched-value.22) (let () (value-eof)))
        ((is-character-value matched-value.22)
          (let ((c (character-value-character matched-value.22))) (value-character c)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            22
            (debug-source-stack)
            (if (host:record? matched-value.22)
              (host:record-type-name (host:record-rtd matched-value.22))
              "nonrecord")))))))

(define primitive/procedure?/1 (lambda (a0) (value-boolean (value-procedure? a0))))

(define primitive/rational?/1
  (lambda (a0)
    (value-boolean (if (value-number? a0) (number-rational? (value-number-number a0)) #f))))

(define primitive/read/0 (lambda () (read-source-value (current-input-port))))

(define primitive/read/1 (lambda (a0) (read-source-value (value-input-port a0))))

(define primitive/read-char/0
  (lambda ()
    (let ((matched-value.24 (read-char (current-input-port))))
      (cond
        ((is-character-end matched-value.24) (let () (value-eof)))
        ((is-character-value matched-value.24)
          (let ((c (character-value-character matched-value.24))) (value-character c)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            24
            (debug-source-stack)
            (if (host:record? matched-value.24)
              (host:record-type-name (host:record-rtd matched-value.24))
              "nonrecord")))))))

(define primitive/read-char/1
  (lambda (a0)
    (let ((matched-value.26 (read-char (value-input-port a0))))
      (cond
        ((is-character-end matched-value.26) (let () (value-eof)))
        ((is-character-value matched-value.26)
          (let ((c (character-value-character matched-value.26))) (value-character c)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            26
            (debug-source-stack)
            (if (host:record? matched-value.26)
              (host:record-type-name (host:record-rtd matched-value.26))
              "nonrecord")))))))

(define primitive/real?/1
  (lambda (a0) (value-boolean (if (value-number? a0) (number-real? (value-number-number a0)) #f))))

(define primitive/reverse/1 (lambda (a0) (value-reverse a0 (value-null))))

(define primitive/round/1 (lambda (a0) (value-number (numeric-round (value-number-number a0)))))

(define primitive/set-car!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-first a0) a1) (value-unspecified))))

(define primitive/set-cdr!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-rest a0) a1) (value-unspecified))))

(define primitive/sin/1 (lambda (a0) (value-number (numeric-sin (value-number-number a0)))))

(define primitive/sqrt/1 (lambda (a0) (value-number (numeric-sqrt (value-number-number a0)))))

(define primitive/string->number/1
  (lambda (a0) (parsed-number->value (string->number (value-string-string a0)))))

(define primitive/string->number/2
  (lambda (a0 a1)
    (parsed-number->value
      (string->number/radix
        (value-string-string a0)
        (integer->i64 (number->integer (value-number-number a1)))))))

(define primitive/string->symbol/1
  (lambda (a0) (value-symbol (string->symbol (value-string-string a0)))))

(define primitive/string-ci<=?/2
  (lambda (a0 a1)
    (value-boolean
      (<=
        (value-compare-strings
          (string-foldcase (value-string-string a0))
          (string-foldcase (value-string-string a1))
          0)
        0))))

(define primitive/string-ci<?/2
  (lambda (a0 a1)
    (value-boolean
      (<
        (value-compare-strings
          (string-foldcase (value-string-string a0))
          (string-foldcase (value-string-string a1))
          0)
        0))))

(define primitive/string-ci=?/2
  (lambda (a0 a1)
    (value-boolean
      (=
        (value-compare-strings
          (string-foldcase (value-string-string a0))
          (string-foldcase (value-string-string a1))
          0)
        0))))

(define primitive/string-ci>=?/2
  (lambda (a0 a1)
    (value-boolean
      (>=
        (value-compare-strings
          (string-foldcase (value-string-string a0))
          (string-foldcase (value-string-string a1))
          0)
        0))))

(define primitive/string-ci>?/2
  (lambda (a0 a1)
    (value-boolean
      (>
        (value-compare-strings
          (string-foldcase (value-string-string a0))
          (string-foldcase (value-string-string a1))
          0)
        0))))

(define primitive/string-length/1
  (lambda (a0) (value-number (exact-number (string-length (value-string-string a0))))))

(define primitive/string-ref/2
  (lambda (a0 a1)
    (value-character
      (string-ref
        (value-string-string a0)
        (integer->i64 (number->integer (value-number-number a1)))))))

(define primitive/string-set!/3
  (lambda (a0 a1 a2)
    (begin
      (string-set!
        (value-string-string a0)
        (integer->i64 (number->integer (value-number-number a1)))
        (value-character-character a2))
      (value-unspecified))))

(define primitive/string<=?/2
  (lambda (a0 a1)
    (value-boolean
      (<= (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/string<?/2
  (lambda (a0 a1)
    (value-boolean
      (< (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/string=?/2
  (lambda (a0 a1)
    (value-boolean
      (= (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/string>=?/2
  (lambda (a0 a1)
    (value-boolean
      (>= (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/string>?/2
  (lambda (a0 a1)
    (value-boolean
      (> (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/string?/1 (lambda (a0) (value-boolean (value-string? a0))))

(define primitive/substring/3
  (lambda (a0 a1 a2)
    (value-string
      (substring
        (value-string-string a0)
        (integer->i64 (number->integer (value-number-number a1)))
        (integer->i64 (number->integer (value-number-number a2)))))))

(define primitive/symbol->string/1
  (lambda (a0) (value-string (symbol->string (value-symbol-symbol a0)))))

(define primitive/symbol?/1 (lambda (a0) (value-boolean (value-symbol? a0))))

(define primitive/tan/1 (lambda (a0) (value-number (numeric-tan (value-number-number a0)))))

(define primitive/truncate/1
  (lambda (a0) (value-number (number-truncate (value-number-number a0)))))

(define primitive/vector/2 (lambda (a0 a1) (value-vector (vector a0 a1))))

(define primitive/vector/3 (lambda (a0 a1 a2) (value-vector (vector a0 a1 a2))))

(define primitive/vector/4 (lambda (a0 a1 a2 a3) (value-vector (vector a0 a1 a2 a3))))

(define primitive/vector-length/1
  (lambda (a0) (value-number (exact-number (vector-length (value-vector-vector a0))))))

(define primitive/vector-ref/2
  (lambda (a0 a1)
    (vector-ref (value-vector-vector a0) (integer->i64 (number->integer (value-number-number a1))))))

(define primitive/vector-set!/3
  (lambda (a0 a1 a2)
    (begin
      (vector-set!
        (value-vector-vector a0)
        (integer->i64 (number->integer (value-number-number a1)))
        a2)
      (value-unspecified))))

(define primitive/vector?/1 (lambda (a0) (value-boolean (value-vector? a0))))

(define primitive/write/1 (lambda (a0) (begin (write (value->datum a0)) (value-unspecified))))

(define primitive/write/2
  (lambda (a0 a1) (begin (write (value->datum a0) (value-output-port a1)) (value-unspecified))))

(define primitive/write-char/1
  (lambda (a0) (begin (write-char (value-character-character a0)) (value-unspecified))))

(define primitive/write-char/2
  (lambda (a0 a1)
    (begin (write-char (value-character-character a0) (value-output-port a1)) (value-unspecified))))

(define primitive-value/boolean? (value-procedure (ref (unit)) (function-1 primitive/boolean?/1)))

(define primitive-value/eqv? (value-procedure (ref (unit)) (function-2 primitive/eqv?/2)))

(define primitive-value/eq? (value-procedure (ref (unit)) (function-2 primitive/eq?/2)))

(define primitive-value/equal? (value-procedure (ref (unit)) (function-2 primitive/equal?/2)))

(define primitive-value/set-car! (value-procedure (ref (unit)) (function-2 primitive/set-car!/2)))

(define primitive-value/set-cdr! (value-procedure (ref (unit)) (function-2 primitive/set-cdr!/2)))

(define primitive-value/caar (value-procedure (ref (unit)) (function-1 primitive/caar/1)))

(define primitive-value/cadr (value-procedure (ref (unit)) (function-1 primitive/cadr/1)))

(define primitive-value/cdar (value-procedure (ref (unit)) (function-1 primitive/cdar/1)))

(define primitive-value/cddr (value-procedure (ref (unit)) (function-1 primitive/cddr/1)))

(define primitive-value/caaar (value-procedure (ref (unit)) (function-1 primitive/caaar/1)))

(define primitive-value/caadr (value-procedure (ref (unit)) (function-1 primitive/caadr/1)))

(define primitive-value/cadar (value-procedure (ref (unit)) (function-1 primitive/cadar/1)))

(define primitive-value/caddr (value-procedure (ref (unit)) (function-1 primitive/caddr/1)))

(define primitive-value/cdaar (value-procedure (ref (unit)) (function-1 primitive/cdaar/1)))

(define primitive-value/cdadr (value-procedure (ref (unit)) (function-1 primitive/cdadr/1)))

(define primitive-value/cddar (value-procedure (ref (unit)) (function-1 primitive/cddar/1)))

(define primitive-value/cdddr (value-procedure (ref (unit)) (function-1 primitive/cdddr/1)))

(define primitive-value/caaaar (value-procedure (ref (unit)) (function-1 primitive/caaaar/1)))

(define primitive-value/caaadr (value-procedure (ref (unit)) (function-1 primitive/caaadr/1)))

(define primitive-value/caadar (value-procedure (ref (unit)) (function-1 primitive/caadar/1)))

(define primitive-value/caaddr (value-procedure (ref (unit)) (function-1 primitive/caaddr/1)))

(define primitive-value/cadaar (value-procedure (ref (unit)) (function-1 primitive/cadaar/1)))

(define primitive-value/cadadr (value-procedure (ref (unit)) (function-1 primitive/cadadr/1)))

(define primitive-value/caddar (value-procedure (ref (unit)) (function-1 primitive/caddar/1)))

(define primitive-value/cadddr (value-procedure (ref (unit)) (function-1 primitive/cadddr/1)))

(define primitive-value/cdaaar (value-procedure (ref (unit)) (function-1 primitive/cdaaar/1)))

(define primitive-value/cdaadr (value-procedure (ref (unit)) (function-1 primitive/cdaadr/1)))

(define primitive-value/cdadar (value-procedure (ref (unit)) (function-1 primitive/cdadar/1)))

(define primitive-value/cdaddr (value-procedure (ref (unit)) (function-1 primitive/cdaddr/1)))

(define primitive-value/cddaar (value-procedure (ref (unit)) (function-1 primitive/cddaar/1)))

(define primitive-value/cddadr (value-procedure (ref (unit)) (function-1 primitive/cddadr/1)))

(define primitive-value/cdddar (value-procedure (ref (unit)) (function-1 primitive/cdddar/1)))

(define primitive-value/cddddr (value-procedure (ref (unit)) (function-1 primitive/cddddr/1)))

(define primitive-value/list? (value-procedure (ref (unit)) (function-1 primitive/list?/1)))

(define primitive-rest/list (lambda (remaining) remaining))

(define primitive-value/list (value-procedure (ref (unit)) (function-rest-0 primitive-rest/list)))

(define primitive-value/length (value-procedure (ref (unit)) (function-1 primitive/length/1)))

(define primitive-rest/append (lambda (remaining) (value-append-many remaining)))

(define primitive-value/append
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/append)))

(define primitive-value/reverse (value-procedure (ref (unit)) (function-1 primitive/reverse/1)))

(define primitive-value/list-ref (value-procedure (ref (unit)) (function-2 primitive/list-ref/2)))

(define primitive-value/memq (value-procedure (ref (unit)) (function-2 primitive/memq/2)))

(define primitive-value/memv (value-procedure (ref (unit)) (function-2 primitive/memv/2)))

(define primitive-value/member (value-procedure (ref (unit)) (function-2 primitive/member/2)))

(define primitive-value/assq (value-procedure (ref (unit)) (function-2 primitive/assq/2)))

(define primitive-value/assv (value-procedure (ref (unit)) (function-2 primitive/assv/2)))

(define primitive-value/assoc (value-procedure (ref (unit)) (function-2 primitive/assoc/2)))

(define primitive-value/symbol? (value-procedure (ref (unit)) (function-1 primitive/symbol?/1)))

(define primitive-value/symbol->string
  (value-procedure (ref (unit)) (function-1 primitive/symbol->string/1)))

(define primitive-value/string->symbol
  (value-procedure (ref (unit)) (function-1 primitive/string->symbol/1)))

(define primitive-value/number? (value-procedure (ref (unit)) (function-1 primitive/number?/1)))

(define primitive-value/complex? (value-procedure (ref (unit)) (function-1 primitive/complex?/1)))

(define primitive-value/real? (value-procedure (ref (unit)) (function-1 primitive/real?/1)))

(define primitive-value/rational? (value-procedure (ref (unit)) (function-1 primitive/rational?/1)))

(define primitive-value/integer? (value-procedure (ref (unit)) (function-1 primitive/integer?/1)))

(define primitive-value/exact? (value-procedure (ref (unit)) (function-1 primitive/exact?/1)))

(define primitive-value/inexact? (value-procedure (ref (unit)) (function-1 primitive/inexact?/1)))

(define primitive-rest/max
  (lambda (a0 remaining)
    (value-number
      (numeric-extreme
        #t
        (value-number-number a0)
        remaining
        (not (number-exact? (value-number-number a0)))))))

(define primitive-value/max (value-procedure (ref (unit)) (function-rest-1 primitive-rest/max)))

(define primitive-rest/min
  (lambda (a0 remaining)
    (value-number
      (numeric-extreme
        #f
        (value-number-number a0)
        remaining
        (not (number-exact? (value-number-number a0)))))))

(define primitive-value/min (value-procedure (ref (unit)) (function-rest-1 primitive-rest/min)))

(define primitive-rest//
  (lambda (a0 remaining)
    (value-number
      (if (value-null? remaining)
        (number-divide (exact-number 1) (value-number-number a0))
        (numeric-fold number-divide (value-number-number a0) remaining)))))

(define primitive-value// (value-procedure (ref (unit)) (function-rest-1 primitive-rest//)))

(define primitive-value/abs (value-procedure (ref (unit)) (function-1 primitive/abs/1)))

(define primitive-rest/gcd
  (lambda (remaining) (value-number (numeric-gcd-fold #f (integer-from-i64 0) remaining #f))))

(define primitive-value/gcd (value-procedure (ref (unit)) (function-rest-0 primitive-rest/gcd)))

(define primitive-rest/lcm
  (lambda (remaining) (value-number (numeric-gcd-fold #t (integer-from-i64 1) remaining #f))))

(define primitive-value/lcm (value-procedure (ref (unit)) (function-rest-0 primitive-rest/lcm)))

(define primitive-value/floor (value-procedure (ref (unit)) (function-1 primitive/floor/1)))

(define primitive-value/ceiling (value-procedure (ref (unit)) (function-1 primitive/ceiling/1)))

(define primitive-value/truncate (value-procedure (ref (unit)) (function-1 primitive/truncate/1)))

(define primitive-value/round (value-procedure (ref (unit)) (function-1 primitive/round/1)))

(define primitive-value/exp (value-procedure (ref (unit)) (function-1 primitive/exp/1)))

(define primitive-rest/log
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/log/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/log/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/log (value-procedure (ref (unit)) (function-rest-1 primitive-rest/log)))

(define primitive-value/sin (value-procedure (ref (unit)) (function-1 primitive/sin/1)))

(define primitive-value/cos (value-procedure (ref (unit)) (function-1 primitive/cos/1)))

(define primitive-value/tan (value-procedure (ref (unit)) (function-1 primitive/tan/1)))

(define primitive-value/asin (value-procedure (ref (unit)) (function-1 primitive/asin/1)))

(define primitive-value/acos (value-procedure (ref (unit)) (function-1 primitive/acos/1)))

(define primitive-rest/atan
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/atan/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/atan/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/atan (value-procedure (ref (unit)) (function-rest-1 primitive-rest/atan)))

(define primitive-value/sqrt (value-procedure (ref (unit)) (function-1 primitive/sqrt/1)))

(define primitive-value/expt (value-procedure (ref (unit)) (function-2 primitive/expt/2)))

(define primitive-value/inexact (value-procedure (ref (unit)) (function-1 primitive/inexact/1)))

(define primitive-value/exact (value-procedure (ref (unit)) (function-1 primitive/exact/1)))

(define primitive-rest/number->string
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/number->string/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/number->string/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/number->string
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/number->string)))

(define primitive-rest/string->number
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/string->number/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/string->number/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/string->number
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/string->number)))

(define primitive-value/char? (value-procedure (ref (unit)) (function-1 primitive/char?/1)))

(define primitive-value/char=? (value-procedure (ref (unit)) (function-2 primitive/char=?/2)))

(define primitive-value/char<? (value-procedure (ref (unit)) (function-2 primitive/char<?/2)))

(define primitive-value/char>? (value-procedure (ref (unit)) (function-2 primitive/char>?/2)))

(define primitive-value/char<=? (value-procedure (ref (unit)) (function-2 primitive/char<=?/2)))

(define primitive-value/char>=? (value-procedure (ref (unit)) (function-2 primitive/char>=?/2)))

(define primitive-value/char-ci=? (value-procedure (ref (unit)) (function-2 primitive/char-ci=?/2)))

(define primitive-value/char-ci<? (value-procedure (ref (unit)) (function-2 primitive/char-ci<?/2)))

(define primitive-value/char-ci>? (value-procedure (ref (unit)) (function-2 primitive/char-ci>?/2)))

(define primitive-value/char-ci<=?
  (value-procedure (ref (unit)) (function-2 primitive/char-ci<=?/2)))

(define primitive-value/char-ci>=?
  (value-procedure (ref (unit)) (function-2 primitive/char-ci>=?/2)))

(define primitive-value/char-alphabetic?
  (value-procedure (ref (unit)) (function-1 primitive/char-alphabetic?/1)))

(define primitive-value/char-numeric?
  (value-procedure (ref (unit)) (function-1 primitive/char-numeric?/1)))

(define primitive-value/char-whitespace?
  (value-procedure (ref (unit)) (function-1 primitive/char-whitespace?/1)))

(define primitive-value/char-lower-case?
  (value-procedure (ref (unit)) (function-1 primitive/char-lower-case?/1)))

(define primitive-value/char->integer
  (value-procedure (ref (unit)) (function-1 primitive/char->integer/1)))

(define primitive-value/integer->char
  (value-procedure (ref (unit)) (function-1 primitive/integer->char/1)))

(define primitive-value/char-upcase
  (value-procedure (ref (unit)) (function-1 primitive/char-upcase/1)))

(define primitive-value/char-downcase
  (value-procedure (ref (unit)) (function-1 primitive/char-downcase/1)))

(define primitive-value/string? (value-procedure (ref (unit)) (function-1 primitive/string?/1)))

(define primitive-rest/make-string
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/make-string/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/make-string/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/make-string
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/make-string)))

(define primitive-rest/string
  (lambda (remaining) (value-string (list->string (value-characters remaining)))))

(define primitive-value/string
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/string)))

(define primitive-value/string-length
  (value-procedure (ref (unit)) (function-1 primitive/string-length/1)))

(define primitive-value/string-ref
  (value-procedure (ref (unit)) (function-2 primitive/string-ref/2)))

(define primitive-value/string-set!
  (value-procedure (ref (unit)) (function-3 primitive/string-set!/3)))

(define primitive-value/string=? (value-procedure (ref (unit)) (function-2 primitive/string=?/2)))

(define primitive-value/string<? (value-procedure (ref (unit)) (function-2 primitive/string<?/2)))

(define primitive-value/string>? (value-procedure (ref (unit)) (function-2 primitive/string>?/2)))

(define primitive-value/string<=? (value-procedure (ref (unit)) (function-2 primitive/string<=?/2)))

(define primitive-value/string>=? (value-procedure (ref (unit)) (function-2 primitive/string>=?/2)))

(define primitive-value/string-ci=?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci=?/2)))

(define primitive-value/string-ci<?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci<?/2)))

(define primitive-value/string-ci>?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci>?/2)))

(define primitive-value/string-ci<=?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci<=?/2)))

(define primitive-value/string-ci>=?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci>=?/2)))

(define primitive-value/substring (value-procedure (ref (unit)) (function-3 primitive/substring/3)))

(define primitive-rest/string-append (lambda (remaining) (value-join-strings remaining)))

(define primitive-value/string-append
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/string-append)))

(define primitive-value/vector? (value-procedure (ref (unit)) (function-1 primitive/vector?/1)))

(define primitive-rest/make-vector
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/make-vector/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/make-vector/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/make-vector
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/make-vector)))

(define primitive-rest/vector
  (lambda (remaining) (value-vector (list->vector (values->native remaining)))))

(define primitive-value/vector
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/vector)))

(define primitive-value/vector-length
  (value-procedure (ref (unit)) (function-1 primitive/vector-length/1)))

(define primitive-value/vector-ref
  (value-procedure (ref (unit)) (function-2 primitive/vector-ref/2)))

(define primitive-value/vector-set!
  (value-procedure (ref (unit)) (function-3 primitive/vector-set!/3)))

(define primitive-value/procedure?
  (value-procedure (ref (unit)) (function-1 primitive/procedure?/1)))

(define primitive-rest/apply
  (lambda (a0 a1 remaining) (invoke-list a0 (value-apply-arguments (value-cons a1 remaining)))))

(define primitive-value/apply (value-procedure (ref (unit)) (function-rest-2 primitive-rest/apply)))

(define primitive-rest/map (lambda (a0 a1 remaining) (value-map-many a0 (value-cons a1 remaining))))

(define primitive-value/map (value-procedure (ref (unit)) (function-rest-2 primitive-rest/map)))

(define primitive-rest/for-each
  (lambda (a0 a1 remaining) (value-for-each-many a0 (value-cons a1 remaining))))

(define primitive-value/for-each
  (value-procedure (ref (unit)) (function-rest-2 primitive-rest/for-each)))

(define primitive-value/call-with-input-file
  (value-procedure (ref (unit)) (function-2 primitive/call-with-input-file/2)))

(define primitive-value/call-with-output-file
  (value-procedure (ref (unit)) (function-2 primitive/call-with-output-file/2)))

(define primitive-value/input-port?
  (value-procedure (ref (unit)) (function-1 primitive/input-port?/1)))

(define primitive-value/output-port?
  (value-procedure (ref (unit)) (function-1 primitive/output-port?/1)))

(define primitive-value/current-input-port
  (value-procedure (ref (unit)) (function-0 primitive/current-input-port/0)))

(define primitive-value/current-output-port
  (value-procedure (ref (unit)) (function-0 primitive/current-output-port/0)))

(define primitive-value/open-input-file
  (value-procedure (ref (unit)) (function-1 primitive/open-input-file/1)))

(define primitive-value/open-output-file
  (value-procedure (ref (unit)) (function-1 primitive/open-output-file/1)))

(define primitive-value/close-input-port
  (value-procedure (ref (unit)) (function-1 primitive/close-input-port/1)))

(define primitive-value/close-output-port
  (value-procedure (ref (unit)) (function-1 primitive/close-output-port/1)))

(define primitive-value/eof-object?
  (value-procedure (ref (unit)) (function-1 primitive/eof-object?/1)))

(define primitive-rest/read
  (lambda (remaining)
    (if (value-null? remaining)
      (primitive/read/0)
      (if (value-null? (value-cdr remaining))
        (primitive/read/1 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/read (value-procedure (ref (unit)) (function-rest-0 primitive-rest/read)))

(define primitive-rest/read-char
  (lambda (remaining)
    (if (value-null? remaining)
      (primitive/read-char/0)
      (if (value-null? (value-cdr remaining))
        (primitive/read-char/1 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/read-char
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/read-char)))

(define primitive-rest/peek-char
  (lambda (remaining)
    (if (value-null? remaining)
      (primitive/peek-char/0)
      (if (value-null? (value-cdr remaining))
        (primitive/peek-char/1 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/peek-char
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/peek-char)))

(define primitive-rest/write
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/write/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/write/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/write (value-procedure (ref (unit)) (function-rest-1 primitive-rest/write)))

(define primitive-rest/display
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/display/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/display/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/display
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/display)))

(define primitive-rest/newline
  (lambda (remaining)
    (if (value-null? remaining)
      (primitive/newline/0)
      (if (value-null? (value-cdr remaining))
        (primitive/newline/1 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/newline
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/newline)))

(define primitive-rest/write-char
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/write-char/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/write-char/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/write-char
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/write-char)))

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

(define standard-input-value (value-input (ref (unit)) (current-input-port)))

(define invoke-list
  (lambda (procedure arguments)
    (let ((matched-value.28 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.28)
          (let ((body (function-0-body matched-value.28)))
            (if (value-null? arguments) (body) (datum-fail "procedure argument count mismatch"))))
        ((is-function-1 matched-value.28)
          (let ((body (function-1-body matched-value.28)))
            (if (value-null? (value-cdr arguments))
              (body (value-car arguments))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-2 matched-value.28)
          (let ((body (function-2-body matched-value.28)))
            (if (value-null? (value-cdr (value-cdr arguments)))
              (body (value-car arguments) (value-car (value-cdr arguments)))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-3 matched-value.28)
          (let ((body (function-3-body matched-value.28)))
            (if (value-null? (value-cdr (value-cdr (value-cdr arguments))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-4 matched-value.28)
          (let ((body (function-4-body matched-value.28)))
            (if (value-null? (value-cdr (value-cdr (value-cdr (value-cdr arguments)))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments)))
                (value-car (value-cdr (value-cdr (value-cdr arguments)))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-rest-0 matched-value.28)
          (let ((body (function-rest-0-body matched-value.28))) (body arguments)))
        ((is-function-rest-1 matched-value.28)
          (let ((body (function-rest-1-body matched-value.28)))
            (body (value-car arguments) (value-cdr arguments))))
        ((is-function-rest-2 matched-value.28)
          (let ((body (function-rest-2-body matched-value.28)))
            (body
              (value-car arguments)
              (value-car (value-cdr arguments))
              (value-cdr (value-cdr arguments)))))
        ((is-function-rest-3 matched-value.28)
          (let ((body (function-rest-3-body matched-value.28)))
            (body
              (value-car arguments)
              (value-car (value-cdr arguments))
              (value-car (value-cdr (value-cdr arguments)))
              (value-cdr (value-cdr (value-cdr arguments))))))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            28
            (debug-source-stack)
            (if (host:record? matched-value.28)
              (host:record-type-name (host:record-rtd matched-value.28))
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
    (let ((matched-value.30 result))
      (cond
        ((is-not-a-number matched-value.30) (let () (value-boolean #f)))
        ((is-parsed-number matched-value.30)
          (let ((number (parsed-number-value matched-value.30))) (value-number number)))
        ((is-number-error matched-value.30)
          (let ((message (number-error-text matched-value.30))) (datum-fail message)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            30
            (debug-source-stack)
            (if (host:record? matched-value.30)
              (host:record-type-name (host:record-rtd matched-value.30))
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
    (let ((matched-value.32 source))
      (cond
        ((is-value-null matched-value.32) (let () (datum-null)))
        ((is-value-boolean matched-value.32)
          (let ((x (value-boolean-boolean matched-value.32))) (datum-boolean x)))
        ((is-value-character matched-value.32)
          (let ((x (value-character-character matched-value.32))) (datum-character x)))
        ((is-value-string matched-value.32)
          (let ((x (value-string-string matched-value.32))) (datum-string x)))
        ((is-value-symbol matched-value.32)
          (let ((x (value-symbol-symbol matched-value.32))) (datum-symbol x)))
        ((is-value-number matched-value.32)
          (let ((x (value-number-number matched-value.32))) (datum-number x)))
        ((is-value-bytevector matched-value.32)
          (let ((x (value-bytevector-bytes matched-value.32))) (datum-bytevector x)))
        ((is-value-pair matched-value.32)
          (let ((first (value-pair-first matched-value.32)) (rest (value-pair-rest matched-value.32)))
            (outward-mutable source seen)))
        ((is-value-vector matched-value.32)
          (let ((vector (value-vector-vector matched-value.32))) (outward-mutable source seen)))
        ((is-value-input matched-value.32)
          (let ((identity (value-input-identity matched-value.32)) (port (value-input-port matched-value.32)))
            (datum-symbol (string->symbol "#<input-port>"))))
        ((is-value-output matched-value.32)
          (let ((port (value-output-port matched-value.32)))
            (datum-symbol (string->symbol "#<output-port>"))))
        ((is-value-procedure matched-value.32)
          (let ((identity (value-procedure-identity matched-value.32)) (procedure (value-procedure-procedure matched-value.32)))
            (datum-symbol (string->symbol "#<procedure>"))))
        ((is-value-eof matched-value.32) (let () (datum-symbol (string->symbol "#<eof>"))))
        ((is-value-unspecified matched-value.32)
          (let () (datum-symbol (string->symbol "#<unspecified>"))))
        ((is-value-uninitialized matched-value.32)
          (let () (datum-fail "uninitialized value is not external data")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            32
            (debug-source-stack)
            (if (host:record? matched-value.32)
              (host:record-type-name (host:record-rtd matched-value.32))
              "nonrecord")))))))

(define outward-mutable
  (lambda (source seen)
    (let ((matched-value.34 (outward-find source (ref-get seen))))
      (cond
        ((is-outward-found matched-value.34)
          (let ((result (outward-found/value matched-value.34))) result))
        ((is-outward-absent matched-value.34) (let () (outward-node source seen)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            34
            (debug-source-stack)
            (if (host:record? matched-value.34)
              (host:record-type-name (host:record-rtd matched-value.34))
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

(define literal
  (value-cons
    (value-symbol (string->symbol "quote"))
    (value-cons
      (value-symbol (string->symbol "quasiquote"))
      (value-cons
        (value-symbol (string->symbol "unquote"))
        (value-cons
          (value-symbol (string->symbol "unquote-splicing"))
          (value-cons
            (value-symbol (string->symbol "lambda"))
            (value-cons
              (value-symbol (string->symbol "if"))
              (value-cons
                (value-symbol (string->symbol "set!"))
                (value-cons
                  (value-symbol (string->symbol "cond"))
                  (value-cons
                    (value-symbol (string->symbol "=>"))
                    (value-cons
                      (value-symbol (string->symbol "else"))
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
                                    (value-symbol (string->symbol "begin"))
                                    (value-cons
                                      (value-symbol (string->symbol "do"))
                                      (value-cons
                                        (value-symbol (string->symbol "define"))
                                        (value-cons
                                          (value-symbol (string->symbol "define-macro"))
                                          (value-null))))))))))))))))))))))

(define literal.1 (value-string "Identifier expected"))

(define literal.2 (value-string "Variable name can not be a syntactic keyword"))

(define literal.3 (value-string "Ill-constructed form"))

(define literal.4 (value-string "Ill-placed 'unquote-splicing'"))

(define literal.5 (value-symbol (string->symbol "unquote-splicing")))

(define literal.6 (value-symbol (string->symbol "unquote")))

(define literal.7 (value-symbol (string->symbol "quasiquote")))

(define literal.8 (value-symbol (string->symbol "unquote-splicing")))

(define literal.9 (value-string "Ill-placed 'unquote'"))

(define literal.10 (value-string "Ill-placed 'unquote-splicing'"))

(define literal.11 (value-string "Body must contain at least one evaluable expression"))

(define literal.12 (value-symbol (string->symbol "define-macro")))

(define literal.13 (value-symbol (string->symbol "define")))

(define literal.14 (value-symbol (string->symbol "begin")))

(define literal.15 (value-string "Identifier expected"))

(define literal.16 (value-symbol (string->symbol "lambda")))

(define literal.17 (value-symbol (string->symbol "=>")))

(define literal.18 (value-symbol (string->symbol "else")))

(define literal.19 (value-symbol (string->symbol "else")))

(define literal.20 (value-symbol (string->symbol "lambda")))

(define literal.21 (value-symbol (string->symbol "lambda")))

(define literal.22 (value-symbol (string->symbol "letrec")))

(define literal.23 (value-symbol (string->symbol "let")))

(define literal.24 (value-symbol (string->symbol "let*")))

(define literal.25 (value-cons (value-boolean #f) (value-null)))

(define literal.26 (value-cons (value-number (exact-number 1)) (value-number (exact-number 1))))

(define literal.27 (value-cons (value-number (exact-number 0)) (value-number (exact-number 1))))

(define literal.28 (value-symbol (string->symbol "lambda")))

(define literal.29 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.30 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.31 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.32 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.33 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.34 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.35 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.36 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.37 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.38 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.39 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.40 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.41 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.42 (value-cons (value-number (exact-number -1)) (value-null)))

(define literal.43 (value-cons (value-number (exact-number -2)) (value-null)))

(define literal.44 (value-cons (value-boolean #t) (value-null)))

(define literal.45 (value-cons (value-boolean #f) (value-null)))

(define literal.46 (value-cons (value-null) (value-null)))

(define literal.47 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.48 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.49 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.50 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.51 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.52 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.53 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.54 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.55 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.56 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.57 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.58 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.59 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.60 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.61 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.62 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.63 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.64 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.65 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.66 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.67 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.68 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.69 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.70 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.71 (value-cons (value-number (exact-number 3)) (value-null)))

(define literal.72 (value-cons (value-number (exact-number 2)) (value-null)))

(define literal.73 (value-cons (value-number (exact-number 1)) (value-null)))

(define literal.74 (value-cons (value-number (exact-number 0)) (value-null)))

(define literal.75 (value-symbol (string->symbol "define-macro")))

(define literal.76 (value-symbol (string->symbol "define")))

(define literal.77 (value-symbol (string->symbol "do")))

(define literal.78 (value-symbol (string->symbol "begin")))

(define literal.79 (value-symbol (string->symbol "letrec")))

(define literal.80 (value-symbol (string->symbol "let*")))

(define literal.81 (value-symbol (string->symbol "let")))

(define literal.82 (value-symbol (string->symbol "case")))

(define literal.83 (value-symbol (string->symbol "or")))

(define literal.84 (value-symbol (string->symbol "and")))

(define literal.85 (value-symbol (string->symbol "cond")))

(define literal.86 (value-symbol (string->symbol "if")))

(define literal.87 (value-symbol (string->symbol "lambda")))

(define literal.88 (value-symbol (string->symbol "set!")))

(define literal.89 (value-symbol (string->symbol "unquote-splicing")))

(define literal.90 (value-symbol (string->symbol "unquote")))

(define literal.91 (value-symbol (string->symbol "quasiquote")))

(define literal.92 (value-symbol (string->symbol "quote")))

(define literal.93 (value-symbol (string->symbol "not")))

(define literal.94 (value-symbol (string->symbol "boolean?")))

(define literal.95 (value-symbol (string->symbol "eqv?")))

(define literal.96 (value-symbol (string->symbol "eq?")))

(define literal.97 (value-symbol (string->symbol "equal?")))

(define literal.98 (value-symbol (string->symbol "pair?")))

(define literal.99 (value-symbol (string->symbol "cons")))

(define literal.100 (value-symbol (string->symbol "car")))

(define literal.101 (value-symbol (string->symbol "cdr")))

(define literal.102 (value-symbol (string->symbol "set-car!")))

(define literal.103 (value-symbol (string->symbol "set-cdr!")))

(define literal.104 (value-symbol (string->symbol "caar")))

(define literal.105 (value-symbol (string->symbol "cadr")))

(define literal.106 (value-symbol (string->symbol "cdar")))

(define literal.107 (value-symbol (string->symbol "cddr")))

(define literal.108 (value-symbol (string->symbol "caaar")))

(define literal.109 (value-symbol (string->symbol "caadr")))

(define literal.110 (value-symbol (string->symbol "cadar")))

(define literal.111 (value-symbol (string->symbol "caddr")))

(define literal.112 (value-symbol (string->symbol "cdaar")))

(define literal.113 (value-symbol (string->symbol "cdadr")))

(define literal.114 (value-symbol (string->symbol "cddar")))

(define literal.115 (value-symbol (string->symbol "cdddr")))

(define literal.116 (value-symbol (string->symbol "caaaar")))

(define literal.117 (value-symbol (string->symbol "caaadr")))

(define literal.118 (value-symbol (string->symbol "caadar")))

(define literal.119 (value-symbol (string->symbol "caaddr")))

(define literal.120 (value-symbol (string->symbol "cadaar")))

(define literal.121 (value-symbol (string->symbol "cadadr")))

(define literal.122 (value-symbol (string->symbol "caddar")))

(define literal.123 (value-symbol (string->symbol "cadddr")))

(define literal.124 (value-symbol (string->symbol "cdaaar")))

(define literal.125 (value-symbol (string->symbol "cdaadr")))

(define literal.126 (value-symbol (string->symbol "cdadar")))

(define literal.127 (value-symbol (string->symbol "cdaddr")))

(define literal.128 (value-symbol (string->symbol "cddaar")))

(define literal.129 (value-symbol (string->symbol "cddadr")))

(define literal.130 (value-symbol (string->symbol "cdddar")))

(define literal.131 (value-symbol (string->symbol "cddddr")))

(define literal.132 (value-symbol (string->symbol "null?")))

(define literal.133 (value-symbol (string->symbol "list?")))

(define literal.134 (value-symbol (string->symbol "list")))

(define literal.135 (value-symbol (string->symbol "length")))

(define literal.136 (value-symbol (string->symbol "append")))

(define literal.137 (value-symbol (string->symbol "reverse")))

(define literal.138 (value-symbol (string->symbol "list-ref")))

(define literal.139 (value-symbol (string->symbol "memq")))

(define literal.140 (value-symbol (string->symbol "memv")))

(define literal.141 (value-symbol (string->symbol "member")))

(define literal.142 (value-symbol (string->symbol "assq")))

(define literal.143 (value-symbol (string->symbol "assv")))

(define literal.144 (value-symbol (string->symbol "assoc")))

(define literal.145 (value-symbol (string->symbol "symbol?")))

(define literal.146 (value-symbol (string->symbol "symbol->string")))

(define literal.147 (value-symbol (string->symbol "string->symbol")))

(define literal.148 (value-symbol (string->symbol "number?")))

(define literal.149 (value-symbol (string->symbol "complex?")))

(define literal.150 (value-symbol (string->symbol "real?")))

(define literal.151 (value-symbol (string->symbol "rational?")))

(define literal.152 (value-symbol (string->symbol "integer?")))

(define literal.153 (value-symbol (string->symbol "exact?")))

(define literal.154 (value-symbol (string->symbol "inexact?")))

(define literal.155 (value-symbol (string->symbol "max")))

(define literal.156 (value-symbol (string->symbol "min")))

(define literal.157 (value-symbol (string->symbol "/")))

(define literal.158 (value-symbol (string->symbol "abs")))

(define literal.159 (value-symbol (string->symbol "gcd")))

(define literal.160 (value-symbol (string->symbol "lcm")))

(define literal.161 (value-symbol (string->symbol "floor")))

(define literal.162 (value-symbol (string->symbol "ceiling")))

(define literal.163 (value-symbol (string->symbol "truncate")))

(define literal.164 (value-symbol (string->symbol "round")))

(define literal.165 (value-symbol (string->symbol "exp")))

(define literal.166 (value-symbol (string->symbol "log")))

(define literal.167 (value-symbol (string->symbol "sin")))

(define literal.168 (value-symbol (string->symbol "cos")))

(define literal.169 (value-symbol (string->symbol "tan")))

(define literal.170 (value-symbol (string->symbol "asin")))

(define literal.171 (value-symbol (string->symbol "acos")))

(define literal.172 (value-symbol (string->symbol "atan")))

(define literal.173 (value-symbol (string->symbol "sqrt")))

(define literal.174 (value-symbol (string->symbol "expt")))

(define literal.175 (value-symbol (string->symbol "exact->inexact")))

(define literal.176 (value-symbol (string->symbol "inexact->exact")))

(define literal.177 (value-symbol (string->symbol "number->string")))

(define literal.178 (value-symbol (string->symbol "string->number")))

(define literal.179 (value-symbol (string->symbol "char?")))

(define literal.180 (value-symbol (string->symbol "char=?")))

(define literal.181 (value-symbol (string->symbol "char<?")))

(define literal.182 (value-symbol (string->symbol "char>?")))

(define literal.183 (value-symbol (string->symbol "char<=?")))

(define literal.184 (value-symbol (string->symbol "char>=?")))

(define literal.185 (value-symbol (string->symbol "char-ci=?")))

(define literal.186 (value-symbol (string->symbol "char-ci<?")))

(define literal.187 (value-symbol (string->symbol "char-ci>?")))

(define literal.188 (value-symbol (string->symbol "char-ci<=?")))

(define literal.189 (value-symbol (string->symbol "char-ci>=?")))

(define literal.190 (value-symbol (string->symbol "char-alphabetic?")))

(define literal.191 (value-symbol (string->symbol "char-numeric?")))

(define literal.192 (value-symbol (string->symbol "char-whitespace?")))

(define literal.193 (value-symbol (string->symbol "char-lower-case?")))

(define literal.194 (value-symbol (string->symbol "char->integer")))

(define literal.195 (value-symbol (string->symbol "integer->char")))

(define literal.196 (value-symbol (string->symbol "char-upcase")))

(define literal.197 (value-symbol (string->symbol "char-downcase")))

(define literal.198 (value-symbol (string->symbol "string?")))

(define literal.199 (value-symbol (string->symbol "make-string")))

(define literal.200 (value-symbol (string->symbol "string")))

(define literal.201 (value-symbol (string->symbol "string-length")))

(define literal.202 (value-symbol (string->symbol "string-ref")))

(define literal.203 (value-symbol (string->symbol "string-set!")))

(define literal.204 (value-symbol (string->symbol "string=?")))

(define literal.205 (value-symbol (string->symbol "string<?")))

(define literal.206 (value-symbol (string->symbol "string>?")))

(define literal.207 (value-symbol (string->symbol "string<=?")))

(define literal.208 (value-symbol (string->symbol "string>=?")))

(define literal.209 (value-symbol (string->symbol "string-ci=?")))

(define literal.210 (value-symbol (string->symbol "string-ci<?")))

(define literal.211 (value-symbol (string->symbol "string-ci>?")))

(define literal.212 (value-symbol (string->symbol "string-ci<=?")))

(define literal.213 (value-symbol (string->symbol "string-ci>=?")))

(define literal.214 (value-symbol (string->symbol "substring")))

(define literal.215 (value-symbol (string->symbol "string-append")))

(define literal.216 (value-symbol (string->symbol "vector?")))

(define literal.217 (value-symbol (string->symbol "make-vector")))

(define literal.218 (value-symbol (string->symbol "vector")))

(define literal.219 (value-symbol (string->symbol "vector-length")))

(define literal.220 (value-symbol (string->symbol "vector-ref")))

(define literal.221 (value-symbol (string->symbol "vector-set!")))

(define literal.222 (value-symbol (string->symbol "procedure?")))

(define literal.223 (value-symbol (string->symbol "apply")))

(define literal.224 (value-symbol (string->symbol "map")))

(define literal.225 (value-symbol (string->symbol "for-each")))

(define literal.226 (value-symbol (string->symbol "call-with-input-file")))

(define literal.227 (value-symbol (string->symbol "call-with-output-file")))

(define literal.228 (value-symbol (string->symbol "input-port?")))

(define literal.229 (value-symbol (string->symbol "output-port?")))

(define literal.230 (value-symbol (string->symbol "current-input-port")))

(define literal.231 (value-symbol (string->symbol "current-output-port")))

(define literal.232 (value-symbol (string->symbol "open-input-file")))

(define literal.233 (value-symbol (string->symbol "open-output-file")))

(define literal.234 (value-symbol (string->symbol "close-input-port")))

(define literal.235 (value-symbol (string->symbol "close-output-port")))

(define literal.236 (value-symbol (string->symbol "eof-object?")))

(define literal.237 (value-symbol (string->symbol "read")))

(define literal.238 (value-symbol (string->symbol "read-char")))

(define literal.239 (value-symbol (string->symbol "peek-char")))

(define literal.240 (value-symbol (string->symbol "write")))

(define literal.241 (value-symbol (string->symbol "display")))

(define literal.242 (value-symbol (string->symbol "newline")))

(define literal.243 (value-symbol (string->symbol "write-char")))

(define source/scheme-eval (ref (value-uninitialized)))

(define body/source/scheme-eval
  (lambda (source/expr)
    ((lambda (source/code) (invoke-1 source/code (value-boolean #f)))
      (body/source/scheme-comp source/expr (binding-value source/scheme-global-environment)))))

(ref-set! source/scheme-eval (value-procedure (ref (unit)) (function-1 body/source/scheme-eval)))

(define source/scheme-global-environment (ref (value-uninitialized)))

(ref-set! source/scheme-global-environment (primitive/cons/2 (value-null) (value-null)))

(define source/scheme-add-macro (ref (value-uninitialized)))

(define body/source/scheme-add-macro
  (lambda (source/name source/proc)
    (begin
      (primitive/set-cdr!/2
        (binding-value source/scheme-global-environment)
        (primitive/cons/2
          (primitive/cons/2 source/name source/proc)
          (primitive/cdr/1 (binding-value source/scheme-global-environment))))
      source/name)))

(ref-set!
  source/scheme-add-macro
  (value-procedure (ref (unit)) (function-2 body/source/scheme-add-macro)))

(define source/scheme-error (ref (value-uninitialized)))

(define body/source/scheme-error
  (lambda (source/msg source/args) (primitive/error/3 (value-boolean #f) source/msg source/args)))

(ref-set!
  source/scheme-error
  (value-procedure (ref (unit)) (function-rest-1 body/source/scheme-error)))

(define source/lst->vector (ref (value-uninitialized)))

(define body/source/lst->vector
  (lambda (source/l)
    ((lambda (source/n) ((lambda (source/v) ((lambda () (invoke-2 ((lambda () (let ((source/loop #f) (body/source/loop #f)) (set! source/loop (ref (value-uninitialized))) (set! body/source/loop (lambda (source/l.1 source/i) (if (value-truth? (primitive/pair?/1 source/l.1)) (begin (primitive/vector-set!/3 source/v source/i (primitive/car/1 source/l.1)) (body/source/loop (primitive/cdr/1 source/l.1) (primitive/+/2 source/i (value-number (exact-number 1))))) source/v))) (ref-set! source/loop (value-procedure (ref (unit)) (function-2 body/source/loop))) (binding-value source/loop)))) source/l (value-number (exact-number 0)))))) (primitive/make-vector/1 source/n)))
      (primitive/length/1 source/l))))

(ref-set! source/lst->vector (value-procedure (ref (unit)) (function-1 body/source/lst->vector)))

(define source/vector->lst (ref (value-uninitialized)))

(define body/source/vector->lst
  (lambda (source/v.1)
    (invoke-2
      ((lambda () (let ((source/loop.1 #f) (body/source/loop.1 #f)) (set! source/loop.1 (ref (value-uninitialized))) (set! body/source/loop.1 (lambda (source/l.2 source/i.1) (if (value-truth? (primitive/</2 source/i.1 (value-number (exact-number 0)))) source/l.2 (body/source/loop.1 (primitive/cons/2 (primitive/vector-ref/2 source/v.1 source/i.1) source/l.2) (primitive/-/2 source/i.1 (value-number (exact-number 1))))))) (ref-set! source/loop.1 (value-procedure (ref (unit)) (function-2 body/source/loop.1))) (binding-value source/loop.1)))
)
      (value-null)
      (primitive/-/2 (primitive/vector-length/1 source/v.1) (value-number (exact-number 1))))))

(ref-set! source/vector->lst (value-procedure (ref (unit)) (function-1 body/source/vector->lst)))

(define source/scheme-syntactic-keywords (ref (value-uninitialized)))

(ref-set! source/scheme-syntactic-keywords literal)

(define source/push-frame (ref (value-uninitialized)))

(define body/source/push-frame
  (lambda (source/frame source/env)
    (if (value-truth? (primitive/null?/1 source/frame))
      source/env
      (primitive/cons/2
        (primitive/cons/2 (primitive/car/1 source/env) source/frame)
        (primitive/cdr/1 source/env)))))

(ref-set! source/push-frame (value-procedure (ref (unit)) (function-2 body/source/push-frame)))

(define source/lookup-var (ref (value-uninitialized)))

(define body/source/lookup-var
  (lambda (source/name.1 source/env.1)
    (invoke-2
      ((lambda () (let ((source/loop1 #f) (body/source/loop1 #f)) (set! source/loop1 (ref (value-uninitialized))) (set! body/source/loop1 (lambda (source/chain source/up) (if (value-truth? (primitive/null?/1 source/chain)) source/name.1 (invoke-4 ((lambda () (let ((source/loop2 #f) (body/source/loop2 #f)) (set! source/loop2 (ref (value-uninitialized))) (set! body/source/loop2 (lambda (source/chain.1 source/up.1 source/frame.1 source/over) (if (value-truth? (primitive/null?/1 source/frame.1)) (body/source/loop1 (primitive/car/1 source/chain.1) (primitive/+/2 source/up.1 (value-number (exact-number 1)))) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/frame.1) source/name.1)) (primitive/cons/2 source/up.1 source/over) (body/source/loop2 source/chain.1 source/up.1 (primitive/cdr/1 source/frame.1) (primitive/+/2 source/over (value-number (exact-number 1)))))))) (ref-set! source/loop2 (value-procedure (ref (unit)) (function-4 body/source/loop2))) (binding-value source/loop2)))) source/chain source/up (primitive/cdr/1 source/chain) (value-number (exact-number 1)))))) (ref-set! source/loop1 (value-procedure (ref (unit)) (function-2 body/source/loop1))) (binding-value source/loop1)))
)
      (primitive/car/1 source/env.1)
      (value-number (exact-number 0)))))

(ref-set! source/lookup-var (value-procedure (ref (unit)) (function-2 body/source/lookup-var)))

(define source/macro? (ref (value-uninitialized)))

(define body/source/macro?
  (lambda (source/name.2 source/env.2)
    (primitive/assq/2 source/name.2 (primitive/cdr/1 source/env.2))))

(ref-set! source/macro? (value-procedure (ref (unit)) (function-2 body/source/macro?)))

(define source/push-macro (ref (value-uninitialized)))

(define body/source/push-macro
  (lambda (source/name.3 source/proc.1 source/env.3)
    (primitive/cons/2
      (primitive/car/1 source/env.3)
      (primitive/cons/2
        (primitive/cons/2 source/name.3 source/proc.1)
        (primitive/cdr/1 source/env.3)))))

(ref-set! source/push-macro (value-procedure (ref (unit)) (function-3 body/source/push-macro)))

(define source/lookup-macro (ref (value-uninitialized)))

(define body/source/lookup-macro
  (lambda (source/name.4 source/env.4)
    (primitive/cdr/1 (primitive/assq/2 source/name.4 (primitive/cdr/1 source/env.4)))))

(ref-set! source/lookup-macro (value-procedure (ref (unit)) (function-2 body/source/lookup-macro)))

(define source/variable (ref (value-uninitialized)))

(define body/source/variable
  (lambda (source/x)
    (begin
      (if (value-truth? (primitive/symbol?/1 source/x))
        (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))
        (body/source/scheme-error literal.1 (value-cons source/x (value-null))))
      (if (value-truth? (primitive/memq/2 source/x (binding-value source/scheme-syntactic-keywords)))
        (body/source/scheme-error literal.2 (value-cons source/x (value-null)))
        (value-unspecified)))))

(ref-set! source/variable (value-procedure (ref (unit)) (function-1 body/source/variable)))

(define source/shape (ref (value-uninitialized)))

(define body/source/shape
  (lambda (source/form source/n.1)
    (invoke-3
      ((lambda () (let ((source/loop.2 #f) (body/source/loop.2 #f)) (set! source/loop.2 (ref (value-uninitialized))) (set! body/source/loop.2 (lambda (source/form.1 source/n.2 source/l.3) ((lambda (source/value) (if (value-truth? source/value) source/value (if (value-truth? (primitive/pair?/1 source/l.3)) (body/source/loop.2 source/form.1 (primitive/-/2 source/n.2 (value-number (exact-number 1))) (primitive/cdr/1 source/l.3)) (body/source/scheme-error literal.3 (value-cons source/form.1 (value-null)))))) (primitive/<=/2 source/n.2 (value-number (exact-number 0)))))) (ref-set! source/loop.2 (value-procedure (ref (unit)) (function-3 body/source/loop.2))) (binding-value source/loop.2)))
)
      source/form
      source/n.1
      source/form)))

(ref-set! source/shape (value-procedure (ref (unit)) (function-2 body/source/shape)))

(define source/macro-expand (ref (value-uninitialized)))

(define body/source/macro-expand
  (lambda (source/expr.1 source/env.5)
    (primitive/apply/2
      (body/source/lookup-macro (primitive/car/1 source/expr.1) source/env.5)
      (primitive/cdr/1 source/expr.1))))

(ref-set! source/macro-expand (value-procedure (ref (unit)) (function-2 body/source/macro-expand)))

(define source/comp-var (ref (value-uninitialized)))

(define body/source/comp-var
  (lambda (source/expr.2 source/env.6)
    (begin
      (body/source/variable source/expr.2)
      (body/source/gen-var-ref (body/source/lookup-var source/expr.2 source/env.6)))))

(ref-set! source/comp-var (value-procedure (ref (unit)) (function-2 body/source/comp-var)))

(define source/comp-self-eval (ref (value-uninitialized)))

(define body/source/comp-self-eval
  (lambda (source/expr.3 source/env.7) (body/source/gen-cst source/expr.3)))

(ref-set!
  source/comp-self-eval
  (value-procedure (ref (unit)) (function-2 body/source/comp-self-eval)))

(define source/comp-quote (ref (value-uninitialized)))

(define body/source/comp-quote
  (lambda (source/expr.4 source/env.8)
    (begin
      (body/source/shape source/expr.4 (value-number (exact-number 2)))
      (body/source/gen-cst (primitive/cadr/1 source/expr.4)))))

(ref-set! source/comp-quote (value-procedure (ref (unit)) (function-2 body/source/comp-quote)))

(define source/comp-quasiquote (ref (value-uninitialized)))

(define body/source/comp-quasiquote
  (lambda (source/expr.5 source/env.9)
    (body/source/comp-quasiquotation
      (primitive/cadr/1 source/expr.5)
      (value-number (exact-number 1))
      source/env.9)))

(ref-set!
  source/comp-quasiquote
  (value-procedure (ref (unit)) (function-2 body/source/comp-quasiquote)))

(define source/comp-quasiquotation (ref (value-uninitialized)))

(define body/source/comp-quasiquotation
  (lambda (source/form.2 source/level source/env.10)
    (if (value-truth? (primitive/=/2 source/level (value-number (exact-number 0))))
      (body/source/scheme-comp source/form.2 source/env.10)
      (if (value-truth? (primitive/pair?/1 source/form.2))
        (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/form.2) literal.7))
          (body/source/comp-quasiquotation-list
            source/form.2
            (primitive/+/2 source/level (value-number (exact-number 1)))
            source/env.10)
          (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/form.2) literal.6))
            (if (value-truth? (primitive/=/2 source/level (value-number (exact-number 1))))
              (body/source/scheme-comp (primitive/cadr/1 source/form.2) source/env.10)
              (body/source/comp-quasiquotation-list
                source/form.2
                (primitive/-/2 source/level (value-number (exact-number 1)))
                source/env.10))
            (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/form.2) literal.5))
              (begin
                (if (value-truth? (primitive/=/2 source/level (value-number (exact-number 1))))
                  (body/source/scheme-error literal.4 (value-cons source/form.2 (value-null)))
                  (value-unspecified))
                (body/source/comp-quasiquotation-list
                  source/form.2
                  (primitive/-/2 source/level (value-number (exact-number 1)))
                  source/env.10))
              (body/source/comp-quasiquotation-list source/form.2 source/level source/env.10))))
        (if (value-truth? (primitive/vector?/1 source/form.2))
          (body/source/gen-vector-form
            (body/source/comp-quasiquotation-list
              (body/source/vector->lst source/form.2)
              source/level
              source/env.10))
          (body/source/gen-cst source/form.2))))))

(ref-set!
  source/comp-quasiquotation
  (value-procedure (ref (unit)) (function-3 body/source/comp-quasiquotation)))

(define source/comp-quasiquotation-list (ref (value-uninitialized)))

(define body/source/comp-quasiquotation-list
  (lambda (source/l.4 source/level.1 source/env.11)
    (if (value-truth? (primitive/pair?/1 source/l.4))
      ((lambda (source/first) (if (value-truth? (primitive/=/2 source/level.1 (value-number (exact-number 1)))) (if (value-truth? (body/source/unquote-splicing? source/first)) (begin (body/source/shape source/first (value-number (exact-number 2))) (body/source/gen-append-form (body/source/scheme-comp (primitive/cadr/1 source/first) source/env.11) (body/source/comp-quasiquotation (primitive/cdr/1 source/l.4) (value-number (exact-number 1)) source/env.11))) (body/source/gen-cons-form (body/source/comp-quasiquotation source/first source/level.1 source/env.11) (body/source/comp-quasiquotation (primitive/cdr/1 source/l.4) source/level.1 source/env.11))) (body/source/gen-cons-form (body/source/comp-quasiquotation source/first source/level.1 source/env.11) (body/source/comp-quasiquotation (primitive/cdr/1 source/l.4) source/level.1 source/env.11))))
        (primitive/car/1 source/l.4))
      (body/source/comp-quasiquotation source/l.4 source/level.1 source/env.11))))

(ref-set!
  source/comp-quasiquotation-list
  (value-procedure (ref (unit)) (function-3 body/source/comp-quasiquotation-list)))

(define source/unquote-splicing? (ref (value-uninitialized)))

(define body/source/unquote-splicing?
  (lambda (source/x.1)
    (if (value-truth? (primitive/pair?/1 source/x.1))
      (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/x.1) literal.8))
        (value-boolean #t)
        (value-boolean #f))
      (value-boolean #f))))

(ref-set!
  source/unquote-splicing?
  (value-procedure (ref (unit)) (function-1 body/source/unquote-splicing?)))

(define source/comp-unquote (ref (value-uninitialized)))

(define body/source/comp-unquote
  (lambda (source/expr.6 source/env.12)
    (body/source/scheme-error literal.9 (value-cons source/expr.6 (value-null)))))

(ref-set! source/comp-unquote (value-procedure (ref (unit)) (function-2 body/source/comp-unquote)))

(define source/comp-unquote-splicing (ref (value-uninitialized)))

(define body/source/comp-unquote-splicing
  (lambda (source/expr.7 source/env.13)
    (body/source/scheme-error literal.10 (value-cons source/expr.7 (value-null)))))

(ref-set!
  source/comp-unquote-splicing
  (value-procedure (ref (unit)) (function-2 body/source/comp-unquote-splicing)))

(define source/comp-set! (ref (value-uninitialized)))

(define body/source/comp-set!
  (lambda (source/expr.8 source/env.14)
    (begin
      (body/source/shape source/expr.8 (value-number (exact-number 3)))
      (body/source/variable (primitive/cadr/1 source/expr.8))
      (body/source/gen-var-set
        (body/source/lookup-var (primitive/cadr/1 source/expr.8) source/env.14)
        (body/source/scheme-comp (primitive/caddr/1 source/expr.8) source/env.14)))))

(ref-set! source/comp-set! (value-procedure (ref (unit)) (function-2 body/source/comp-set!)))

(define source/comp-lambda (ref (value-uninitialized)))

(define body/source/comp-lambda
  (lambda (source/expr.9 source/env.15)
    (begin
      (body/source/shape source/expr.9 (value-number (exact-number 3)))
      ((lambda (source/parms) ((lambda (source/frame.2) ((lambda (source/nb-vars source/code.1) (if (value-truth? (body/source/rest-param? source/parms)) (body/source/gen-lambda-rest source/nb-vars source/code.1) (body/source/gen-lambda source/nb-vars source/code.1))) (primitive/length/1 source/frame.2) (body/source/comp-body (primitive/cddr/1 source/expr.9) (body/source/push-frame source/frame.2 source/env.15)))) (body/source/parms->frame source/parms)))
        (primitive/cadr/1 source/expr.9)))))

(ref-set! source/comp-lambda (value-procedure (ref (unit)) (function-2 body/source/comp-lambda)))

(define source/parms->frame (ref (value-uninitialized)))

(define body/source/parms->frame
  (lambda (source/parms.1)
    (if (value-truth? (primitive/null?/1 source/parms.1))
      (value-null)
      (if (value-truth? (primitive/pair?/1 source/parms.1))
        ((lambda (source/x.2) (begin (body/source/variable source/x.2) (primitive/cons/2 source/x.2 (body/source/parms->frame (primitive/cdr/1 source/parms.1)))))
          (primitive/car/1 source/parms.1))
        (begin (body/source/variable source/parms.1) (primitive/list/1 source/parms.1))))))

(ref-set! source/parms->frame (value-procedure (ref (unit)) (function-1 body/source/parms->frame)))

(define source/rest-param? (ref (value-uninitialized)))

(define body/source/rest-param?
  (lambda (source/parms.2)
    (if (value-truth? (primitive/pair?/1 source/parms.2))
      (body/source/rest-param? (primitive/cdr/1 source/parms.2))
      (if (value-truth? (primitive/null?/1 source/parms.2)) (value-boolean #f) (value-boolean #t)))))

(ref-set! source/rest-param? (value-procedure (ref (unit)) (function-1 body/source/rest-param?)))

(define source/comp-body (ref (value-uninitialized)))

(define body/source/comp-body
  (lambda (source/body source/env.16)
    (let ((source/letrec-defines #f) (body/source/letrec-defines #f) (source/letrec-defines* #f) (body/source/letrec-defines* #f))
      (set! source/letrec-defines (ref (value-uninitialized)))
      (set!
        body/source/letrec-defines
        (lambda (source/vars source/vals source/body.1 source/env.17)
          (if (value-truth? (primitive/pair?/1 source/body.1))
            ((lambda (source/expr.10) (if (value-truth? (primitive/not/1 (primitive/pair?/1 source/expr.10))) (body/source/letrec-defines* source/vars source/vals source/body.1 source/env.17) (if (value-truth? (body/source/macro? (primitive/car/1 source/expr.10) source/env.17)) (body/source/letrec-defines source/vars source/vals (primitive/cons/2 (body/source/macro-expand source/expr.10 source/env.17) (primitive/cdr/1 source/body.1)) source/env.17) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.10) literal.14)) (body/source/letrec-defines source/vars source/vals (primitive/append/2 (primitive/cdr/1 source/expr.10) (primitive/cdr/1 source/body.1)) source/env.17) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.10) literal.13)) ((lambda (source/x.4) (begin (body/source/variable source/x.4) (body/source/letrec-defines (primitive/cons/2 source/x.4 source/vars) (primitive/cons/2 (body/source/definition-value source/expr.10) source/vals) (primitive/cdr/1 source/body.1) source/env.17))) (body/source/definition-name source/expr.10)) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.10) literal.12)) ((lambda (source/x.3) (body/source/letrec-defines source/vars source/vals (primitive/cdr/1 source/body.1) (body/source/push-macro source/x.3 (body/source/scheme-eval (body/source/definition-value source/expr.10)) source/env.17))) (body/source/definition-name source/expr.10)) (body/source/letrec-defines* source/vars source/vals source/body.1 source/env.17)))))))
              (primitive/car/1 source/body.1))
            (body/source/scheme-error literal.11 (value-null)))))
      (ref-set!
        source/letrec-defines
        (value-procedure (ref (unit)) (function-4 body/source/letrec-defines)))
      (set! source/letrec-defines* (ref (value-uninitialized)))
      (set!
        body/source/letrec-defines*
        (lambda (source/vars.1 source/vals.1 source/body.2 source/env.18)
          (if (value-truth? (primitive/null?/1 source/vars.1))
            (body/source/comp-sequence source/body.2 source/env.18)
            (body/source/comp-letrec-aux source/vars.1 source/vals.1 source/body.2 source/env.18))))
      (ref-set!
        source/letrec-defines*
        (value-procedure (ref (unit)) (function-4 body/source/letrec-defines*)))
      (body/source/letrec-defines (value-null) (value-null) source/body source/env.16))))

(ref-set! source/comp-body (value-procedure (ref (unit)) (function-2 body/source/comp-body)))

(define source/definition-name (ref (value-uninitialized)))

(define body/source/definition-name
  (lambda (source/expr.11)
    (begin
      (body/source/shape source/expr.11 (value-number (exact-number 3)))
      ((lambda (source/pattern) ((lambda (source/name.5) (begin (if (value-truth? (primitive/symbol?/1 source/name.5)) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)) (body/source/scheme-error literal.15 (value-cons source/name.5 (value-null)))) source/name.5)) (if (value-truth? (primitive/pair?/1 source/pattern)) (primitive/car/1 source/pattern) source/pattern)))
        (primitive/cadr/1 source/expr.11)))))

(ref-set!
  source/definition-name
  (value-procedure (ref (unit)) (function-1 body/source/definition-name)))

(define source/definition-value (ref (value-uninitialized)))

(define body/source/definition-value
  (lambda (source/expr.12)
    ((lambda (source/pattern.1) (if (value-truth? (primitive/pair?/1 source/pattern.1)) (primitive/cons/2 literal.16 (primitive/cons/2 (primitive/cdr/1 source/pattern.1) (primitive/cddr/1 source/expr.12))) (primitive/caddr/1 source/expr.12)))
      (primitive/cadr/1 source/expr.12))))

(ref-set!
  source/definition-value
  (value-procedure (ref (unit)) (function-1 body/source/definition-value)))

(define source/comp-if (ref (value-uninitialized)))

(define body/source/comp-if
  (lambda (source/expr.13 source/env.19)
    (begin
      (body/source/shape source/expr.13 (value-number (exact-number 3)))
      ((lambda (source/code1 source/code2) (if (value-truth? (primitive/pair?/1 (primitive/cdddr/1 source/expr.13))) (body/source/gen-if source/code1 source/code2 (body/source/scheme-comp (primitive/cadddr/1 source/expr.13) source/env.19)) (body/source/gen-when source/code1 source/code2)))
        (body/source/scheme-comp (primitive/cadr/1 source/expr.13) source/env.19)
        (body/source/scheme-comp (primitive/caddr/1 source/expr.13) source/env.19)))))

(ref-set! source/comp-if (value-procedure (ref (unit)) (function-2 body/source/comp-if)))

(define source/comp-cond (ref (value-uninitialized)))

(define body/source/comp-cond
  (lambda (source/expr.14 source/env.20)
    (body/source/comp-cond-aux (primitive/cdr/1 source/expr.14) source/env.20)))

(ref-set! source/comp-cond (value-procedure (ref (unit)) (function-2 body/source/comp-cond)))

(define source/comp-cond-aux (ref (value-uninitialized)))

(define body/source/comp-cond-aux
  (lambda (source/clauses source/env.21)
    (if (value-truth? (primitive/pair?/1 source/clauses))
      ((lambda (source/clause) (begin (body/source/shape source/clause (value-number (exact-number 1))) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/clause) literal.18)) (begin (body/source/shape source/clause (value-number (exact-number 2))) (body/source/comp-sequence (primitive/cdr/1 source/clause) source/env.21)) (if (value-truth? (primitive/not/1 (primitive/pair?/1 (primitive/cdr/1 source/clause)))) (body/source/gen-or (body/source/scheme-comp (primitive/car/1 source/clause) source/env.21) (body/source/comp-cond-aux (primitive/cdr/1 source/clauses) source/env.21)) (if (value-truth? (primitive/eq?/2 (primitive/cadr/1 source/clause) literal.17)) (begin (body/source/shape source/clause (value-number (exact-number 3))) (body/source/gen-cond-send (body/source/scheme-comp (primitive/car/1 source/clause) source/env.21) (body/source/scheme-comp (primitive/caddr/1 source/clause) source/env.21) (body/source/comp-cond-aux (primitive/cdr/1 source/clauses) source/env.21))) (body/source/gen-if (body/source/scheme-comp (primitive/car/1 source/clause) source/env.21) (body/source/comp-sequence (primitive/cdr/1 source/clause) source/env.21) (body/source/comp-cond-aux (primitive/cdr/1 source/clauses) source/env.21)))))))
        (primitive/car/1 source/clauses))
      (body/source/gen-cst (value-null)))))

(ref-set!
  source/comp-cond-aux
  (value-procedure (ref (unit)) (function-2 body/source/comp-cond-aux)))

(define source/comp-and (ref (value-uninitialized)))

(define body/source/comp-and
  (lambda (source/expr.15 source/env.22)
    ((lambda (source/rest) (if (value-truth? (primitive/pair?/1 source/rest)) (body/source/comp-and-aux source/rest source/env.22) (body/source/gen-cst (value-boolean #t))))
      (primitive/cdr/1 source/expr.15))))

(ref-set! source/comp-and (value-procedure (ref (unit)) (function-2 body/source/comp-and)))

(define source/comp-and-aux (ref (value-uninitialized)))

(define body/source/comp-and-aux
  (lambda (source/l.5 source/env.23)
    ((lambda (source/code.2 source/rest.1) (if (value-truth? (primitive/pair?/1 source/rest.1)) (body/source/gen-and source/code.2 (body/source/comp-and-aux source/rest.1 source/env.23)) source/code.2))
      (body/source/scheme-comp (primitive/car/1 source/l.5) source/env.23)
      (primitive/cdr/1 source/l.5))))

(ref-set! source/comp-and-aux (value-procedure (ref (unit)) (function-2 body/source/comp-and-aux)))

(define source/comp-or (ref (value-uninitialized)))

(define body/source/comp-or
  (lambda (source/expr.16 source/env.24)
    ((lambda (source/rest.2) (if (value-truth? (primitive/pair?/1 source/rest.2)) (body/source/comp-or-aux source/rest.2 source/env.24) (body/source/gen-cst (value-boolean #f))))
      (primitive/cdr/1 source/expr.16))))

(ref-set! source/comp-or (value-procedure (ref (unit)) (function-2 body/source/comp-or)))

(define source/comp-or-aux (ref (value-uninitialized)))

(define body/source/comp-or-aux
  (lambda (source/l.6 source/env.25)
    ((lambda (source/code.3 source/rest.3) (if (value-truth? (primitive/pair?/1 source/rest.3)) (body/source/gen-or source/code.3 (body/source/comp-or-aux source/rest.3 source/env.25)) source/code.3))
      (body/source/scheme-comp (primitive/car/1 source/l.6) source/env.25)
      (primitive/cdr/1 source/l.6))))

(ref-set! source/comp-or-aux (value-procedure (ref (unit)) (function-2 body/source/comp-or-aux)))

(define source/comp-case (ref (value-uninitialized)))

(define body/source/comp-case
  (lambda (source/expr.17 source/env.26)
    (begin
      (body/source/shape source/expr.17 (value-number (exact-number 3)))
      (body/source/gen-case
        (body/source/scheme-comp (primitive/cadr/1 source/expr.17) source/env.26)
        (body/source/comp-case-aux (primitive/cddr/1 source/expr.17) source/env.26)))))

(ref-set! source/comp-case (value-procedure (ref (unit)) (function-2 body/source/comp-case)))

(define source/comp-case-aux (ref (value-uninitialized)))

(define body/source/comp-case-aux
  (lambda (source/clauses.1 source/env.27)
    (if (value-truth? (primitive/pair?/1 source/clauses.1))
      ((lambda (source/clause.1) (begin (body/source/shape source/clause.1 (value-number (exact-number 2))) (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/clause.1) literal.19)) (body/source/gen-case-else (body/source/comp-sequence (primitive/cdr/1 source/clause.1) source/env.27)) (body/source/gen-case-clause (primitive/car/1 source/clause.1) (body/source/comp-sequence (primitive/cdr/1 source/clause.1) source/env.27) (body/source/comp-case-aux (primitive/cdr/1 source/clauses.1) source/env.27)))))
        (primitive/car/1 source/clauses.1))
      (body/source/gen-case-else (body/source/gen-cst (value-null))))))

(ref-set!
  source/comp-case-aux
  (value-procedure (ref (unit)) (function-2 body/source/comp-case-aux)))

(define source/comp-let (ref (value-uninitialized)))

(define body/source/comp-let
  (lambda (source/expr.18 source/env.28)
    (begin
      (body/source/shape source/expr.18 (value-number (exact-number 3)))
      ((lambda (source/x.5) (if (value-truth? (primitive/symbol?/1 source/x.5)) (begin (body/source/shape source/expr.18 (value-number (exact-number 4))) ((lambda (source/y) ((lambda (source/proc.2) (body/source/scheme-comp (primitive/cons/2 (primitive/list/3 literal.22 (primitive/list/1 (primitive/list/2 source/x.5 source/proc.2)) source/x.5) (body/source/bindings->vals source/y)) source/env.28)) (primitive/cons/2 literal.21 (primitive/cons/2 (body/source/bindings->vars source/y) (primitive/cdddr/1 source/expr.18))))) (primitive/caddr/1 source/expr.18))) (if (value-truth? (primitive/pair?/1 source/x.5)) (body/source/scheme-comp (primitive/cons/2 (primitive/cons/2 literal.20 (primitive/cons/2 (body/source/bindings->vars source/x.5) (primitive/cddr/1 source/expr.18))) (body/source/bindings->vals source/x.5)) source/env.28) (body/source/comp-body (primitive/cddr/1 source/expr.18) source/env.28))))
        (primitive/cadr/1 source/expr.18)))))

(ref-set! source/comp-let (value-procedure (ref (unit)) (function-2 body/source/comp-let)))

(define source/bindings->vars (ref (value-uninitialized)))

(define body/source/bindings->vars
  (lambda (source/bindings)
    (if (value-truth? (primitive/pair?/1 source/bindings))
      ((lambda (source/binding) (begin (body/source/shape source/binding (value-number (exact-number 2))) ((lambda (source/x.6) (begin (body/source/variable source/x.6) (primitive/cons/2 source/x.6 (body/source/bindings->vars (primitive/cdr/1 source/bindings))))) (primitive/car/1 source/binding))))
        (primitive/car/1 source/bindings))
      (value-null))))

(ref-set!
  source/bindings->vars
  (value-procedure (ref (unit)) (function-1 body/source/bindings->vars)))

(define source/bindings->vals (ref (value-uninitialized)))

(define body/source/bindings->vals
  (lambda (source/bindings.1)
    (if (value-truth? (primitive/pair?/1 source/bindings.1))
      ((lambda (source/binding.1) (primitive/cons/2 (primitive/cadr/1 source/binding.1) (body/source/bindings->vals (primitive/cdr/1 source/bindings.1))))
        (primitive/car/1 source/bindings.1))
      (value-null))))

(ref-set!
  source/bindings->vals
  (value-procedure (ref (unit)) (function-1 body/source/bindings->vals)))

(define source/comp-let* (ref (value-uninitialized)))

(define body/source/comp-let*
  (lambda (source/expr.19 source/env.29)
    (begin
      (body/source/shape source/expr.19 (value-number (exact-number 3)))
      ((lambda (source/bindings.2) (if (value-truth? (primitive/pair?/1 source/bindings.2)) (body/source/scheme-comp (primitive/list/3 literal.23 (primitive/list/1 (primitive/car/1 source/bindings.2)) (primitive/cons/2 literal.24 (primitive/cons/2 (primitive/cdr/1 source/bindings.2) (primitive/cddr/1 source/expr.19)))) source/env.29) (body/source/comp-body (primitive/cddr/1 source/expr.19) source/env.29)))
        (primitive/cadr/1 source/expr.19)))))

(ref-set! source/comp-let* (value-procedure (ref (unit)) (function-2 body/source/comp-let*)))

(define source/comp-letrec (ref (value-uninitialized)))

(define body/source/comp-letrec
  (lambda (source/expr.20 source/env.30)
    (begin
      (body/source/shape source/expr.20 (value-number (exact-number 3)))
      ((lambda (source/bindings.3) (body/source/comp-letrec-aux (body/source/bindings->vars source/bindings.3) (body/source/bindings->vals source/bindings.3) (primitive/cddr/1 source/expr.20) source/env.30))
        (primitive/cadr/1 source/expr.20)))))

(ref-set! source/comp-letrec (value-procedure (ref (unit)) (function-2 body/source/comp-letrec)))

(define source/comp-letrec-aux (ref (value-uninitialized)))

(define body/source/comp-letrec-aux
  (lambda (source/vars.2 source/vals.2 source/body.3 source/env.31)
    (if (value-truth? (primitive/pair?/1 source/vars.2))
      ((lambda (source/new-env) (body/source/gen-letrec (body/source/comp-vals source/vals.2 source/new-env) (body/source/comp-body source/body.3 source/new-env)))
        (body/source/push-frame source/vars.2 source/env.31))
      (body/source/comp-body source/body.3 source/env.31))))

(ref-set!
  source/comp-letrec-aux
  (value-procedure (ref (unit)) (function-4 body/source/comp-letrec-aux)))

(define source/comp-vals (ref (value-uninitialized)))

(define body/source/comp-vals
  (lambda (source/l.7 source/env.32)
    (if (value-truth? (primitive/pair?/1 source/l.7))
      (primitive/cons/2
        (body/source/scheme-comp (primitive/car/1 source/l.7) source/env.32)
        (body/source/comp-vals (primitive/cdr/1 source/l.7) source/env.32))
      (value-null))))

(ref-set! source/comp-vals (value-procedure (ref (unit)) (function-2 body/source/comp-vals)))

(define source/comp-begin (ref (value-uninitialized)))

(define body/source/comp-begin
  (lambda (source/expr.21 source/env.33)
    (begin
      (body/source/shape source/expr.21 (value-number (exact-number 2)))
      (body/source/comp-sequence (primitive/cdr/1 source/expr.21) source/env.33))))

(ref-set! source/comp-begin (value-procedure (ref (unit)) (function-2 body/source/comp-begin)))

(define source/comp-sequence (ref (value-uninitialized)))

(define body/source/comp-sequence
  (lambda (source/exprs source/env.34)
    (if (value-truth? (primitive/pair?/1 source/exprs))
      (body/source/comp-sequence-aux source/exprs source/env.34)
      (body/source/gen-cst (value-null)))))

(ref-set!
  source/comp-sequence
  (value-procedure (ref (unit)) (function-2 body/source/comp-sequence)))

(define source/comp-sequence-aux (ref (value-uninitialized)))

(define body/source/comp-sequence-aux
  (lambda (source/exprs.1 source/env.35)
    ((lambda (source/code.4 source/rest.4) (if (value-truth? (primitive/pair?/1 source/rest.4)) (body/source/gen-sequence source/code.4 (body/source/comp-sequence-aux source/rest.4 source/env.35)) source/code.4))
      (body/source/scheme-comp (primitive/car/1 source/exprs.1) source/env.35)
      (primitive/cdr/1 source/exprs.1))))

(ref-set!
  source/comp-sequence-aux
  (value-procedure (ref (unit)) (function-2 body/source/comp-sequence-aux)))

(define source/comp-do (ref (value-uninitialized)))

(define body/source/comp-do
  (lambda (source/expr.22 source/env.36)
    (begin
      (body/source/shape source/expr.22 (value-number (exact-number 3)))
      ((lambda (source/bindings.4 source/exit) (begin (body/source/shape source/exit (value-number (exact-number 1))) ((lambda (source/vars.3) ((lambda (source/new-env1) ((lambda (source/new-env2) ((lambda () (body/source/gen-letrec (primitive/list/1 (body/source/gen-lambda (primitive/length/1 source/vars.3) (body/source/gen-if (body/source/scheme-comp (primitive/car/1 source/exit) source/new-env2) (body/source/comp-sequence (primitive/cdr/1 source/exit) source/new-env2) (body/source/gen-sequence (body/source/comp-sequence (primitive/cdddr/1 source/expr.22) source/new-env2) (body/source/gen-combination (body/source/gen-var-ref literal.26) (body/source/comp-vals (body/source/bindings->steps source/bindings.4) source/new-env2)))))) (body/source/gen-combination (body/source/gen-var-ref literal.27) (body/source/comp-vals (body/source/bindings->vals source/bindings.4) source/new-env1)))))) (body/source/push-frame source/vars.3 source/new-env1))) (body/source/push-frame literal.25 source/env.36))) (body/source/bindings->vars source/bindings.4))))
        (primitive/cadr/1 source/expr.22)
        (primitive/caddr/1 source/expr.22)))))

(ref-set! source/comp-do (value-procedure (ref (unit)) (function-2 body/source/comp-do)))

(define source/bindings->steps (ref (value-uninitialized)))

(define body/source/bindings->steps
  (lambda (source/bindings.5)
    (if (value-truth? (primitive/pair?/1 source/bindings.5))
      ((lambda (source/binding.2) (primitive/cons/2 (if (value-truth? (primitive/pair?/1 (primitive/cddr/1 source/binding.2))) (primitive/caddr/1 source/binding.2) (primitive/car/1 source/binding.2)) (body/source/bindings->steps (primitive/cdr/1 source/bindings.5))))
        (primitive/car/1 source/bindings.5))
      (value-null))))

(ref-set!
  source/bindings->steps
  (value-procedure (ref (unit)) (function-1 body/source/bindings->steps)))

(define source/comp-define (ref (value-uninitialized)))

(define body/source/comp-define
  (lambda (source/expr.23 source/env.37)
    (begin
      (body/source/shape source/expr.23 (value-number (exact-number 3)))
      ((lambda (source/pattern.2) ((lambda (source/x.7) (begin (body/source/variable source/x.7) (body/source/gen-sequence (body/source/gen-var-set (body/source/lookup-var source/x.7 source/env.37) (body/source/scheme-comp (if (value-truth? (primitive/pair?/1 source/pattern.2)) (primitive/cons/2 literal.28 (primitive/cons/2 (primitive/cdr/1 source/pattern.2) (primitive/cddr/1 source/expr.23))) (primitive/caddr/1 source/expr.23)) source/env.37)) (body/source/gen-cst source/x.7)))) (if (value-truth? (primitive/pair?/1 source/pattern.2)) (primitive/car/1 source/pattern.2) source/pattern.2)))
        (primitive/cadr/1 source/expr.23)))))

(ref-set! source/comp-define (value-procedure (ref (unit)) (function-2 body/source/comp-define)))

(define source/comp-define-macro (ref (value-uninitialized)))

(define body/source/comp-define-macro
  (lambda (source/expr.24 source/env.38)
    ((lambda (source/x.8) (body/source/gen-macro source/x.8 (body/source/scheme-eval (body/source/definition-value source/expr.24))))
      (body/source/definition-name source/expr.24))))

(ref-set!
  source/comp-define-macro
  (value-procedure (ref (unit)) (function-2 body/source/comp-define-macro)))

(define source/comp-combination (ref (value-uninitialized)))

(define body/source/comp-combination
  (lambda (source/expr.25 source/env.39)
    (body/source/gen-combination
      (body/source/scheme-comp (primitive/car/1 source/expr.25) source/env.39)
      (body/source/comp-vals (primitive/cdr/1 source/expr.25) source/env.39))))

(ref-set!
  source/comp-combination
  (value-procedure (ref (unit)) (function-2 body/source/comp-combination)))

(define source/gen-var-ref (ref (value-uninitialized)))

(define body/source/gen-var-ref
  (lambda (source/var)
    (if (value-truth? (primitive/pair?/1 source/var))
      (body/source/gen-rte-ref (primitive/car/1 source/var) (primitive/cdr/1 source/var))
      (body/source/gen-glo-ref (body/source/scheme-global-var source/var)))))

(ref-set! source/gen-var-ref (value-procedure (ref (unit)) (function-1 body/source/gen-var-ref)))

(define source/gen-rte-ref (ref (value-uninitialized)))

(define body/source/gen-rte-ref
  (lambda (source/up.2 source/over.1)
    ((lambda (source/value.1) (if (value-truth? (primitive/memv/2 source/value.1 literal.30)) (body/source/gen-slot-ref-0 source/over.1) ((lambda (source/value.2) (if (value-truth? (primitive/memv/2 source/value.2 literal.29)) (body/source/gen-slot-ref-1 source/over.1) ((lambda (source/value.3) (body/source/gen-slot-ref-up-2 (body/source/gen-rte-ref (primitive/-/2 source/up.2 (value-number (exact-number 2))) source/over.1))) source/value.2))) source/value.1)))
      source/up.2)))

(ref-set! source/gen-rte-ref (value-procedure (ref (unit)) (function-2 body/source/gen-rte-ref)))

(define source/gen-slot-ref-0 (ref (value-uninitialized)))

(define body/source/gen-slot-ref-0
  (lambda (source/i.2)
    ((lambda (source/value.4) (if (value-truth? (primitive/memv/2 source/value.4 literal.34)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.4) (primitive/vector-ref/2 source/rte.4 (value-number (exact-number 0)))))) ((lambda (source/value.5) (if (value-truth? (primitive/memv/2 source/value.5 literal.33)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.3) (primitive/vector-ref/2 source/rte.3 (value-number (exact-number 1)))))) ((lambda (source/value.6) (if (value-truth? (primitive/memv/2 source/value.6 literal.32)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.2) (primitive/vector-ref/2 source/rte.2 (value-number (exact-number 2)))))) ((lambda (source/value.7) (if (value-truth? (primitive/memv/2 source/value.7 literal.31)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.1) (primitive/vector-ref/2 source/rte.1 (value-number (exact-number 3)))))) ((lambda (source/value.8) (value-procedure (ref (unit)) (function-1 (lambda (source/rte) (primitive/vector-ref/2 source/rte source/i.2))))) source/value.7))) source/value.6))) source/value.5))) source/value.4)))
      source/i.2)))

(ref-set!
  source/gen-slot-ref-0
  (value-procedure (ref (unit)) (function-1 body/source/gen-slot-ref-0)))

(define source/gen-slot-ref-1 (ref (value-uninitialized)))

(define body/source/gen-slot-ref-1
  (lambda (source/i.3)
    ((lambda (source/value.9) (if (value-truth? (primitive/memv/2 source/value.9 literal.38)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.9) (primitive/vector-ref/2 (primitive/vector-ref/2 source/rte.9 (value-number (exact-number 0))) (value-number (exact-number 0)))))) ((lambda (source/value.10) (if (value-truth? (primitive/memv/2 source/value.10 literal.37)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.8) (primitive/vector-ref/2 (primitive/vector-ref/2 source/rte.8 (value-number (exact-number 0))) (value-number (exact-number 1)))))) ((lambda (source/value.11) (if (value-truth? (primitive/memv/2 source/value.11 literal.36)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.7) (primitive/vector-ref/2 (primitive/vector-ref/2 source/rte.7 (value-number (exact-number 0))) (value-number (exact-number 2)))))) ((lambda (source/value.12) (if (value-truth? (primitive/memv/2 source/value.12 literal.35)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.6) (primitive/vector-ref/2 (primitive/vector-ref/2 source/rte.6 (value-number (exact-number 0))) (value-number (exact-number 3)))))) ((lambda (source/value.13) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.5) (primitive/vector-ref/2 (primitive/vector-ref/2 source/rte.5 (value-number (exact-number 0))) source/i.3))))) source/value.12))) source/value.11))) source/value.10))) source/value.9)))
      source/i.3)))

(ref-set!
  source/gen-slot-ref-1
  (value-procedure (ref (unit)) (function-1 body/source/gen-slot-ref-1)))

(define source/gen-slot-ref-up-2 (ref (value-uninitialized)))

(define body/source/gen-slot-ref-up-2
  (lambda (source/code.5)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.10)
          (invoke-1
            source/code.5
            (primitive/vector-ref/2
              (primitive/vector-ref/2 source/rte.10 (value-number (exact-number 0)))
              (value-number (exact-number 0)))))))))

(ref-set!
  source/gen-slot-ref-up-2
  (value-procedure (ref (unit)) (function-1 body/source/gen-slot-ref-up-2)))

(define source/gen-glo-ref (ref (value-uninitialized)))

(define body/source/gen-glo-ref
  (lambda (source/i.4)
    (value-procedure
      (ref (unit))
      (function-1 (lambda (source/rte.11) (body/source/scheme-global-var-ref source/i.4))))))

(ref-set! source/gen-glo-ref (value-procedure (ref (unit)) (function-1 body/source/gen-glo-ref)))

(define source/gen-cst (ref (value-uninitialized)))

(define body/source/gen-cst
  (lambda (source/val)
    ((lambda (source/value.14) (if (value-truth? (primitive/memv/2 source/value.14 literal.46)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.20) (value-null)))) ((lambda (source/value.15) (if (value-truth? (primitive/memv/2 source/value.15 literal.45)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.19) (value-boolean #f)))) ((lambda (source/value.16) (if (value-truth? (primitive/memv/2 source/value.16 literal.44)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.18) (value-boolean #t)))) ((lambda (source/value.17) (if (value-truth? (primitive/memv/2 source/value.17 literal.43)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.17) (value-number (exact-number -2))))) ((lambda (source/value.18) (if (value-truth? (primitive/memv/2 source/value.18 literal.42)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.16) (value-number (exact-number -1))))) ((lambda (source/value.19) (if (value-truth? (primitive/memv/2 source/value.19 literal.41)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.15) (value-number (exact-number 0))))) ((lambda (source/value.20) (if (value-truth? (primitive/memv/2 source/value.20 literal.40)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.14) (value-number (exact-number 1))))) ((lambda (source/value.21) (if (value-truth? (primitive/memv/2 source/value.21 literal.39)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.13) (value-number (exact-number 2))))) ((lambda (source/value.22) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.12) source/val)))) source/value.21))) source/value.20))) source/value.19))) source/value.18))) source/value.17))) source/value.16))) source/value.15))) source/value.14)))
      source/val)))

(ref-set! source/gen-cst (value-procedure (ref (unit)) (function-1 body/source/gen-cst)))

(define source/gen-append-form (ref (value-uninitialized)))

(define body/source/gen-append-form
  (lambda (source/code1.1 source/code2.1)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.21)
          (primitive/append/2
            (invoke-1 source/code1.1 source/rte.21)
            (invoke-1 source/code2.1 source/rte.21)))))))

(ref-set!
  source/gen-append-form
  (value-procedure (ref (unit)) (function-2 body/source/gen-append-form)))

(define source/gen-cons-form (ref (value-uninitialized)))

(define body/source/gen-cons-form
  (lambda (source/code1.2 source/code2.2)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.22)
          (primitive/cons/2
            (invoke-1 source/code1.2 source/rte.22)
            (invoke-1 source/code2.2 source/rte.22)))))))

(ref-set!
  source/gen-cons-form
  (value-procedure (ref (unit)) (function-2 body/source/gen-cons-form)))

(define source/gen-vector-form (ref (value-uninitialized)))

(define body/source/gen-vector-form
  (lambda (source/code.6)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.23) (body/source/lst->vector (invoke-1 source/code.6 source/rte.23)))))))

(ref-set!
  source/gen-vector-form
  (value-procedure (ref (unit)) (function-1 body/source/gen-vector-form)))

(define source/gen-var-set (ref (value-uninitialized)))

(define body/source/gen-var-set
  (lambda (source/var.1 source/code.7)
    (if (value-truth? (primitive/pair?/1 source/var.1))
      (body/source/gen-rte-set
        (primitive/car/1 source/var.1)
        (primitive/cdr/1 source/var.1)
        source/code.7)
      (body/source/gen-glo-set (body/source/scheme-global-var source/var.1) source/code.7))))

(ref-set! source/gen-var-set (value-procedure (ref (unit)) (function-2 body/source/gen-var-set)))

(define source/gen-rte-set (ref (value-uninitialized)))

(define body/source/gen-rte-set
  (lambda (source/up.3 source/over.2 source/code.8)
    ((lambda (source/value.23) (if (value-truth? (primitive/memv/2 source/value.23 literal.48)) (body/source/gen-slot-set-0 source/over.2 source/code.8) ((lambda (source/value.24) (if (value-truth? (primitive/memv/2 source/value.24 literal.47)) (body/source/gen-slot-set-1 source/over.2 source/code.8) ((lambda (source/value.25) (body/source/gen-slot-set-n (body/source/gen-rte-ref (primitive/-/2 source/up.3 (value-number (exact-number 2))) (value-number (exact-number 0))) source/over.2 source/code.8)) source/value.24))) source/value.23)))
      source/up.3)))

(ref-set! source/gen-rte-set (value-procedure (ref (unit)) (function-3 body/source/gen-rte-set)))

(define source/gen-slot-set-0 (ref (value-uninitialized)))

(define body/source/gen-slot-set-0
  (lambda (source/i.5 source/code.9)
    ((lambda (source/value.26) (if (value-truth? (primitive/memv/2 source/value.26 literal.52)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.28) (primitive/vector-set!/3 source/rte.28 (value-number (exact-number 0)) (invoke-1 source/code.9 source/rte.28))))) ((lambda (source/value.27) (if (value-truth? (primitive/memv/2 source/value.27 literal.51)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.27) (primitive/vector-set!/3 source/rte.27 (value-number (exact-number 1)) (invoke-1 source/code.9 source/rte.27))))) ((lambda (source/value.28) (if (value-truth? (primitive/memv/2 source/value.28 literal.50)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.26) (primitive/vector-set!/3 source/rte.26 (value-number (exact-number 2)) (invoke-1 source/code.9 source/rte.26))))) ((lambda (source/value.29) (if (value-truth? (primitive/memv/2 source/value.29 literal.49)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.25) (primitive/vector-set!/3 source/rte.25 (value-number (exact-number 3)) (invoke-1 source/code.9 source/rte.25))))) ((lambda (source/value.30) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.24) (primitive/vector-set!/3 source/rte.24 source/i.5 (invoke-1 source/code.9 source/rte.24)))))) source/value.29))) source/value.28))) source/value.27))) source/value.26)))
      source/i.5)))

(ref-set!
  source/gen-slot-set-0
  (value-procedure (ref (unit)) (function-2 body/source/gen-slot-set-0)))

(define source/gen-slot-set-1 (ref (value-uninitialized)))

(define body/source/gen-slot-set-1
  (lambda (source/i.6 source/code.10)
    ((lambda (source/value.31) (if (value-truth? (primitive/memv/2 source/value.31 literal.56)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.33) (primitive/vector-set!/3 (primitive/vector-ref/2 source/rte.33 (value-number (exact-number 0))) (value-number (exact-number 0)) (invoke-1 source/code.10 source/rte.33))))) ((lambda (source/value.32) (if (value-truth? (primitive/memv/2 source/value.32 literal.55)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.32) (primitive/vector-set!/3 (primitive/vector-ref/2 source/rte.32 (value-number (exact-number 0))) (value-number (exact-number 1)) (invoke-1 source/code.10 source/rte.32))))) ((lambda (source/value.33) (if (value-truth? (primitive/memv/2 source/value.33 literal.54)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.31) (primitive/vector-set!/3 (primitive/vector-ref/2 source/rte.31 (value-number (exact-number 0))) (value-number (exact-number 2)) (invoke-1 source/code.10 source/rte.31))))) ((lambda (source/value.34) (if (value-truth? (primitive/memv/2 source/value.34 literal.53)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.30) (primitive/vector-set!/3 (primitive/vector-ref/2 source/rte.30 (value-number (exact-number 0))) (value-number (exact-number 3)) (invoke-1 source/code.10 source/rte.30))))) ((lambda (source/value.35) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.29) (primitive/vector-set!/3 (primitive/vector-ref/2 source/rte.29 (value-number (exact-number 0))) source/i.6 (invoke-1 source/code.10 source/rte.29)))))) source/value.34))) source/value.33))) source/value.32))) source/value.31)))
      source/i.6)))

(ref-set!
  source/gen-slot-set-1
  (value-procedure (ref (unit)) (function-2 body/source/gen-slot-set-1)))

(define source/gen-slot-set-n (ref (value-uninitialized)))

(define body/source/gen-slot-set-n
  (lambda (source/up.4 source/i.7 source/code.11)
    ((lambda (source/value.36) (if (value-truth? (primitive/memv/2 source/value.36 literal.60)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.38) (primitive/vector-set!/3 (invoke-1 source/up.4 (primitive/vector-ref/2 source/rte.38 (value-number (exact-number 0)))) (value-number (exact-number 0)) (invoke-1 source/code.11 source/rte.38))))) ((lambda (source/value.37) (if (value-truth? (primitive/memv/2 source/value.37 literal.59)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.37) (primitive/vector-set!/3 (invoke-1 source/up.4 (primitive/vector-ref/2 source/rte.37 (value-number (exact-number 0)))) (value-number (exact-number 1)) (invoke-1 source/code.11 source/rte.37))))) ((lambda (source/value.38) (if (value-truth? (primitive/memv/2 source/value.38 literal.58)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.36) (primitive/vector-set!/3 (invoke-1 source/up.4 (primitive/vector-ref/2 source/rte.36 (value-number (exact-number 0)))) (value-number (exact-number 2)) (invoke-1 source/code.11 source/rte.36))))) ((lambda (source/value.39) (if (value-truth? (primitive/memv/2 source/value.39 literal.57)) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.35) (primitive/vector-set!/3 (invoke-1 source/up.4 (primitive/vector-ref/2 source/rte.35 (value-number (exact-number 0)))) (value-number (exact-number 3)) (invoke-1 source/code.11 source/rte.35))))) ((lambda (source/value.40) (value-procedure (ref (unit)) (function-1 (lambda (source/rte.34) (primitive/vector-set!/3 (invoke-1 source/up.4 (primitive/vector-ref/2 source/rte.34 (value-number (exact-number 0)))) source/i.7 (invoke-1 source/code.11 source/rte.34)))))) source/value.39))) source/value.38))) source/value.37))) source/value.36)))
      source/i.7)))

(ref-set!
  source/gen-slot-set-n
  (value-procedure (ref (unit)) (function-3 body/source/gen-slot-set-n)))

(define source/gen-glo-set (ref (value-uninitialized)))

(define body/source/gen-glo-set
  (lambda (source/i.8 source/code.12)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.39)
          (body/source/scheme-global-var-set! source/i.8 (invoke-1 source/code.12 source/rte.39)))))))

(ref-set! source/gen-glo-set (value-procedure (ref (unit)) (function-2 body/source/gen-glo-set)))

(define source/gen-lambda-rest (ref (value-uninitialized)))

(define body/source/gen-lambda-rest
  (lambda (source/nb-vars.1 source/body.4)
    ((lambda (source/value.41) (if (value-truth? (primitive/memv/2 source/value.41 literal.63)) (body/source/gen-lambda-1-rest source/body.4) ((lambda (source/value.42) (if (value-truth? (primitive/memv/2 source/value.42 literal.62)) (body/source/gen-lambda-2-rest source/body.4) ((lambda (source/value.43) (if (value-truth? (primitive/memv/2 source/value.43 literal.61)) (body/source/gen-lambda-3-rest source/body.4) ((lambda (source/value.44) (body/source/gen-lambda-n-rest source/nb-vars.1 source/body.4)) source/value.43))) source/value.42))) source/value.41)))
      source/nb-vars.1)))

(ref-set!
  source/gen-lambda-rest
  (value-procedure (ref (unit)) (function-2 body/source/gen-lambda-rest)))

(define source/gen-lambda-1-rest (ref (value-uninitialized)))

(define body/source/gen-lambda-1-rest
  (lambda (source/body.5)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.40)
          (value-procedure
            (ref (unit))
            (function-rest-0
              (lambda (source/a)
                (invoke-1 source/body.5 (primitive/vector/2 source/rte.40 source/a))))))))))

(ref-set!
  source/gen-lambda-1-rest
  (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-1-rest)))

(define source/gen-lambda-2-rest (ref (value-uninitialized)))

(define body/source/gen-lambda-2-rest
  (lambda (source/body.6)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.41)
          (value-procedure
            (ref (unit))
            (function-rest-1
              (lambda (source/a.1 source/b)
                (invoke-1 source/body.6 (primitive/vector/3 source/rte.41 source/a.1 source/b))))))))))

(ref-set!
  source/gen-lambda-2-rest
  (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-2-rest)))

(define source/gen-lambda-3-rest (ref (value-uninitialized)))

(define body/source/gen-lambda-3-rest
  (lambda (source/body.7)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.42)
          (value-procedure
            (ref (unit))
            (function-rest-2
              (lambda (source/a.2 source/b.1 source/c)
                (invoke-1
                  source/body.7
                  (primitive/vector/4 source/rte.42 source/a.2 source/b.1 source/c))))))))))

(ref-set!
  source/gen-lambda-3-rest
  (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-3-rest)))

(define source/gen-lambda-n-rest (ref (value-uninitialized)))

(define body/source/gen-lambda-n-rest
  (lambda (source/nb-vars.2 source/body.8)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.43)
          (value-procedure
            (ref (unit))
            (function-rest-3
              (lambda (source/a.3 source/b.2 source/c.1 source/d)
                ((lambda (source/x.9) (begin (primitive/vector-set!/3 source/x.9 (value-number (exact-number 0)) source/rte.43) (primitive/vector-set!/3 source/x.9 (value-number (exact-number 1)) source/a.3) (primitive/vector-set!/3 source/x.9 (value-number (exact-number 2)) source/b.2) (primitive/vector-set!/3 source/x.9 (value-number (exact-number 3)) source/c.1) (invoke-4 ((lambda () (let ((source/loop.3 #f) (body/source/loop.3 #f)) (set! source/loop.3 (ref (value-uninitialized))) (set! body/source/loop.3 (lambda (source/n.3 source/x.10 source/i.9 source/l.8) (if (value-truth? (primitive/</2 source/i.9 source/n.3)) (begin (primitive/vector-set!/3 source/x.10 source/i.9 (primitive/car/1 source/l.8)) (body/source/loop.3 source/n.3 source/x.10 (primitive/+/2 source/i.9 (value-number (exact-number 1))) (primitive/cdr/1 source/l.8))) (primitive/vector-set!/3 source/x.10 source/i.9 source/l.8)))) (ref-set! source/loop.3 (value-procedure (ref (unit)) (function-4 body/source/loop.3))) (binding-value source/loop.3)))) source/nb-vars.2 source/x.9 (value-number (exact-number 4)) source/d) (invoke-1 source/body.8 source/x.9)))
                  (primitive/make-vector/1
                    (primitive/+/2 source/nb-vars.2 (value-number (exact-number 1)))))))))))))

(ref-set!
  source/gen-lambda-n-rest
  (value-procedure (ref (unit)) (function-2 body/source/gen-lambda-n-rest)))

(define source/gen-lambda (ref (value-uninitialized)))

(define body/source/gen-lambda
  (lambda (source/nb-vars.3 source/body.9)
    ((lambda (source/value.45) (if (value-truth? (primitive/memv/2 source/value.45 literal.67)) (body/source/gen-lambda-0 source/body.9) ((lambda (source/value.46) (if (value-truth? (primitive/memv/2 source/value.46 literal.66)) (body/source/gen-lambda-1 source/body.9) ((lambda (source/value.47) (if (value-truth? (primitive/memv/2 source/value.47 literal.65)) (body/source/gen-lambda-2 source/body.9) ((lambda (source/value.48) (if (value-truth? (primitive/memv/2 source/value.48 literal.64)) (body/source/gen-lambda-3 source/body.9) ((lambda (source/value.49) (body/source/gen-lambda-n source/nb-vars.3 source/body.9)) source/value.48))) source/value.47))) source/value.46))) source/value.45)))
      source/nb-vars.3)))

(ref-set! source/gen-lambda (value-procedure (ref (unit)) (function-2 body/source/gen-lambda)))

(define source/gen-lambda-0 (ref (value-uninitialized)))

(define body/source/gen-lambda-0
  (lambda (source/body.10)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.44)
          (value-procedure
            (ref (unit))
            (function-0 (lambda () (invoke-1 source/body.10 source/rte.44)))))))))

(ref-set! source/gen-lambda-0 (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-0)))

(define source/gen-lambda-1 (ref (value-uninitialized)))

(define body/source/gen-lambda-1
  (lambda (source/body.11)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.45)
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/a.4)
                (invoke-1 source/body.11 (primitive/vector/2 source/rte.45 source/a.4))))))))))

(ref-set! source/gen-lambda-1 (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-1)))

(define source/gen-lambda-2 (ref (value-uninitialized)))

(define body/source/gen-lambda-2
  (lambda (source/body.12)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.46)
          (value-procedure
            (ref (unit))
            (function-2
              (lambda (source/a.5 source/b.3)
                (invoke-1 source/body.12 (primitive/vector/3 source/rte.46 source/a.5 source/b.3))))))))))

(ref-set! source/gen-lambda-2 (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-2)))

(define source/gen-lambda-3 (ref (value-uninitialized)))

(define body/source/gen-lambda-3
  (lambda (source/body.13)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.47)
          (value-procedure
            (ref (unit))
            (function-3
              (lambda (source/a.6 source/b.4 source/c.2)
                (invoke-1
                  source/body.13
                  (primitive/vector/4 source/rte.47 source/a.6 source/b.4 source/c.2))))))))))

(ref-set! source/gen-lambda-3 (value-procedure (ref (unit)) (function-1 body/source/gen-lambda-3)))

(define source/gen-lambda-n (ref (value-uninitialized)))

(define body/source/gen-lambda-n
  (lambda (source/nb-vars.4 source/body.14)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.48)
          (value-procedure
            (ref (unit))
            (function-rest-3
              (lambda (source/a.7 source/b.5 source/c.3 source/d.1)
                ((lambda (source/x.11) (begin (primitive/vector-set!/3 source/x.11 (value-number (exact-number 0)) source/rte.48) (primitive/vector-set!/3 source/x.11 (value-number (exact-number 1)) source/a.7) (primitive/vector-set!/3 source/x.11 (value-number (exact-number 2)) source/b.5) (primitive/vector-set!/3 source/x.11 (value-number (exact-number 3)) source/c.3) (invoke-4 ((lambda () (let ((source/loop.4 #f) (body/source/loop.4 #f)) (set! source/loop.4 (ref (value-uninitialized))) (set! body/source/loop.4 (lambda (source/n.4 source/x.12 source/i.10 source/l.9) (if (value-truth? (primitive/<=/2 source/i.10 source/n.4)) (begin (primitive/vector-set!/3 source/x.12 source/i.10 (primitive/car/1 source/l.9)) (body/source/loop.4 source/n.4 source/x.12 (primitive/+/2 source/i.10 (value-number (exact-number 1))) (primitive/cdr/1 source/l.9))) (value-unspecified)))) (ref-set! source/loop.4 (value-procedure (ref (unit)) (function-4 body/source/loop.4))) (binding-value source/loop.4)))) source/nb-vars.4 source/x.11 (value-number (exact-number 4)) source/d.1) (invoke-1 source/body.14 source/x.11)))
                  (primitive/make-vector/1
                    (primitive/+/2 source/nb-vars.4 (value-number (exact-number 1)))))))))))))

(ref-set! source/gen-lambda-n (value-procedure (ref (unit)) (function-2 body/source/gen-lambda-n)))

(define source/gen-sequence (ref (value-uninitialized)))

(define body/source/gen-sequence
  (lambda (source/code1.3 source/code2.3)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.49)
          (begin (invoke-1 source/code1.3 source/rte.49) (invoke-1 source/code2.3 source/rte.49)))))))

(ref-set! source/gen-sequence (value-procedure (ref (unit)) (function-2 body/source/gen-sequence)))

(define source/gen-when (ref (value-uninitialized)))

(define body/source/gen-when
  (lambda (source/code1.4 source/code2.4)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.50)
          (if (value-truth? (invoke-1 source/code1.4 source/rte.50))
            (invoke-1 source/code2.4 source/rte.50)
            (value-null)))))))

(ref-set! source/gen-when (value-procedure (ref (unit)) (function-2 body/source/gen-when)))

(define source/gen-if (ref (value-uninitialized)))

(define body/source/gen-if
  (lambda (source/code1.5 source/code2.5 source/code3)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.51)
          (if (value-truth? (invoke-1 source/code1.5 source/rte.51))
            (invoke-1 source/code2.5 source/rte.51)
            (invoke-1 source/code3 source/rte.51)))))))

(ref-set! source/gen-if (value-procedure (ref (unit)) (function-3 body/source/gen-if)))

(define source/gen-cond-send (ref (value-uninitialized)))

(define body/source/gen-cond-send
  (lambda (source/code1.6 source/code2.6 source/code3.1)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.52)
          ((lambda (source/temp) (if (value-truth? source/temp) (invoke-1 (invoke-1 source/code2.6 source/rte.52) source/temp) (invoke-1 source/code3.1 source/rte.52)))
            (invoke-1 source/code1.6 source/rte.52)))))))

(ref-set!
  source/gen-cond-send
  (value-procedure (ref (unit)) (function-3 body/source/gen-cond-send)))

(define source/gen-and (ref (value-uninitialized)))

(define body/source/gen-and
  (lambda (source/code1.7 source/code2.7)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.53)
          ((lambda (source/temp.1) (if (value-truth? source/temp.1) (invoke-1 source/code2.7 source/rte.53) source/temp.1))
            (invoke-1 source/code1.7 source/rte.53)))))))

(ref-set! source/gen-and (value-procedure (ref (unit)) (function-2 body/source/gen-and)))

(define source/gen-or (ref (value-uninitialized)))

(define body/source/gen-or
  (lambda (source/code1.8 source/code2.8)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.54)
          ((lambda (source/temp.2) (if (value-truth? source/temp.2) source/temp.2 (invoke-1 source/code2.8 source/rte.54)))
            (invoke-1 source/code1.8 source/rte.54)))))))

(ref-set! source/gen-or (value-procedure (ref (unit)) (function-2 body/source/gen-or)))

(define source/gen-case (ref (value-uninitialized)))

(define body/source/gen-case
  (lambda (source/code1.9 source/code2.9)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.55)
          (invoke-2 source/code2.9 source/rte.55 (invoke-1 source/code1.9 source/rte.55)))))))

(ref-set! source/gen-case (value-procedure (ref (unit)) (function-2 body/source/gen-case)))

(define source/gen-case-clause (ref (value-uninitialized)))

(define body/source/gen-case-clause
  (lambda (source/datums source/code1.10 source/code2.10)
    (value-procedure
      (ref (unit))
      (function-2
        (lambda (source/rte.56 source/key)
          (if (value-truth? (primitive/memv/2 source/key source/datums))
            (invoke-1 source/code1.10 source/rte.56)
            (invoke-2 source/code2.10 source/rte.56 source/key)))))))

(ref-set!
  source/gen-case-clause
  (value-procedure (ref (unit)) (function-3 body/source/gen-case-clause)))

(define source/gen-case-else (ref (value-uninitialized)))

(define body/source/gen-case-else
  (lambda (source/code.13)
    (value-procedure
      (ref (unit))
      (function-2 (lambda (source/rte.57 source/key.1) (invoke-1 source/code.13 source/rte.57))))))

(ref-set!
  source/gen-case-else
  (value-procedure (ref (unit)) (function-1 body/source/gen-case-else)))

(define source/gen-letrec (ref (value-uninitialized)))

(define body/source/gen-letrec
  (lambda (source/vals.3 source/body.15)
    ((lambda (source/nb-vals) ((lambda (source/value.50) (if (value-truth? (primitive/memv/2 source/value.50 literal.70)) (body/source/gen-letrec-1 (primitive/car/1 source/vals.3) source/body.15) ((lambda (source/value.51) (if (value-truth? (primitive/memv/2 source/value.51 literal.69)) (body/source/gen-letrec-2 (primitive/car/1 source/vals.3) (primitive/cadr/1 source/vals.3) source/body.15) ((lambda (source/value.52) (if (value-truth? (primitive/memv/2 source/value.52 literal.68)) (body/source/gen-letrec-3 (primitive/car/1 source/vals.3) (primitive/cadr/1 source/vals.3) (primitive/caddr/1 source/vals.3) source/body.15) ((lambda (source/value.53) (body/source/gen-letrec-n source/nb-vals source/vals.3 source/body.15)) source/value.52))) source/value.51))) source/value.50))) source/nb-vals))
      (primitive/length/1 source/vals.3))))

(ref-set! source/gen-letrec (value-procedure (ref (unit)) (function-2 body/source/gen-letrec)))

(define source/gen-letrec-1 (ref (value-uninitialized)))

(define body/source/gen-letrec-1
  (lambda (source/val1 source/body.16)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.58)
          ((lambda (source/x.13) (begin (primitive/vector-set!/3 source/x.13 (value-number (exact-number 1)) (invoke-1 source/val1 source/x.13)) (invoke-1 source/body.16 source/x.13)))
            (primitive/vector/2 source/rte.58 (value-boolean #f))))))))

(ref-set! source/gen-letrec-1 (value-procedure (ref (unit)) (function-2 body/source/gen-letrec-1)))

(define source/gen-letrec-2 (ref (value-uninitialized)))

(define body/source/gen-letrec-2
  (lambda (source/val1.1 source/val2 source/body.17)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.59)
          ((lambda (source/x.14) (begin (primitive/vector-set!/3 source/x.14 (value-number (exact-number 1)) (invoke-1 source/val1.1 source/x.14)) (primitive/vector-set!/3 source/x.14 (value-number (exact-number 2)) (invoke-1 source/val2 source/x.14)) (invoke-1 source/body.17 source/x.14)))
            (primitive/vector/3 source/rte.59 (value-boolean #f) (value-boolean #f))))))))

(ref-set! source/gen-letrec-2 (value-procedure (ref (unit)) (function-3 body/source/gen-letrec-2)))

(define source/gen-letrec-3 (ref (value-uninitialized)))

(define body/source/gen-letrec-3
  (lambda (source/val1.2 source/val2.1 source/val3 source/body.18)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.60)
          ((lambda (source/x.15) (begin (primitive/vector-set!/3 source/x.15 (value-number (exact-number 1)) (invoke-1 source/val1.2 source/x.15)) (primitive/vector-set!/3 source/x.15 (value-number (exact-number 2)) (invoke-1 source/val2.1 source/x.15)) (primitive/vector-set!/3 source/x.15 (value-number (exact-number 3)) (invoke-1 source/val3 source/x.15)) (invoke-1 source/body.18 source/x.15)))
            (primitive/vector/4
              source/rte.60
              (value-boolean #f)
              (value-boolean #f)
              (value-boolean #f))))))))

(ref-set! source/gen-letrec-3 (value-procedure (ref (unit)) (function-4 body/source/gen-letrec-3)))

(define source/gen-letrec-n (ref (value-uninitialized)))

(define body/source/gen-letrec-n
  (lambda (source/nb-vals.1 source/vals.4 source/body.19)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.61)
          ((lambda (source/x.16) (begin (primitive/vector-set!/3 source/x.16 (value-number (exact-number 0)) source/rte.61) (invoke-3 ((lambda () (let ((source/loop.5 #f) (body/source/loop.5 #f)) (set! source/loop.5 (ref (value-uninitialized))) (set! body/source/loop.5 (lambda (source/x.17 source/i.11 source/l.10) (if (value-truth? (primitive/pair?/1 source/l.10)) (begin (primitive/vector-set!/3 source/x.17 source/i.11 (invoke-1 (primitive/car/1 source/l.10) source/x.17)) (body/source/loop.5 source/x.17 (primitive/+/2 source/i.11 (value-number (exact-number 1))) (primitive/cdr/1 source/l.10))) (value-unspecified)))) (ref-set! source/loop.5 (value-procedure (ref (unit)) (function-3 body/source/loop.5))) (binding-value source/loop.5)))) source/x.16 (value-number (exact-number 1)) source/vals.4) (invoke-1 source/body.19 source/x.16)))
            (primitive/make-vector/1
              (primitive/+/2 source/nb-vals.1 (value-number (exact-number 1))))))))))

(ref-set! source/gen-letrec-n (value-procedure (ref (unit)) (function-3 body/source/gen-letrec-n)))

(define source/gen-macro (ref (value-uninitialized)))

(define body/source/gen-macro
  (lambda (source/name.6 source/proc.3)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.62) (body/source/scheme-add-macro source/name.6 source/proc.3))))))

(ref-set! source/gen-macro (value-procedure (ref (unit)) (function-2 body/source/gen-macro)))

(define source/gen-combination (ref (value-uninitialized)))

(define body/source/gen-combination
  (lambda (source/oper source/args.1)
    ((lambda (source/value.54) (if (value-truth? (primitive/memv/2 source/value.54 literal.74)) (body/source/gen-combination-0 source/oper) ((lambda (source/value.55) (if (value-truth? (primitive/memv/2 source/value.55 literal.73)) (body/source/gen-combination-1 source/oper (primitive/car/1 source/args.1)) ((lambda (source/value.56) (if (value-truth? (primitive/memv/2 source/value.56 literal.72)) (body/source/gen-combination-2 source/oper (primitive/car/1 source/args.1) (primitive/cadr/1 source/args.1)) ((lambda (source/value.57) (if (value-truth? (primitive/memv/2 source/value.57 literal.71)) (body/source/gen-combination-3 source/oper (primitive/car/1 source/args.1) (primitive/cadr/1 source/args.1) (primitive/caddr/1 source/args.1)) ((lambda (source/value.58) (body/source/gen-combination-n source/oper source/args.1)) source/value.57))) source/value.56))) source/value.55))) source/value.54)))
      (primitive/length/1 source/args.1))))

(ref-set!
  source/gen-combination
  (value-procedure (ref (unit)) (function-2 body/source/gen-combination)))

(define source/gen-combination-0 (ref (value-uninitialized)))

(define body/source/gen-combination-0
  (lambda (source/oper.1)
    (value-procedure
      (ref (unit))
      (function-1 (lambda (source/rte.63) (invoke-0 (invoke-1 source/oper.1 source/rte.63)))))))

(ref-set!
  source/gen-combination-0
  (value-procedure (ref (unit)) (function-1 body/source/gen-combination-0)))

(define source/gen-combination-1 (ref (value-uninitialized)))

(define body/source/gen-combination-1
  (lambda (source/oper.2 source/arg1)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.64)
          (invoke-1 (invoke-1 source/oper.2 source/rte.64) (invoke-1 source/arg1 source/rte.64)))))))

(ref-set!
  source/gen-combination-1
  (value-procedure (ref (unit)) (function-2 body/source/gen-combination-1)))

(define source/gen-combination-2 (ref (value-uninitialized)))

(define body/source/gen-combination-2
  (lambda (source/oper.3 source/arg1.1 source/arg2)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.65)
          (invoke-2
            (invoke-1 source/oper.3 source/rte.65)
            (invoke-1 source/arg1.1 source/rte.65)
            (invoke-1 source/arg2 source/rte.65)))))))

(ref-set!
  source/gen-combination-2
  (value-procedure (ref (unit)) (function-3 body/source/gen-combination-2)))

(define source/gen-combination-3 (ref (value-uninitialized)))

(define body/source/gen-combination-3
  (lambda (source/oper.4 source/arg1.2 source/arg2.1 source/arg3)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.66)
          (invoke-3
            (invoke-1 source/oper.4 source/rte.66)
            (invoke-1 source/arg1.2 source/rte.66)
            (invoke-1 source/arg2.1 source/rte.66)
            (invoke-1 source/arg3 source/rte.66)))))))

(ref-set!
  source/gen-combination-3
  (value-procedure (ref (unit)) (function-4 body/source/gen-combination-3)))

(define source/gen-combination-n (ref (value-uninitialized)))

(define body/source/gen-combination-n
  (lambda (source/oper.5 source/args.2)
    (value-procedure
      (ref (unit))
      (function-1
        (lambda (source/rte.67)
          (let ((source/evaluate #f) (body/source/evaluate #f))
            (set! source/evaluate (ref (value-uninitialized)))
            (set!
              body/source/evaluate
              (lambda (source/l.11 source/rte.68)
                (if (value-truth? (primitive/pair?/1 source/l.11))
                  (primitive/cons/2
                    (invoke-1 (primitive/car/1 source/l.11) source/rte.68)
                    (body/source/evaluate (primitive/cdr/1 source/l.11) source/rte.68))
                  (value-null))))
            (ref-set!
              source/evaluate
              (value-procedure (ref (unit)) (function-2 body/source/evaluate)))
            (primitive/apply/2
              (invoke-1 source/oper.5 source/rte.67)
              (body/source/evaluate source/args.2 source/rte.67))))))))

(ref-set!
  source/gen-combination-n
  (value-procedure (ref (unit)) (function-2 body/source/gen-combination-n)))

(define source/scheme-comp (ref (value-uninitialized)))

(define body/source/scheme-comp
  (lambda (source/expr.26 source/env.40)
    (if (value-truth? (primitive/symbol?/1 source/expr.26))
      (body/source/comp-var source/expr.26 source/env.40)
      (if (value-truth? (primitive/not/1 (primitive/pair?/1 source/expr.26)))
        (body/source/comp-self-eval source/expr.26 source/env.40)
        (if (value-truth? (body/source/macro? (primitive/car/1 source/expr.26) source/env.40))
          (body/source/scheme-comp
            (body/source/macro-expand source/expr.26 source/env.40)
            source/env.40)
          (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.92))
            (body/source/comp-quote source/expr.26 source/env.40)
            (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.91))
              (body/source/comp-quasiquote source/expr.26 source/env.40)
              (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.90))
                (body/source/comp-unquote source/expr.26 source/env.40)
                (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.89))
                  (body/source/comp-unquote-splicing source/expr.26 source/env.40)
                  (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.88))
                    (body/source/comp-set! source/expr.26 source/env.40)
                    (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.87))
                      (body/source/comp-lambda source/expr.26 source/env.40)
                      (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.86))
                        (body/source/comp-if source/expr.26 source/env.40)
                        (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.85))
                          (body/source/comp-cond source/expr.26 source/env.40)
                          (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.84))
                            (body/source/comp-and source/expr.26 source/env.40)
                            (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.83))
                              (body/source/comp-or source/expr.26 source/env.40)
                              (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.82))
                                (body/source/comp-case source/expr.26 source/env.40)
                                (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.81))
                                  (body/source/comp-let source/expr.26 source/env.40)
                                  (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.80))
                                    (body/source/comp-let* source/expr.26 source/env.40)
                                    (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.79))
                                      (body/source/comp-letrec source/expr.26 source/env.40)
                                      (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.78))
                                        (body/source/comp-begin source/expr.26 source/env.40)
                                        (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.77))
                                          (body/source/comp-do source/expr.26 source/env.40)
                                          (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.76))
                                            (body/source/comp-define source/expr.26 source/env.40)
                                            (if (value-truth? (primitive/eq?/2 (primitive/car/1 source/expr.26) literal.75))
                                              (body/source/comp-define-macro
                                                source/expr.26
                                                source/env.40)
                                              (body/source/comp-combination
                                                source/expr.26
                                                source/env.40))))))))))))))))))))))))

(ref-set! source/scheme-comp (value-procedure (ref (unit)) (function-2 body/source/scheme-comp)))

(define source/scheme-global-var (ref (value-uninitialized)))

(define body/source/scheme-global-var
  (lambda (source/name.7)
    ((lambda (source/x.18) (if (value-truth? source/x.18) source/x.18 ((lambda (source/y.1) (begin (begin (ref-set! source/scheme-global-variables (primitive/cons/2 source/y.1 (binding-value source/scheme-global-variables))) (value-unspecified)) source/y.1)) (primitive/cons/2 source/name.7 (value-null)))))
      (primitive/assq/2 source/name.7 (binding-value source/scheme-global-variables)))))

(ref-set!
  source/scheme-global-var
  (value-procedure (ref (unit)) (function-1 body/source/scheme-global-var)))

(define source/scheme-global-var-ref (ref (value-uninitialized)))

(define body/source/scheme-global-var-ref (lambda (source/i.12) (primitive/cdr/1 source/i.12)))

(ref-set!
  source/scheme-global-var-ref
  (value-procedure (ref (unit)) (function-1 body/source/scheme-global-var-ref)))

(define source/scheme-global-var-set! (ref (value-uninitialized)))

(define body/source/scheme-global-var-set!
  (lambda (source/i.13 source/val.1)
    (begin (primitive/set-cdr!/2 source/i.13 source/val.1) (value-null))))

(ref-set!
  source/scheme-global-var-set!
  (value-procedure (ref (unit)) (function-2 body/source/scheme-global-var-set!)))

(define source/scheme-global-variables (ref (value-uninitialized)))

(ref-set! source/scheme-global-variables (value-null))

(define source/def-proc (ref (value-uninitialized)))

(define body/source/def-proc
  (lambda (source/name.8 source/value.59)
    (body/source/scheme-global-var-set!
      (body/source/scheme-global-var source/name.8)
      source/value.59)))

(ref-set! source/def-proc (value-procedure (ref (unit)) (function-2 body/source/def-proc)))

(body/source/def-proc
  literal.93
  (value-procedure (ref (unit)) (function-1 (lambda (source/x.19) (primitive/not/1 source/x.19)))))

(body/source/def-proc literal.94 primitive-value/boolean?)

(body/source/def-proc literal.95 primitive-value/eqv?)

(body/source/def-proc literal.96 primitive-value/eq?)

(body/source/def-proc literal.97 primitive-value/equal?)

(body/source/def-proc
  literal.98
  (value-procedure (ref (unit)) (function-1 (lambda (source/obj) (primitive/pair?/1 source/obj)))))

(body/source/def-proc
  literal.99
  (value-procedure
    (ref (unit))
    (function-2 (lambda (source/x.20 source/y.2) (primitive/cons/2 source/x.20 source/y.2)))))

(body/source/def-proc
  literal.100
  (value-procedure (ref (unit)) (function-1 (lambda (source/x.21) (primitive/car/1 source/x.21)))))

(body/source/def-proc
  literal.101
  (value-procedure (ref (unit)) (function-1 (lambda (source/x.22) (primitive/cdr/1 source/x.22)))))

(body/source/def-proc literal.102 primitive-value/set-car!)

(body/source/def-proc literal.103 primitive-value/set-cdr!)

(body/source/def-proc literal.104 primitive-value/caar)

(body/source/def-proc literal.105 primitive-value/cadr)

(body/source/def-proc literal.106 primitive-value/cdar)

(body/source/def-proc literal.107 primitive-value/cddr)

(body/source/def-proc literal.108 primitive-value/caaar)

(body/source/def-proc literal.109 primitive-value/caadr)

(body/source/def-proc literal.110 primitive-value/cadar)

(body/source/def-proc literal.111 primitive-value/caddr)

(body/source/def-proc literal.112 primitive-value/cdaar)

(body/source/def-proc literal.113 primitive-value/cdadr)

(body/source/def-proc literal.114 primitive-value/cddar)

(body/source/def-proc literal.115 primitive-value/cdddr)

(body/source/def-proc literal.116 primitive-value/caaaar)

(body/source/def-proc literal.117 primitive-value/caaadr)

(body/source/def-proc literal.118 primitive-value/caadar)

(body/source/def-proc literal.119 primitive-value/caaddr)

(body/source/def-proc literal.120 primitive-value/cadaar)

(body/source/def-proc literal.121 primitive-value/cadadr)

(body/source/def-proc literal.122 primitive-value/caddar)

(body/source/def-proc literal.123 primitive-value/cadddr)

(body/source/def-proc literal.124 primitive-value/cdaaar)

(body/source/def-proc literal.125 primitive-value/cdaadr)

(body/source/def-proc literal.126 primitive-value/cdadar)

(body/source/def-proc literal.127 primitive-value/cdaddr)

(body/source/def-proc literal.128 primitive-value/cddaar)

(body/source/def-proc literal.129 primitive-value/cddadr)

(body/source/def-proc literal.130 primitive-value/cdddar)

(body/source/def-proc literal.131 primitive-value/cddddr)

(body/source/def-proc
  literal.132
  (value-procedure (ref (unit)) (function-1 (lambda (source/x.23) (primitive/null?/1 source/x.23)))))

(body/source/def-proc literal.133 primitive-value/list?)

(body/source/def-proc literal.134 primitive-value/list)

(body/source/def-proc literal.135 primitive-value/length)

(body/source/def-proc literal.136 primitive-value/append)

(body/source/def-proc literal.137 primitive-value/reverse)

(body/source/def-proc literal.138 primitive-value/list-ref)

(body/source/def-proc literal.139 primitive-value/memq)

(body/source/def-proc literal.140 primitive-value/memv)

(body/source/def-proc literal.141 primitive-value/member)

(body/source/def-proc literal.142 primitive-value/assq)

(body/source/def-proc literal.143 primitive-value/assv)

(body/source/def-proc literal.144 primitive-value/assoc)

(body/source/def-proc literal.145 primitive-value/symbol?)

(body/source/def-proc literal.146 primitive-value/symbol->string)

(body/source/def-proc literal.147 primitive-value/string->symbol)

(body/source/def-proc literal.148 primitive-value/number?)

(body/source/def-proc literal.149 primitive-value/complex?)

(body/source/def-proc literal.150 primitive-value/real?)

(body/source/def-proc literal.151 primitive-value/rational?)

(body/source/def-proc literal.152 primitive-value/integer?)

(body/source/def-proc literal.153 primitive-value/exact?)

(body/source/def-proc literal.154 primitive-value/inexact?)

(body/source/def-proc literal.155 primitive-value/max)

(body/source/def-proc literal.156 primitive-value/min)

(body/source/def-proc literal.157 primitive-value//)

(body/source/def-proc literal.158 primitive-value/abs)

(body/source/def-proc literal.159 primitive-value/gcd)

(body/source/def-proc literal.160 primitive-value/lcm)

(body/source/def-proc literal.161 primitive-value/floor)

(body/source/def-proc literal.162 primitive-value/ceiling)

(body/source/def-proc literal.163 primitive-value/truncate)

(body/source/def-proc literal.164 primitive-value/round)

(body/source/def-proc literal.165 primitive-value/exp)

(body/source/def-proc literal.166 primitive-value/log)

(body/source/def-proc literal.167 primitive-value/sin)

(body/source/def-proc literal.168 primitive-value/cos)

(body/source/def-proc literal.169 primitive-value/tan)

(body/source/def-proc literal.170 primitive-value/asin)

(body/source/def-proc literal.171 primitive-value/acos)

(body/source/def-proc literal.172 primitive-value/atan)

(body/source/def-proc literal.173 primitive-value/sqrt)

(body/source/def-proc literal.174 primitive-value/expt)

(body/source/def-proc literal.175 primitive-value/inexact)

(body/source/def-proc literal.176 primitive-value/exact)

(body/source/def-proc literal.177 primitive-value/number->string)

(body/source/def-proc literal.178 primitive-value/string->number)

(body/source/def-proc literal.179 primitive-value/char?)

(body/source/def-proc literal.180 primitive-value/char=?)

(body/source/def-proc literal.181 primitive-value/char<?)

(body/source/def-proc literal.182 primitive-value/char>?)

(body/source/def-proc literal.183 primitive-value/char<=?)

(body/source/def-proc literal.184 primitive-value/char>=?)

(body/source/def-proc literal.185 primitive-value/char-ci=?)

(body/source/def-proc literal.186 primitive-value/char-ci<?)

(body/source/def-proc literal.187 primitive-value/char-ci>?)

(body/source/def-proc literal.188 primitive-value/char-ci<=?)

(body/source/def-proc literal.189 primitive-value/char-ci>=?)

(body/source/def-proc literal.190 primitive-value/char-alphabetic?)

(body/source/def-proc literal.191 primitive-value/char-numeric?)

(body/source/def-proc literal.192 primitive-value/char-whitespace?)

(body/source/def-proc literal.193 primitive-value/char-lower-case?)

(body/source/def-proc literal.194 primitive-value/char->integer)

(body/source/def-proc literal.195 primitive-value/integer->char)

(body/source/def-proc literal.196 primitive-value/char-upcase)

(body/source/def-proc literal.197 primitive-value/char-downcase)

(body/source/def-proc literal.198 primitive-value/string?)

(body/source/def-proc literal.199 primitive-value/make-string)

(body/source/def-proc literal.200 primitive-value/string)

(body/source/def-proc literal.201 primitive-value/string-length)

(body/source/def-proc literal.202 primitive-value/string-ref)

(body/source/def-proc literal.203 primitive-value/string-set!)

(body/source/def-proc literal.204 primitive-value/string=?)

(body/source/def-proc literal.205 primitive-value/string<?)

(body/source/def-proc literal.206 primitive-value/string>?)

(body/source/def-proc literal.207 primitive-value/string<=?)

(body/source/def-proc literal.208 primitive-value/string>=?)

(body/source/def-proc literal.209 primitive-value/string-ci=?)

(body/source/def-proc literal.210 primitive-value/string-ci<?)

(body/source/def-proc literal.211 primitive-value/string-ci>?)

(body/source/def-proc literal.212 primitive-value/string-ci<=?)

(body/source/def-proc literal.213 primitive-value/string-ci>=?)

(body/source/def-proc literal.214 primitive-value/substring)

(body/source/def-proc literal.215 primitive-value/string-append)

(body/source/def-proc literal.216 primitive-value/vector?)

(body/source/def-proc literal.217 primitive-value/make-vector)

(body/source/def-proc literal.218 primitive-value/vector)

(body/source/def-proc literal.219 primitive-value/vector-length)

(body/source/def-proc literal.220 primitive-value/vector-ref)

(body/source/def-proc literal.221 primitive-value/vector-set!)

(body/source/def-proc literal.222 primitive-value/procedure?)

(body/source/def-proc literal.223 primitive-value/apply)

(body/source/def-proc literal.224 primitive-value/map)

(body/source/def-proc literal.225 primitive-value/for-each)

(body/source/def-proc literal.226 primitive-value/call-with-input-file)

(body/source/def-proc literal.227 primitive-value/call-with-output-file)

(body/source/def-proc literal.228 primitive-value/input-port?)

(body/source/def-proc literal.229 primitive-value/output-port?)

(body/source/def-proc literal.230 primitive-value/current-input-port)

(body/source/def-proc literal.231 primitive-value/current-output-port)

(body/source/def-proc literal.232 primitive-value/open-input-file)

(body/source/def-proc literal.233 primitive-value/open-output-file)

(body/source/def-proc literal.234 primitive-value/close-input-port)

(body/source/def-proc literal.235 primitive-value/close-output-port)

(body/source/def-proc literal.236 primitive-value/eof-object?)

(body/source/def-proc literal.237 primitive-value/read)

(body/source/def-proc literal.238 primitive-value/read-char)

(body/source/def-proc literal.239 primitive-value/peek-char)

(body/source/def-proc literal.240 primitive-value/write)

(body/source/def-proc literal.241 primitive-value/display)

(body/source/def-proc literal.242 primitive-value/newline)

(body/source/def-proc literal.243 primitive-value/write-char)

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
              (body/source/scheme-eval
                (if (barrier) (specification-input configured) (unreachable))))
            (if (value-equal? result (specification-expected configured)) 1 0))))
      (repeat 0 (value-boolean #f)))))

(unit)

(define observe
  (lambda ()
    (call-with-input-file
      "probes.scm"
      (lambda (port)
        (let ((loop #f))
          (set!
            loop
            (lambda (index)
              (let ((next (read-source-value port)))
                (if (value-eof? next)
                  index
                  (let ((actual (body/source/scheme-eval (value-car next))))
                    (if (value-equal? actual (value-car (value-cdr next)))
                      (loop (+ index 1))
                      (begin
                        (write
                          (value->datum
                            (value-cons
                              (value-number (exact-number index))
                              (value-cons actual (value-null)))))
                        (newline)
                        (datum-fail "interpreter diagnostic mismatch"))))))))
          (loop 0))))))

;; ---- The canonical count and original predicate govern the control ----
(define (monotonic-nanoseconds)
 (let ((now (current-time 'time-monotonic))) (+ (* (time-second now) 1000000000) (time-nanosecond now))))
(let* ((count (configured-count)) (start (monotonic-nanoseconds)) (result (bench count))
       (seconds (inexact (/ (- (monotonic-nanoseconds) start) 1000000000))))
 (unless (= result 1) (error 'scheme "incorrect result" result))
 (display "+!CSVLINE!+chez-adapted,scheme:") (display count) (display ",") (write seconds) (newline))
