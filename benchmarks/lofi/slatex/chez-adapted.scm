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
    (fields (immutable body function-rest-1-body))))

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
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            14
            (debug-source-stack)
            (if (host:record? matched-value.14)
              (host:record-type-name (host:record-rtd matched-value.14))
              "nonrecord")))))))

(define read-source-value
  (lambda (port)
    (let ((matched-value.16 (read port)))
      (cond
        ((is-read-end matched-value.16) (let () (value-eof)))
        ((is-read-error matched-value.16)
          (let ((message (read-error-message matched-value.16))) (datum-fail message)))
        ((is-read-value matched-value.16)
          (let ((datum (read-value-datum matched-value.16))) (datum->value datum)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            16
            (debug-source-stack)
            (if (host:record? matched-value.16)
              (host:record-type-name (host:record-rtd matched-value.16))
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

(define primitive/>/2
  (lambda (a0 a1) (value-boolean (number>? (value-number-number a0) (value-number-number a1)))))

(define primitive/>=/2
  (lambda (a0 a1) (value-boolean (number>=? (value-number-number a0) (value-number-number a1)))))

(define primitive/append/2 (lambda (a0 a1) (value-append a0 a1)))

(define primitive/apply/2 (lambda (a0 a1) (invoke-list a0 a1)))

(define primitive/apply/4
  (lambda (a0 a1 a2 a3) (invoke-list a0 (value-cons a1 (value-cons a2 a3)))))

(define primitive/apply/5
  (lambda (a0 a1 a2 a3 a4) (invoke-list a0 (value-cons a1 (value-cons a2 (value-cons a3 a4))))))

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

(define primitive/cdr/1 (lambda (a0) (value-cdr a0)))

(define primitive/char-alphabetic?/1
  (lambda (a0) (value-boolean (char-alphabetic? (value-character-character a0)))))

(define primitive/char-whitespace?/1
  (lambda (a0) (value-boolean (char-whitespace? (value-character-character a0)))))

(define primitive/char=?/2
  (lambda (a0 a1)
    (value-boolean (char=? (value-character-character a0) (value-character-character a1)))))

(define primitive/char?/1 (lambda (a0) (value-boolean (value-character? a0))))

(define primitive/cons/2 (lambda (a0 a1) (value-cons a0 a1)))

(define primitive/delete-file/1
  (lambda (a0) (begin (delete-file (value-string-string a0)) (value-unspecified))))

(define primitive/display/1 (lambda (a0) (begin (display (value->datum a0)) (value-unspecified))))

(define primitive/display/2
  (lambda (a0 a1) (begin (display (value->datum a0) (value-output-port a1)) (value-unspecified))))

(define primitive/eof-object?/1 (lambda (a0) (value-boolean (value-eof? a0))))

(define primitive/eq?/2 (lambda (a0 a1) (value-boolean (value-eq? a0 a1))))

(define primitive/equal?/2 (lambda (a0 a1) (value-boolean (value-equal? a0 a1))))

(define primitive/eqv?/2 (lambda (a0 a1) (value-boolean (value-eq? a0 a1))))

(define primitive/error/2
  (lambda (a0 a1) (value-error (value-cons a0 (value-cons a1 (value-null))))))

(define primitive/file-exists?/1
  (lambda (a0) (value-boolean (file-exists? (value-string-string a0)))))

(define primitive/for-each/2
  (lambda (a0 a1)
    (if (value-null? a1)
      (value-unspecified)
      (begin (invoke-1 a0 (value-car a1)) (primitive/for-each/2 a0 (value-cdr a1))))))

(define primitive/integer->char/1
  (lambda (a0)
    (value-character (integer->char (integer->i64 (number->integer (value-number-number a0)))))))

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

(define primitive/list/10
  (lambda (a0 a1 a2 a3 a4 a5 a6 a7 a8 a9)
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
                (value-cons a6 (value-cons a7 (value-cons a8 (value-cons a9 (value-null)))))))))))))

(define primitive/list/14
  (lambda (a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13)
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
                          (value-cons a11 (value-cons a12 (value-cons a13 (value-null)))))))))))))))))

(define primitive/list->string/1 (lambda (a0) (value-string (list->string (value-characters a0)))))

(define primitive/list-tail/2
  (lambda (a0 a1) (value-tail a0 (integer->i64 (number->integer (value-number-number a1))))))

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

(define primitive/map/2
  (lambda (a0 a1)
    (if (value-null? a1)
      (value-null)
      (let ((first (invoke-1 a0 (value-car a1))))
        (value-cons first (primitive/map/2 a0 (value-cdr a1)))))))

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

(define primitive/peek-char/1
  (lambda (a0)
    (let ((matched-value.18 (peek-char (value-input-port a0))))
      (cond
        ((is-character-end matched-value.18) (let () (value-eof)))
        ((is-character-value matched-value.18)
          (let ((c (character-value-character matched-value.18))) (value-character c)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            18
            (debug-source-stack)
            (if (host:record? matched-value.18)
              (host:record-type-name (host:record-rtd matched-value.18))
              "nonrecord")))))))

(define primitive/read-char/1
  (lambda (a0)
    (let ((matched-value.20 (read-char (value-input-port a0))))
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

(define primitive/set-car!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-first a0) a1) (value-unspecified))))

(define primitive/set-cdr!/2
  (lambda (a0 a1) (begin (ref-set! (value-pair-rest a0) a1) (value-unspecified))))

(define primitive/string/1 (lambda (a0) (value-string (string (value-character-character a0)))))

(define primitive/string/2
  (lambda (a0 a1)
    (value-string (string (value-character-character a0) (value-character-character a1)))))

(define primitive/string/4
  (lambda (a0 a1 a2 a3)
    (value-string
      (string
        (value-character-character a0)
        (value-character-character a1)
        (value-character-character a2)
        (value-character-character a3)))))

(define primitive/string->list/1
  (lambda (a0) (native->values (value-wrap-characters (string->list (value-string-string a0))))))

(define primitive/string->number/1
  (lambda (a0) (parsed-number->value (string->number (value-string-string a0)))))

(define primitive/string-append/2
  (lambda (a0 a1) (value-string (string-append (value-string-string a0) (value-string-string a1)))))

(define primitive/string-append/3
  (lambda (a0 a1 a2)
    (value-string
      (string-append (value-string-string a0) (value-string-string a1) (value-string-string a2)))))

(define primitive/string-ci=?/2
  (lambda (a0 a1)
    (value-boolean
      (=
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

(define primitive/string=?/2
  (lambda (a0 a1)
    (value-boolean
      (= (value-compare-strings (value-string-string a0) (value-string-string a1) 0) 0))))

(define primitive/substring/3
  (lambda (a0 a1 a2)
    (value-string
      (substring
        (value-string-string a0)
        (integer->i64 (number->integer (value-number-number a1)))
        (integer->i64 (number->integer (value-number-number a2)))))))

(define primitive/symbol->string/1
  (lambda (a0) (value-string (symbol->string (value-symbol-symbol a0)))))

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

(define primitive/write/1 (lambda (a0) (begin (write (value->datum a0)) (value-unspecified))))

(define primitive-value/member (value-procedure (ref (unit)) (function-2 primitive/member/2)))

(define primitive-value/string-ci=?
  (value-procedure (ref (unit)) (function-2 primitive/string-ci=?/2)))

(define primitive-value/string=? (value-procedure (ref (unit)) (function-2 primitive/string=?/2)))

(define primitive-value/symbol->string
  (value-procedure (ref (unit)) (function-1 primitive/symbol->string/1)))

(define primitive-rest/string-append (lambda (remaining) (value-join-strings remaining)))

(define primitive-value/string-append
  (value-procedure (ref (unit)) (function-rest-0 primitive-rest/string-append)))

(define primitive-rest/display
  (lambda (a0 remaining)
    (if (value-null? remaining)
      (primitive/display/1 a0)
      (if (value-null? (value-cdr remaining))
        (primitive/display/2 a0 (value-car remaining))
        (datum-fail "primitive argument count mismatch")))))

(define primitive-value/display
  (value-procedure (ref (unit)) (function-rest-1 primitive-rest/display)))

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
    (let ((matched-value.22 (value-procedure-procedure procedure)))
      (cond
        ((is-function-0 matched-value.22)
          (let ((body (function-0-body matched-value.22)))
            (if (value-null? arguments) (body) (datum-fail "procedure argument count mismatch"))))
        ((is-function-1 matched-value.22)
          (let ((body (function-1-body matched-value.22)))
            (if (value-null? (value-cdr arguments))
              (body (value-car arguments))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-2 matched-value.22)
          (let ((body (function-2-body matched-value.22)))
            (if (value-null? (value-cdr (value-cdr arguments)))
              (body (value-car arguments) (value-car (value-cdr arguments)))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-3 matched-value.22)
          (let ((body (function-3-body matched-value.22)))
            (if (value-null? (value-cdr (value-cdr (value-cdr arguments))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-4 matched-value.22)
          (let ((body (function-4-body matched-value.22)))
            (if (value-null? (value-cdr (value-cdr (value-cdr (value-cdr arguments)))))
              (body
                (value-car arguments)
                (value-car (value-cdr arguments))
                (value-car (value-cdr (value-cdr arguments)))
                (value-car (value-cdr (value-cdr (value-cdr arguments)))))
              (datum-fail "procedure argument count mismatch"))))
        ((is-function-rest-0 matched-value.22)
          (let ((body (function-rest-0-body matched-value.22))) (body arguments)))
        ((is-function-rest-1 matched-value.22)
          (let ((body (function-rest-1-body matched-value.22)))
            (body (value-car arguments) (value-cdr arguments))))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            22
            (debug-source-stack)
            (if (host:record? matched-value.22)
              (host:record-type-name (host:record-rtd matched-value.22))
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
    (let ((matched-value.24 result))
      (cond
        ((is-not-a-number matched-value.24) (let () (value-boolean #f)))
        ((is-parsed-number matched-value.24)
          (let ((number (parsed-number-value matched-value.24))) (value-number number)))
        ((is-number-error matched-value.24)
          (let ((message (number-error-text matched-value.24))) (datum-fail message)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            24
            (debug-source-stack)
            (if (host:record? matched-value.24)
              (host:record-type-name (host:record-rtd matched-value.24))
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
    (let ((matched-value.26 source))
      (cond
        ((is-value-null matched-value.26) (let () (datum-null)))
        ((is-value-boolean matched-value.26)
          (let ((x (value-boolean-boolean matched-value.26))) (datum-boolean x)))
        ((is-value-character matched-value.26)
          (let ((x (value-character-character matched-value.26))) (datum-character x)))
        ((is-value-string matched-value.26)
          (let ((x (value-string-string matched-value.26))) (datum-string x)))
        ((is-value-symbol matched-value.26)
          (let ((x (value-symbol-symbol matched-value.26))) (datum-symbol x)))
        ((is-value-number matched-value.26)
          (let ((x (value-number-number matched-value.26))) (datum-number x)))
        ((is-value-bytevector matched-value.26)
          (let ((x (value-bytevector-bytes matched-value.26))) (datum-bytevector x)))
        ((is-value-pair matched-value.26)
          (let ((first (value-pair-first matched-value.26)) (rest (value-pair-rest matched-value.26)))
            (outward-mutable source seen)))
        ((is-value-vector matched-value.26)
          (let ((vector (value-vector-vector matched-value.26))) (outward-mutable source seen)))
        ((is-value-input matched-value.26)
          (let ((identity (value-input-identity matched-value.26)) (port (value-input-port matched-value.26)))
            (datum-symbol (string->symbol "#<input-port>"))))
        ((is-value-output matched-value.26)
          (let ((port (value-output-port matched-value.26)))
            (datum-symbol (string->symbol "#<output-port>"))))
        ((is-value-procedure matched-value.26)
          (let ((identity (value-procedure-identity matched-value.26)) (procedure (value-procedure-procedure matched-value.26)))
            (datum-symbol (string->symbol "#<procedure>"))))
        ((is-value-eof matched-value.26) (let () (datum-symbol (string->symbol "#<eof>"))))
        ((is-value-unspecified matched-value.26)
          (let () (datum-symbol (string->symbol "#<unspecified>"))))
        ((is-value-uninitialized matched-value.26)
          (let () (datum-fail "uninitialized value is not external data")))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            26
            (debug-source-stack)
            (if (host:record? matched-value.26)
              (host:record-type-name (host:record-rtd matched-value.26))
              "nonrecord")))))))

(define outward-mutable
  (lambda (source seen)
    (let ((matched-value.28 (outward-find source (ref-get seen))))
      (cond
        ((is-outward-found matched-value.28)
          (let ((result (outward-found/value matched-value.28))) result))
        ((is-outward-absent matched-value.28) (let () (outward-node source seen)))
        (else
          (host:error
            "SFIR"
            "nonexhaustive control match"
            28
            (debug-source-stack)
            (if (host:record? matched-value.28)
              (host:record-type-name (host:record-rtd matched-value.28))
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

(define literal (value-symbol (string->symbol "unix")))

(define literal.1 (value-symbol (string->symbol "slatex.list-set!")))

(define literal.2 (value-symbol (string->symbol "list-too-small")))

(define literal.3 (value-symbol (string->symbol "slatex.sublist")))

(define literal.4 (value-symbol (string->symbol "list-too-small")))

(define literal.5 (value-symbol (string->symbol "assume-output-forced")))

(define literal.6 (value-string "Error: "))

(define literal.7 (value-string ": "))

(define literal.8 (value-string ""))

(define literal.9
  (value-cons
    (value-symbol (string->symbol "=>"))
    (value-cons
      (value-symbol (string->symbol "%"))
      (value-cons
        (value-symbol (string->symbol "abort"))
        (value-cons
          (value-symbol (string->symbol "and"))
          (value-cons
            (value-symbol (string->symbol "begin"))
            (value-cons
              (value-symbol (string->symbol "begin0"))
              (value-cons
                (value-symbol (string->symbol "case"))
                (value-cons
                  (value-symbol (string->symbol "case-lambda"))
                  (value-cons
                    (value-symbol (string->symbol "cond"))
                    (value-cons
                      (value-symbol (string->symbol "define"))
                      (value-cons
                        (value-symbol (string->symbol "define!"))
                        (value-cons
                          (value-symbol (string->symbol "define-macro!"))
                          (value-cons
                            (value-symbol (string->symbol "define-syntax"))
                            (value-cons
                              (value-symbol (string->symbol "defrec!"))
                              (value-cons
                                (value-symbol (string->symbol "delay"))
                                (value-cons
                                  (value-symbol (string->symbol "do"))
                                  (value-cons
                                    (value-symbol (string->symbol "else"))
                                    (value-cons
                                      (value-symbol (string->symbol "extend-syntax"))
                                      (value-cons
                                        (value-symbol (string->symbol "fluid-let"))
                                        (value-cons
                                          (value-symbol (string->symbol "if"))
                                          (value-cons
                                            (value-symbol (string->symbol "lambda"))
                                            (value-cons
                                              (value-symbol (string->symbol "let"))
                                              (value-cons
                                                (value-symbol (string->symbol "let*"))
                                                (value-cons
                                                  (value-symbol (string->symbol "letrec"))
                                                  (value-cons
                                                    (value-symbol (string->symbol "let-syntax"))
                                                    (value-cons
                                                      (value-symbol
                                                        (string->symbol "letrec-syntax"))
                                                      (value-cons
                                                        (value-symbol (string->symbol "or"))
                                                        (value-cons
                                                          (value-symbol
                                                            (string->symbol "quasiquote"))
                                                          (value-cons
                                                            (value-symbol (string->symbol "quote"))
                                                            (value-cons
                                                              (value-symbol (string->symbol "rec"))
                                                              (value-cons
                                                                (value-symbol
                                                                  (string->symbol "record-case"))
                                                                (value-cons
                                                                  (value-symbol
                                                                    (string->symbol "record-evcase"))
                                                                  (value-cons
                                                                    (value-symbol
                                                                      (string->symbol "recur"))
                                                                    (value-cons
                                                                      (value-symbol
                                                                        (string->symbol "set!"))
                                                                      (value-cons
                                                                        (value-symbol
                                                                          (string->symbol "sigma"))
                                                                        (value-cons
                                                                          (value-symbol
                                                                            (string->symbol
                                                                              "struct"))
                                                                          (value-cons
                                                                            (value-symbol
                                                                              (string->symbol
                                                                                "syntax"))
                                                                            (value-cons
                                                                              (value-symbol
                                                                                (string->symbol
                                                                                  "syntax-rules"))
                                                                              (value-cons
                                                                                (value-symbol
                                                                                  (string->symbol
                                                                                    "trace"))
                                                                                (value-cons
                                                                                  (value-symbol
                                                                                    (string->symbol
                                                                                      "trace-lambda"))
                                                                                  (value-cons
                                                                                    (value-symbol
                                                                                      (string->symbol
                                                                                        "trace-let"))
                                                                                    (value-cons
                                                                                      (value-symbol
                                                                                        (string->symbol
                                                                                          "trace-recur"))
                                                                                      (value-cons
                                                                                        (value-symbol
                                                                                          (string->symbol
                                                                                            "unless"))
                                                                                        (value-cons
                                                                                          (value-symbol
                                                                                            (string->symbol
                                                                                              "unquote"))
                                                                                          (value-cons
                                                                                            (value-symbol
                                                                                              (string->symbol
                                                                                                "unquote-splicing"))
                                                                                            (value-cons
                                                                                              (value-symbol
                                                                                                (string->symbol
                                                                                                  "untrace"))
                                                                                              (value-cons
                                                                                                (value-symbol
                                                                                                  (string->symbol
                                                                                                    "when"))
                                                                                                (value-cons
                                                                                                  (value-symbol
                                                                                                    (string->symbol
                                                                                                      "with"))
                                                                                                  (value-null
))))))))))))))))))))))))))))))))))))))))))))))))))

(define literal.10 (value-string "."))

(define literal.11 (value-string "."))

(define literal.12 (value-string "..."))

(define literal.13 (value-string "{\\dots}"))

(define literal.14 (value-string "-"))

(define literal.15 (value-string "$-$"))

(define literal.16 (value-string "1-"))

(define literal.17 (value-string "\\va{1$-$}"))

(define literal.18 (value-string "-1+"))

(define literal.19 (value-string "\\va{$-$1$+$}"))

(define literal.20
  (value-cons
    (value-string "define-syntax")
    (value-cons
      (value-string "syntax-rules")
      (value-cons
        (value-string "defmacro")
        (value-cons
          (value-string "extend-syntax")
          (value-cons (value-string "define-macro!") (value-null)))))))

(define literal.21
  (value-cons (value-string "case") (value-cons (value-string "record-case") (value-null))))

(define literal.22 (value-string "{\\tt\\dq}"))

(define literal.23 (value-string "{\\atsign}"))

(define literal.24 (value-string "\\~{}"))

(define literal.25 (value-string "$\\vert$"))

(define literal.26 (value-string "\\^{}"))

(define literal.27 (value-string "$\\gt$"))

(define literal.28 (value-string "$\\lt$"))

(define literal.29 (value-string "$=$"))

(define literal.30 (value-string "$+$"))

(define literal.31 (value-string "$\\backslash$"))

(define literal.32
  (value-cons (value-character #\{) (value-cons (value-character #\}) (value-null))))

(define literal.33
  (value-cons
    (value-character #\$)
    (value-cons
      (value-character #\&)
      (value-cons
        (value-character #\%)
        (value-cons (value-character #\#) (value-cons (value-character #\_) (value-null)))))))

(define literal.34 (value-string "UNDEFINED"))

(define literal.35 (value-string "scheme"))

(define literal.36 (value-string "schemeresult"))

(define literal.37 (value-string "schemedisplay"))

(define literal.38 (value-string "schemebox"))

(define literal.39 (value-string "schemeinput"))

(define literal.40 (value-string "schemeregion"))

(define literal.41 (value-symbol (string->symbol "all")))

(define literal.42 (value-symbol (string->symbol "skip")))

(define literal.43 (value-symbol (string->symbol "skip")))

(define literal.44 (value-symbol (string->symbol "skip")))

(define literal.45 (value-string "-$>$"))

(define literal.46 (value-string "$\\to$"))

(define literal.47 (value-string "\\begin{"))

(define literal.48 (value-string "}"))

(define literal.49 (value-string "\\"))

(define literal.50 (value-string "\\end{"))

(define literal.51 (value-string "}"))

(define literal.52 (value-string "\\end"))

(define literal.53 (value-symbol (string->symbol "slatex.display-token")))

(define literal.54 (value-string "\\dt{"))

(define literal.55 (value-string "}"))

(define literal.56 (value-symbol (string->symbol "data")))

(define literal.57 (value-string "\\cn{"))

(define literal.58 (value-string "}"))

(define literal.59 (value-symbol (string->symbol "constant")))

(define literal.60 (value-string "\\va{"))

(define literal.61 (value-string "}"))

(define literal.62 (value-symbol (string->symbol "variable")))

(define literal.63 (value-string "\\sy{"))

(define literal.64 (value-string "}"))

(define literal.65 (value-symbol (string->symbol "syntax")))

(define literal.66 (value-symbol (string->symbol "fwd1")))

(define literal.67 (value-symbol (string->symbol "fwd2")))

(define literal.68 (value-string "UNDEFINED"))

(define literal.69 (value-symbol (string->symbol "fwd3")))

(define literal.70 (value-symbol (string->symbol "fwd4")))

(define literal.71 (value-symbol (string->symbol "fwd5")))

(define literal.72 (value-symbol (string->symbol "fwd6")))

(define literal.73 (value-symbol (string->symbol "fwd7")))

(define literal.74 (value-symbol (string->symbol "fwd8")))

(define literal.75 (value-symbol (string->symbol "fwd9")))

(define literal.76 (value-symbol (string->symbol "fwd10")))

(define literal.77 (value-string "\\ "))

(define literal.78 (value-string "\\QUO "))

(define literal.79 (value-string "\\BKT "))

(define literal.80 (value-string "\\PRN "))

(define literal.81 (value-string "\\HL "))

(define literal.82 (value-string "\\>"))

(define literal.83 (value-string "\\="))

(define literal.84 (value-string "}"))

(define literal.85 (value-string "\\dt{"))

(define literal.86 (value-symbol (string->symbol "not-yet")))

(define literal.87 (value-symbol (string->symbol "already-seen")))

(define literal.88 (value-symbol (string->symbol "dos")))

(define literal.89 (value-symbol (string->symbol "slatex.get-line")))

(define literal.90 (value-symbol (string->symbol "runaway-math-subformula")))

(define literal.91 (value-symbol (string->symbol "slatex.get-line")))

(define literal.92 (value-symbol (string->symbol "runaway-math-subformula")))

(define literal.93 (value-symbol (string->symbol "anything-else?")))

(define literal.94 (value-symbol (string->symbol "skip")))

(define literal.95 (value-symbol (string->symbol "exit-loop1")))

(define literal.96 (value-symbol (string->symbol "exit-loop1")))

(define literal.97
  (value-cons
    (value-character #\')
    (value-cons (value-character #\`) (value-cons (value-character #\,) (value-null)))))

(define literal.98 (value-symbol (string->symbol "skip")))

(define literal.99 (value-symbol (string->symbol "skip")))

(define literal.100 (value-symbol (string->symbol "skip")))

(define literal.101 (value-symbol (string->symbol "skip")))

(define literal.102 (value-symbol (string->symbol "skip")))

(define literal.103 (value-symbol (string->symbol "exit-loop")))

(define literal.104 (value-symbol (string->symbol "exit")))

(define literal.105 (value-symbol (string->symbol "exit-loop2")))

(define literal.106 (value-symbol (string->symbol "exit-loop")))

(define literal.107 (value-symbol (string->symbol "skip")))

(define literal.108 (value-symbol (string->symbol "exit-loop")))

(define literal.109 (value-symbol (string->symbol "skip")))

(define literal.110 (value-symbol (string->symbol "else")))

(define literal.111 (value-symbol (string->symbol "skip")))

(define literal.112 (value-symbol (string->symbol "skip")))

(define literal.113 (value-symbol (string->symbol "skip")))

(define literal.114
  (value-cons (value-character #\)) (value-cons (value-character #\]) (value-null))))

(define literal.115 (value-symbol (string->symbol "skip")))

(define literal.116 (value-symbol (string->symbol "skip")))

(define literal.117
  (value-cons (value-character #\() (value-cons (value-character #\[) (value-null))))

(define literal.118 (value-symbol (string->symbol "skip")))

(define literal.119 (value-symbol (string->symbol "skip")))

(define literal.120 (value-string "}"))

(define literal.121 (value-string "\\dt{"))

(define literal.122 (value-string "\\\\"))

(define literal.123 (value-symbol (string->symbol "slatex.do-token")))

(define literal.124 (value-symbol (string->symbol "skip")))

(define literal.125 (value-symbol (string->symbol "variable")))

(define literal.126 (value-string "quote"))

(define literal.127 (value-symbol (string->symbol "syntax")))

(define literal.128 (value-symbol (string->symbol "variable")))

(define literal.129 (value-symbol (string->symbol "constant")))

(define literal.130 (value-symbol (string->symbol "syntax")))

(define literal.131 (value-symbol (string->symbol "syntax")))

(define literal.132 (value-symbol (string->symbol "constant")))

(define literal.133 (value-symbol (string->symbol "constant")))

(define literal.134 (value-symbol (string->symbol "data")))

(define literal.135 (value-symbol (string->symbol "constant")))

(define literal.136 (value-symbol (string->symbol "data")))

(define literal.137 (value-symbol (string->symbol "syntax")))

(define literal.138 (value-string "else"))

(define literal.139 (value-string ""))

(define literal.140 (value-symbol (string->symbol "slatex.*path-separator*")))

(define literal.141 (value-symbol (string->symbol "cant-determine")))

(define literal.142 (value-symbol (string->symbol "dos")))

(define literal.143 (value-symbol (string->symbol "unix")))

(define literal.144 (value-symbol (string->symbol "slatex.*directory-mark*")))

(define literal.145 (value-symbol (string->symbol "cant-determine")))

(define literal.146 (value-string "\\"))

(define literal.147 (value-symbol (string->symbol "dos")))

(define literal.148 (value-string "/"))

(define literal.149 (value-symbol (string->symbol "unix")))

(define literal.150 (value-string "."))

(define literal.151 (value-string "x"))

(define literal.152 (value-symbol (string->symbol "dos")))

(define literal.153 (value-string "outputs/"))

(define literal.154 (value-symbol (string->symbol "unix")))

(define literal.155 (value-string ""))

(define literal.156 (value-string ""))

(define literal.157 (value-string "."))

(define literal.158 (value-string ".tex"))

(define literal.159 (value-string ".sty"))

(define literal.160 (value-string ".tex"))

(define literal.161
  (value-cons
    (value-string ".scm")
    (value-cons (value-string ".ss") (value-cons (value-string ".s") (value-null)))))

(define literal.162 (value-symbol (string->symbol "fwd")))

(define literal.163 (value-string "z"))

(define literal.164 (value-string "zz"))

(define literal.165 (value-symbol (string->symbol "done")))

(define literal.166 (value-symbol (string->symbol "done")))

(define literal.167 (value-symbol (string->symbol "read-ctrl-exp")))

(define literal.168 (value-symbol (string->symbol "done")))

(define literal.169 (value-symbol (string->symbol "done")))

(define literal.170 (value-symbol (string->symbol "done")))

(define literal.171 (value-symbol (string->symbol "done")))

(define literal.172 (value-symbol (string->symbol "done")))

(define literal.173 (value-symbol (string->symbol "done")))

(define literal.174 (value-symbol (string->symbol "slatex.read-grouped-latexexp")))

(define literal.175 (value-symbol (string->symbol "slatex.read-grouped-latexexp")))

(define literal.176 (value-symbol (string->symbol "ok")))

(define literal.177 (value-symbol (string->symbol "slatex.read-grouped-latexexp")))

(define literal.178 (value-symbol (string->symbol "slatex.read-filename")))

(define literal.179 (value-symbol (string->symbol "slatex.read-filename")))

(define literal.180 (value-symbol (string->symbol "slatex.read-delimed-commaed-filenames")))

(define literal.181 (value-symbol (string->symbol "slatex.read-delimed-commaed-filenames")))

(define literal.182 (value-symbol (string->symbol "ok")))

(define literal.183 (value-symbol (string->symbol "slatex.read-delimed-commaed-filenames")))

(define literal.184 (value-symbol (string->symbol "slatex.read-delimed-commaed-filenames")))

(define literal.185 (value-symbol (string->symbol "slatex.read-delimed-commaed-filenames")))

(define literal.186 (value-symbol (string->symbol "void")))

(define literal.187 (value-symbol (string->symbol "slatex.read-grouped-schemeids")))

(define literal.188 (value-symbol (string->symbol "slatex.read-grouped-schemeids")))

(define literal.189 (value-symbol (string->symbol "ok")))

(define literal.190 (value-symbol (string->symbol "slatex.read-grouped-schemeids")))

(define literal.191 (value-string "UNDEFINED"))

(define literal.192 (value-symbol (string->symbol "void")))

(define literal.193
  (value-cons
    (value-symbol (string->symbol "keyword"))
    (value-cons
      (value-symbol (string->symbol "constant"))
      (value-cons (value-symbol (string->symbol "variable")) (value-null)))))

(define literal.194 (value-symbol (string->symbol "slatex.add-to-slatex-db-basic")))

(define literal.195 (value-symbol (string->symbol "variable")))

(define literal.196 (value-symbol (string->symbol "constant")))

(define literal.197 (value-symbol (string->symbol "keyword")))

(define literal.198 (value-symbol (string->symbol "slatex.add-to-slatex-db-special")))

(define literal.199 (value-symbol (string->symbol "slatex.add-to-slatex-db-special")))

(define literal.200 (value-symbol (string->symbol "setspecialsymbol-takes-one-arg-only")))

(define literal.201 (value-symbol (string->symbol "ok")))

(define literal.202 (value-symbol (string->symbol "setspecialsymbol")))

(define literal.203 (value-symbol (string->symbol "unsetspecialsymbol")))

(define literal.204 (value-symbol (string->symbol "slatex.process-slatex-alias")))

(define literal.205 (value-symbol (string->symbol "slatex.process-slatex-alias")))

(define literal.206 (value-symbol (string->symbol "math-escape-should-be-character")))

(define literal.207 (value-symbol (string->symbol "ok")))

(define literal.208 (value-symbol (string->symbol "mathescape")))

(define literal.209 (value-symbol (string->symbol "region")))

(define literal.210 (value-symbol (string->symbol "input")))

(define literal.211 (value-symbol (string->symbol "box")))

(define literal.212 (value-symbol (string->symbol "display")))

(define literal.213 (value-symbol (string->symbol "resultintext")))

(define literal.214 (value-symbol (string->symbol "intext")))

(define literal.215 (value-string "pltexchk.jnk"))

(define literal.216 (value-symbol (string->symbol "junk")))

(define literal.217 (value-string ".sty"))

(define literal.218 (value-symbol (string->symbol "slatex.process-case-info")))

(define literal.219 (value-symbol (string->symbol "bad-schemecasesensitive-arg")))

(define literal.220 (value-string "false"))

(define literal.221 (value-string "true"))

(define literal.222 (value-string "xZfilhid.tex"))

(define literal.223 (value-string "\\def\\filehider{x}"))

(define literal.224 (value-symbol (string->symbol "dos")))

(define literal.225 (value-string ".tex"))

(define literal.226 (value-symbol (string->symbol "slatex.dump-intext")))

(define literal.227 (value-symbol (string->symbol "slatex.dump-intext")))

(define literal.228 (value-symbol (string->symbol "done")))

(define literal.229 (value-symbol (string->symbol "slatex.dump-display")))

(define literal.230 (value-string ""))

(define literal.231 (value-symbol (string->symbol "slatex.dump-display")))

(define literal.232 (value-string ""))

(define literal.233 (value-symbol (string->symbol "done")))

(define literal.234 (value-string "begin "))

(define literal.235 (value-string "documentstyle"))

(define literal.236 (value-symbol (string->symbol "skip")))

(define literal.237 (value-symbol (string->symbol "unsetspecialsymbol")))

(define literal.238 (value-string "unsetspecialsymbol"))

(define literal.239 (value-symbol (string->symbol "setspecialsymbol")))

(define literal.240 (value-string "setspecialsymbol"))

(define literal.241 (value-symbol (string->symbol "variable")))

(define literal.242 (value-string "setvariable"))

(define literal.243 (value-symbol (string->symbol "constant")))

(define literal.244 (value-string "setconstant"))

(define literal.245 (value-symbol (string->symbol "keyword")))

(define literal.246 (value-string "setkeyword"))

(define literal.247 (value-symbol (string->symbol "mathescape")))

(define literal.248 (value-string "undefschememathescape"))

(define literal.249 (value-symbol (string->symbol "mathescape")))

(define literal.250 (value-string "defschememathescape"))

(define literal.251 (value-symbol (string->symbol "region")))

(define literal.252 (value-string "undefschemeregiontoken"))

(define literal.253 (value-symbol (string->symbol "region")))

(define literal.254 (value-string "defschemeregiontoken"))

(define literal.255 (value-symbol (string->symbol "input")))

(define literal.256 (value-string "undefschemeinputtoken"))

(define literal.257 (value-symbol (string->symbol "input")))

(define literal.258 (value-string "defschemeinputtoken"))

(define literal.259 (value-symbol (string->symbol "box")))

(define literal.260 (value-string "undefschemeboxtoken"))

(define literal.261 (value-symbol (string->symbol "box")))

(define literal.262 (value-string "defschemeboxtoken"))

(define literal.263 (value-symbol (string->symbol "display")))

(define literal.264 (value-string "undefschemedisplaytoken"))

(define literal.265 (value-symbol (string->symbol "display")))

(define literal.266 (value-string "defschemedisplaytoken"))

(define literal.267 (value-symbol (string->symbol "resultintext")))

(define literal.268 (value-string "undefschemeresulttoken"))

(define literal.269 (value-symbol (string->symbol "resultintext")))

(define literal.270 (value-string "defschemeresulttoken"))

(define literal.271 (value-symbol (string->symbol "intext")))

(define literal.272 (value-string "undefschemetoken"))

(define literal.273 (value-symbol (string->symbol "intext")))

(define literal.274 (value-string "defschemetoken"))

(define literal.275 (value-string "schemecasesensitive"))

(define literal.276 (value-string "documentstyle"))

(define literal.277 (value-string "includeonly"))

(define literal.278 (value-string ".tex"))

(define literal.279 (value-symbol (string->symbol "all")))

(define literal.280 (value-string "include"))

(define literal.281 (value-string "input"))

(define literal.282 (value-symbol (string->symbol "plainregion")))

(define literal.283 (value-symbol (string->symbol "plainbox")))

(define literal.284 (value-symbol (string->symbol "plaindisplay")))

(define literal.285 (value-symbol (string->symbol "resultintext")))

(define literal.286 (value-symbol (string->symbol "intext")))

(define literal.287 (value-symbol (string->symbol "envregion")))

(define literal.288 (value-symbol (string->symbol "envbox")))

(define literal.289 (value-symbol (string->symbol "envdisplay")))

(define literal.290 (value-string "begin"))

(define literal.291 (value-string "slatexdisable"))

(define literal.292 (value-string "slatexseparateincludes"))

(define literal.293 (value-string "slatexignorecurrentfile"))

(define literal.294 (value-symbol (string->symbol "exit-loop")))

(define literal.295 (value-string "["))

(define literal.296 (value-string "]"))

(define literal.297 (value-string "end "))

(define literal.298 (value-string ".tex"))

(define literal.299 (value-string "ZZZZschemedisplay"))

(define literal.300 (value-string "process-scheme-file: "))

(define literal.301 (value-string " doesn't exist"))

(define literal.302 (value-string ".scm"))

(define literal.303 (value-string ".tex"))

(define literal.304 (value-symbol (string->symbol "slatex.trigger-scheme2tex")))

(define literal.305 (value-string "\\end"))

(define literal.306
  (value-cons
    (value-symbol (string->symbol "plaindisplay"))
    (value-cons (value-symbol (string->symbol "plainbox")) (value-null))))

(define literal.307 (value-string "\\end{"))

(define literal.308 (value-string "}"))

(define literal.309
  (value-cons
    (value-symbol (string->symbol "envdisplay"))
    (value-cons (value-symbol (string->symbol "envbox")) (value-null))))

(define literal.310
  (value-cons
    (value-symbol (string->symbol "intext"))
    (value-cons (value-symbol (string->symbol "resultintext")) (value-null))))

(define literal.311
  (value-cons
    (value-symbol (string->symbol "intext"))
    (value-cons (value-symbol (string->symbol "resultintext")) (value-null))))

(define literal.312 (value-symbol (string->symbol "slatex.trigger-scheme2tex")))

(define literal.313 (value-string "ZZZZschemebox"))

(define literal.314
  (value-cons
    (value-symbol (string->symbol "envbox"))
    (value-cons (value-symbol (string->symbol "plainbox")) (value-null))))

(define literal.315 (value-string "ZZZZschemedisplay"))

(define literal.316
  (value-cons
    (value-symbol (string->symbol "envdisplay"))
    (value-cons (value-symbol (string->symbol "plaindisplay")) (value-null))))

(define literal.317 (value-string "ZZZZschemeresultintext"))

(define literal.318 (value-symbol (string->symbol "resultintext")))

(define literal.319 (value-string "ZZZZschemecodeintext"))

(define literal.320 (value-symbol (string->symbol "intext")))

(define literal.321
  (value-cons
    (value-symbol (string->symbol "envdisplay"))
    (value-cons
      (value-symbol (string->symbol "plaindisplay"))
      (value-cons
        (value-symbol (string->symbol "envbox"))
        (value-cons (value-symbol (string->symbol "plainbox")) (value-null))))))

(define literal.322 (value-string ".tex"))

(define literal.323 (value-string ".tex"))

(define literal.324 (value-symbol (string->symbol "slatex.trigger-region")))

(define literal.325 (value-string "\\end"))

(define literal.326 (value-symbol (string->symbol "plainregion")))

(define literal.327 (value-string "\\end{"))

(define literal.328 (value-string "}"))

(define literal.329 (value-symbol (string->symbol "envregion")))

(define literal.330 (value-string "\\"))

(define literal.331 (value-symbol (string->symbol "input")))

(define literal.332 (value-symbol (string->symbol "plainregion")))

(define literal.333 (value-symbol (string->symbol "plainbox")))

(define literal.334 (value-symbol (string->symbol "plaindisplay")))

(define literal.335 (value-symbol (string->symbol "resultintext")))

(define literal.336 (value-symbol (string->symbol "intext")))

(define literal.337 (value-string "\\begin{"))

(define literal.338 (value-string "}"))

(define literal.339 (value-symbol (string->symbol "envregion")))

(define literal.340 (value-symbol (string->symbol "envbox")))

(define literal.341 (value-symbol (string->symbol "envdisplay")))

(define literal.342 (value-string "begin"))

(define literal.343 (value-string "{}"))

(define literal.344 (value-symbol (string->symbol "exit-loop")))

(define literal.345 (value-symbol (string->symbol "slatex.inline-protected")))

(define literal.346 (value-symbol (string->symbol "input")))

(define literal.347 (value-string "\\end"))

(define literal.348
  (value-cons
    (value-symbol (string->symbol "plaindisplay"))
    (value-cons (value-symbol (string->symbol "plainbox")) (value-null))))

(define literal.349 (value-string "\\end{"))

(define literal.350 (value-string "}"))

(define literal.351
  (value-cons
    (value-symbol (string->symbol "envdisplay"))
    (value-cons (value-symbol (string->symbol "envbox")) (value-null))))

(define literal.352
  (value-cons
    (value-symbol (string->symbol "intext"))
    (value-cons (value-symbol (string->symbol "resultintext")) (value-null))))

(define literal.353 (value-string "\\"))

(define literal.354 (value-string "\\end"))

(define literal.355 (value-string "\\end"))

(define literal.356 (value-symbol (string->symbol "plainregion")))

(define literal.357 (value-string "\\begin{"))

(define literal.358 (value-string "}"))

(define literal.359 (value-string "\\end{"))

(define literal.360 (value-string "}"))

(define literal.361 (value-string "\\end{"))

(define literal.362 (value-string "}"))

(define literal.363 (value-symbol (string->symbol "envregion")))

(define source/*op-sys* (ref (value-uninitialized)))

(ref-set! source/*op-sys* literal)

(define source/slatex.ormap (ref (value-uninitialized)))

(define body/source/slatex.ormap
  (lambda (source/f source/l)
    (invoke-1
      ((lambda () (let ((source/loop #f) (body/source/loop #f)) (set! source/loop (ref (value-uninitialized))) (set! body/source/loop (lambda (source/l.1) (if (value-truth? (primitive/null?/1 source/l.1)) (value-boolean #f) ((lambda (source/value) (if (value-truth? source/value) source/value (body/source/loop (primitive/cdr/1 source/l.1)))) (invoke-1 source/f (primitive/car/1 source/l.1)))))) (ref-set! source/loop (value-procedure (ref (unit)) (function-1 body/source/loop))) (binding-value source/loop)))
)
      source/l)))

(ref-set! source/slatex.ormap (value-procedure (ref (unit)) (function-2 body/source/slatex.ormap)))

(define source/slatex.ormapcdr (ref (value-uninitialized)))

(define body/source/slatex.ormapcdr
  (lambda (source/f.1 source/l.2)
    (invoke-1
      ((lambda () (let ((source/loop.1 #f) (body/source/loop.1 #f)) (set! source/loop.1 (ref (value-uninitialized))) (set! body/source/loop.1 (lambda (source/l.3) (if (value-truth? (primitive/null?/1 source/l.3)) (value-boolean #f) ((lambda (source/value.1) (if (value-truth? source/value.1) source/value.1 (body/source/loop.1 (primitive/cdr/1 source/l.3)))) (invoke-1 source/f.1 source/l.3))))) (ref-set! source/loop.1 (value-procedure (ref (unit)) (function-1 body/source/loop.1))) (binding-value source/loop.1)))
)
      source/l.2)))

(ref-set!
  source/slatex.ormapcdr
  (value-procedure (ref (unit)) (function-2 body/source/slatex.ormapcdr)))

(define source/slatex.append! (ref (value-uninitialized)))

(define body/source/slatex.append!
  (lambda (source/l1 source/l2)
    (if (value-truth? (primitive/null?/1 source/l1))
      source/l2
      (if (value-truth? (primitive/null?/1 source/l2))
        source/l1
        (begin
          (invoke-1
            ((lambda () (let ((source/loop.2 #f) (body/source/loop.2 #f)) (set! source/loop.2 (ref (value-uninitialized))) (set! body/source/loop.2 (lambda (source/l1.1) (if (value-truth? (primitive/null?/1 (primitive/cdr/1 source/l1.1))) (primitive/set-cdr!/2 source/l1.1 source/l2) (body/source/loop.2 (primitive/cdr/1 source/l1.1))))) (ref-set! source/loop.2 (value-procedure (ref (unit)) (function-1 body/source/loop.2))) (binding-value source/loop.2)))
)
            source/l1)
          source/l1)))))

(ref-set!
  source/slatex.append!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.append!)))

(define source/slatex.append-map! (ref (value-uninitialized)))

(define body/source/slatex.append-map!
  (lambda (source/f.2 source/l.4)
    (invoke-1
      ((lambda () (let ((source/loop.3 #f) (body/source/loop.3 #f)) (set! source/loop.3 (ref (value-uninitialized))) (set! body/source/loop.3 (lambda (source/l.5) (if (value-truth? (primitive/null?/1 source/l.5)) (value-null) (body/source/slatex.append! (invoke-1 source/f.2 (primitive/car/1 source/l.5)) (body/source/loop.3 (primitive/cdr/1 source/l.5)))))) (ref-set! source/loop.3 (value-procedure (ref (unit)) (function-1 body/source/loop.3))) (binding-value source/loop.3)))
)
      source/l.4)))

(ref-set!
  source/slatex.append-map!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.append-map!)))

(define source/slatex.remove-if! (ref (value-uninitialized)))

(define body/source/slatex.remove-if!
  (lambda (source/p source/s)
    (invoke-1
      ((lambda () (let ((source/loop.4 #f) (body/source/loop.4 #f)) (set! source/loop.4 (ref (value-uninitialized))) (set! body/source/loop.4 (lambda (source/s.1) (if (value-truth? (primitive/null?/1 source/s.1)) (value-null) (if (value-truth? (invoke-1 source/p (primitive/car/1 source/s.1))) (body/source/loop.4 (primitive/cdr/1 source/s.1)) ((lambda (source/r) (begin (primitive/set-cdr!/2 source/s.1 source/r) source/s.1)) (body/source/loop.4 (primitive/cdr/1 source/s.1))))))) (ref-set! source/loop.4 (value-procedure (ref (unit)) (function-1 body/source/loop.4))) (binding-value source/loop.4)))
)
      source/s)))

(ref-set!
  source/slatex.remove-if!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.remove-if!)))

(define source/slatex.reverse! (ref (value-uninitialized)))

(define body/source/slatex.reverse!
  (lambda (source/s.2)
    (invoke-2
      ((lambda () (let ((source/loop.5 #f) (body/source/loop.5 #f)) (set! source/loop.5 (ref (value-uninitialized))) (set! body/source/loop.5 (lambda (source/s.3 source/r.1) (if (value-truth? (primitive/null?/1 source/s.3)) source/r.1 ((lambda (source/d) (begin (primitive/set-cdr!/2 source/s.3 source/r.1) (body/source/loop.5 source/d source/s.3))) (primitive/cdr/1 source/s.3))))) (ref-set! source/loop.5 (value-procedure (ref (unit)) (function-2 body/source/loop.5))) (binding-value source/loop.5)))
)
      source/s.2
      (value-null))))

(ref-set!
  source/slatex.reverse!
  (value-procedure (ref (unit)) (function-1 body/source/slatex.reverse!)))

(define source/slatex.list-set! (ref (value-uninitialized)))

(define body/source/slatex.list-set!
  (lambda (source/l.6 source/i source/v)
    (invoke-2
      ((lambda () (let ((source/loop.6 #f) (body/source/loop.6 #f)) (set! source/loop.6 (ref (value-uninitialized))) (set! body/source/loop.6 (lambda (source/l.7 source/i.1) (if (value-truth? (primitive/null?/1 source/l.7)) (body/source/slatex.error literal.1 literal.2) (if (value-truth? (primitive/=/2 source/i.1 (value-number (exact-number 0)))) (primitive/set-car!/2 source/l.7 source/v) (body/source/loop.6 (primitive/cdr/1 source/l.7) (primitive/-/2 source/i.1 (value-number (exact-number 1)))))))) (ref-set! source/loop.6 (value-procedure (ref (unit)) (function-2 body/source/loop.6))) (binding-value source/loop.6)))
)
      source/l.6
      source/i)))

(ref-set!
  source/slatex.list-set!
  (value-procedure (ref (unit)) (function-3 body/source/slatex.list-set!)))

(define source/slatex.list-prefix? (ref (value-uninitialized)))

(define body/source/slatex.list-prefix?
  (lambda (source/pfx source/l.8)
    (if (value-truth? (primitive/null?/1 source/pfx))
      (value-boolean #t)
      (if (value-truth? (primitive/null?/1 source/l.8))
        (value-boolean #f)
        (if (value-truth? (primitive/eqv?/2 (primitive/car/1 source/pfx) (primitive/car/1 source/l.8)))
          (body/source/slatex.list-prefix?
            (primitive/cdr/1 source/pfx)
            (primitive/cdr/1 source/l.8))
          (value-boolean #f))))))

(ref-set!
  source/slatex.list-prefix?
  (value-procedure (ref (unit)) (function-2 body/source/slatex.list-prefix?)))

(define source/slatex.string-prefix? (ref (value-uninitialized)))

(define body/source/slatex.string-prefix?
  (lambda (source/pfx.1 source/s.4)
    ((lambda (source/pfx-len source/s-len) (if (value-truth? (primitive/>/2 source/pfx-len source/s-len)) (value-boolean #f) (invoke-1 ((lambda () (let ((source/loop.7 #f) (body/source/loop.7 #f)) (set! source/loop.7 (ref (value-uninitialized))) (set! body/source/loop.7 (lambda (source/i.2) (if (value-truth? (primitive/>=/2 source/i.2 source/pfx-len)) (value-boolean #t) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 source/pfx.1 source/i.2) (primitive/string-ref/2 source/s.4 source/i.2))) (body/source/loop.7 (primitive/+/2 source/i.2 (value-number (exact-number 1)))) (value-boolean #f))))) (ref-set! source/loop.7 (value-procedure (ref (unit)) (function-1 body/source/loop.7))) (binding-value source/loop.7)))) (value-number (exact-number 0)))))
      (primitive/string-length/1 source/pfx.1)
      (primitive/string-length/1 source/s.4))))

(ref-set!
  source/slatex.string-prefix?
  (value-procedure (ref (unit)) (function-2 body/source/slatex.string-prefix?)))

(define source/slatex.string-suffix? (ref (value-uninitialized)))

(define body/source/slatex.string-suffix?
  (lambda (source/sfx source/s.5)
    ((lambda (source/sfx-len source/s-len.1) (if (value-truth? (primitive/>/2 source/sfx-len source/s-len.1)) (value-boolean #f) (invoke-2 ((lambda () (let ((source/loop.8 #f) (body/source/loop.8 #f)) (set! source/loop.8 (ref (value-uninitialized))) (set! body/source/loop.8 (lambda (source/i.3 source/j) (if (value-truth? (primitive/</2 source/i.3 (value-number (exact-number 0)))) (value-boolean #t) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 source/sfx source/i.3) (primitive/string-ref/2 source/s.5 source/j))) (body/source/loop.8 (primitive/-/2 source/i.3 (value-number (exact-number 1))) (primitive/-/2 source/j (value-number (exact-number 1)))) (value-boolean #f))))) (ref-set! source/loop.8 (value-procedure (ref (unit)) (function-2 body/source/loop.8))) (binding-value source/loop.8)))) (primitive/-/2 source/sfx-len (value-number (exact-number 1))) (primitive/-/2 source/s-len.1 (value-number (exact-number 1))))))
      (primitive/string-length/1 source/sfx)
      (primitive/string-length/1 source/s.5))))

(ref-set!
  source/slatex.string-suffix?
  (value-procedure (ref (unit)) (function-2 body/source/slatex.string-suffix?)))

(define source/slatex.member-string (ref (value-uninitialized)))

(ref-set! source/slatex.member-string primitive-value/member)

(define source/slatex.adjoin-string (ref (value-uninitialized)))

(define body/source/slatex.adjoin-string
  (lambda (source/s.6 source/l.9)
    (if (value-truth? (invoke-2 (binding-value source/slatex.member-string) source/s.6 source/l.9))
      source/l.9
      (primitive/cons/2 source/s.6 source/l.9))))

(ref-set!
  source/slatex.adjoin-string
  (value-procedure (ref (unit)) (function-2 body/source/slatex.adjoin-string)))

(define source/slatex.remove-string! (ref (value-uninitialized)))

(define body/source/slatex.remove-string!
  (lambda (source/s.7 source/l.10)
    (body/source/slatex.remove-if!
      (value-procedure
        (ref (unit))
        (function-1 (lambda (source/l_i) (primitive/string=?/2 source/l_i source/s.7))))
      source/l.10)))

(ref-set!
  source/slatex.remove-string!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.remove-string!)))

(define source/slatex.adjoin-char (ref (value-uninitialized)))

(define body/source/slatex.adjoin-char
  (lambda (source/c source/l.11)
    (if (value-truth? (primitive/memv/2 source/c source/l.11))
      source/l.11
      (primitive/cons/2 source/c source/l.11))))

(ref-set!
  source/slatex.adjoin-char
  (value-procedure (ref (unit)) (function-2 body/source/slatex.adjoin-char)))

(define source/slatex.remove-char! (ref (value-uninitialized)))

(define body/source/slatex.remove-char!
  (lambda (source/c.1 source/l.12)
    (body/source/slatex.remove-if!
      (value-procedure
        (ref (unit))
        (function-1 (lambda (source/l_i.1) (primitive/char=?/2 source/l_i.1 source/c.1))))
      source/l.12)))

(ref-set!
  source/slatex.remove-char!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.remove-char!)))

(define source/slatex.sublist (ref (value-uninitialized)))

(define body/source/slatex.sublist
  (lambda (source/l.13 source/i.4 source/f.3)
    (invoke-3
      ((lambda () (let ((source/loop.9 #f) (body/source/loop.9 #f)) (set! source/loop.9 (ref (value-uninitialized))) (set! body/source/loop.9 (lambda (source/l.14 source/k source/r.2) (if (value-truth? (primitive/>=/2 source/k source/f.3)) (body/source/slatex.reverse! source/r.2) (if (value-truth? (primitive/null?/1 source/l.14)) (body/source/slatex.error literal.3 literal.4) (body/source/loop.9 (primitive/cdr/1 source/l.14) (primitive/+/2 source/k (value-number (exact-number 1))) (primitive/cons/2 (primitive/car/1 source/l.14) source/r.2)))))) (ref-set! source/loop.9 (value-procedure (ref (unit)) (function-3 body/source/loop.9))) (binding-value source/loop.9)))
)
      (primitive/list-tail/2 source/l.13 source/i.4)
      source/i.4
      (value-null))))

(ref-set!
  source/slatex.sublist
  (value-procedure (ref (unit)) (function-3 body/source/slatex.sublist)))

(define source/slatex.position-char (ref (value-uninitialized)))

(define body/source/slatex.position-char
  (lambda (source/c.2 source/l.15)
    (invoke-2
      ((lambda () (let ((source/loop.10 #f) (body/source/loop.10 #f)) (set! source/loop.10 (ref (value-uninitialized))) (set! body/source/loop.10 (lambda (source/l.16 source/i.5) (if (value-truth? (primitive/null?/1 source/l.16)) (value-boolean #f) (if (value-truth? (primitive/char=?/2 (primitive/car/1 source/l.16) source/c.2)) source/i.5 (body/source/loop.10 (primitive/cdr/1 source/l.16) (primitive/+/2 source/i.5 (value-number (exact-number 1)))))))) (ref-set! source/loop.10 (value-procedure (ref (unit)) (function-2 body/source/loop.10))) (binding-value source/loop.10)))
)
      source/l.15
      (value-number (exact-number 0)))))

(ref-set!
  source/slatex.position-char
  (value-procedure (ref (unit)) (function-2 body/source/slatex.position-char)))

(define source/slatex.string-position-right (ref (value-uninitialized)))

(define body/source/slatex.string-position-right
  (lambda (source/c.3 source/s.8)
    ((lambda (source/n) (invoke-1 ((lambda () (let ((source/loop.11 #f) (body/source/loop.11 #f)) (set! source/loop.11 (ref (value-uninitialized))) (set! body/source/loop.11 (lambda (source/i.6) (if (value-truth? (primitive/</2 source/i.6 (value-number (exact-number 0)))) (value-boolean #f) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 source/s.8 source/i.6) source/c.3)) source/i.6 (body/source/loop.11 (primitive/-/2 source/i.6 (value-number (exact-number 1)))))))) (ref-set! source/loop.11 (value-procedure (ref (unit)) (function-1 body/source/loop.11))) (binding-value source/loop.11)))) (primitive/-/2 source/n (value-number (exact-number 1)))))
      (primitive/string-length/1 source/s.8))))

(ref-set!
  source/slatex.string-position-right
  (value-procedure (ref (unit)) (function-2 body/source/slatex.string-position-right)))

(define source/slatex.token=? (ref (value-uninitialized)))

(define body/source/slatex.token=?
  (lambda (source/t1 source/t2)
    (invoke-2
      (if (value-truth? (binding-value source/slatex.*slatex-case-sensitive?*))
        primitive-value/string=?
        primitive-value/string-ci=?)
      source/t1
      source/t2)))

(ref-set!
  source/slatex.token=?
  (value-procedure (ref (unit)) (function-2 body/source/slatex.token=?)))

(define source/slatex.assoc-token (ref (value-uninitialized)))

(define body/source/slatex.assoc-token
  (lambda (source/x source/s.9)
    (body/source/slatex.ormap
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/s_i)
            (if (value-truth? (body/source/slatex.token=? (primitive/car/1 source/s_i) source/x))
              source/s_i
              (value-boolean #f)))))
      source/s.9)))

(ref-set!
  source/slatex.assoc-token
  (value-procedure (ref (unit)) (function-2 body/source/slatex.assoc-token)))

(define source/slatex.member-token (ref (value-uninitialized)))

(define body/source/slatex.member-token
  (lambda (source/x.1 source/s.10)
    (body/source/slatex.ormapcdr
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/s_i..)
            (if (value-truth? (body/source/slatex.token=? (primitive/car/1 source/s_i..) source/x.1))
              source/s_i..
              (value-boolean #f)))))
      source/s.10)))

(ref-set!
  source/slatex.member-token
  (value-procedure (ref (unit)) (function-2 body/source/slatex.member-token)))

(define source/slatex.remove-token! (ref (value-uninitialized)))

(define body/source/slatex.remove-token!
  (lambda (source/x.2 source/s.11)
    (body/source/slatex.remove-if!
      (value-procedure
        (ref (unit))
        (function-1 (lambda (source/s_i.1) (body/source/slatex.token=? source/s_i.1 source/x.2))))
      source/s.11)))

(ref-set!
  source/slatex.remove-token!
  (value-procedure (ref (unit)) (function-2 body/source/slatex.remove-token!)))

(define source/slatex.file-exists? (ref (value-uninitialized)))

(define body/source/slatex.file-exists? (lambda (source/f.4) (primitive/file-exists?/1 source/f.4)))

(ref-set!
  source/slatex.file-exists?
  (value-procedure (ref (unit)) (function-1 body/source/slatex.file-exists?)))

(define source/slatex.delete-file (ref (value-uninitialized)))

(define body/source/slatex.delete-file (lambda (source/f.5) (primitive/delete-file/1 source/f.5)))

(ref-set!
  source/slatex.delete-file
  (value-procedure (ref (unit)) (function-1 body/source/slatex.delete-file)))

(define source/slatex.force-output (ref (value-uninitialized)))

(define body/source/slatex.force-output (lambda (source/z) literal.5))

(ref-set!
  source/slatex.force-output
  (value-procedure (ref (unit)) (function-rest-0 body/source/slatex.force-output)))

(define source/slatex.*return* (ref (value-uninitialized)))

(ref-set! source/slatex.*return* (primitive/integer->char/1 (value-number (exact-number 13))))

(define source/slatex.*tab* (ref (value-uninitialized)))

(ref-set! source/slatex.*tab* (primitive/integer->char/1 (value-number (exact-number 9))))

(define source/slatex.error (ref (value-uninitialized)))

(define body/source/slatex.error
  (lambda (source/error-type source/error-values)
    (begin
      (primitive/display/1 literal.6)
      (primitive/display/1 source/error-type)
      (primitive/display/1 literal.7)
      (primitive/newline/0)
      (primitive/write/1 source/error-values)
      (primitive/error/2 (value-boolean #f) literal.8))))

(ref-set! source/slatex.error (value-procedure (ref (unit)) (function-2 body/source/slatex.error)))

(define source/slatex.keyword-tokens (ref (value-uninitialized)))

(ref-set! source/slatex.keyword-tokens (primitive/map/2 primitive-value/symbol->string literal.9))

(define source/slatex.variable-tokens (ref (value-uninitialized)))

(ref-set! source/slatex.variable-tokens (value-null))

(define source/slatex.constant-tokens (ref (value-uninitialized)))

(ref-set! source/slatex.constant-tokens (value-null))

(define source/slatex.special-symbols (ref (value-uninitialized)))

(ref-set!
  source/slatex.special-symbols
  (primitive/list/5
    (primitive/cons/2 literal.10 literal.11)
    (primitive/cons/2 literal.12 literal.13)
    (primitive/cons/2 literal.14 literal.15)
    (primitive/cons/2 literal.16 literal.17)
    (primitive/cons/2 literal.18 literal.19)))

(define source/slatex.macro-definers (ref (value-uninitialized)))

(ref-set! source/slatex.macro-definers literal.20)

(define source/slatex.case-and-ilk (ref (value-uninitialized)))

(ref-set! source/slatex.case-and-ilk literal.21)

(define source/slatex.tex-analog (ref (value-uninitialized)))

(define body/source/slatex.tex-analog
  (lambda (source/c.4)
    (if (value-truth? (primitive/memv/2 source/c.4 literal.33))
      (primitive/string/2 (value-character #\\) source/c.4)
      (if (value-truth? (primitive/memv/2 source/c.4 literal.32))
        (primitive/string/4
          (value-character #\$)
          (value-character #\\)
          source/c.4
          (value-character #\$))
        (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\\)))
          literal.31
          (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\+)))
            literal.30
            (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\=)))
              literal.29
              (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\<)))
                literal.28
                (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\>)))
                  literal.27
                  (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\^)))
                    literal.26
                    (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\|)))
                      literal.25
                      (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\~)))
                        literal.24
                        (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\@)))
                          literal.23
                          (if (value-truth? (primitive/char=?/2 source/c.4 (value-character #\")))
                            literal.22
                            (primitive/string/1 source/c.4)))))))))))))))

(ref-set!
  source/slatex.tex-analog
  (value-procedure (ref (unit)) (function-1 body/source/slatex.tex-analog)))

(define source/slatex.*slatex-case-sensitive?* (ref (value-uninitialized)))

(ref-set! source/slatex.*slatex-case-sensitive?* (value-boolean #t))

(define source/slatex.*slatex-enabled?* (ref (value-uninitialized)))

(ref-set! source/slatex.*slatex-enabled?* (value-boolean #t))

(define source/slatex.*slatex-reenabler* (ref (value-uninitialized)))

(ref-set! source/slatex.*slatex-reenabler* literal.34)

(define source/slatex.*intext-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*intext-triggerers* (primitive/list/1 literal.35))

(define source/slatex.*resultintext-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*resultintext-triggerers* (primitive/list/1 literal.36))

(define source/slatex.*display-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*display-triggerers* (primitive/list/1 literal.37))

(define source/slatex.*box-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*box-triggerers* (primitive/list/1 literal.38))

(define source/slatex.*input-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*input-triggerers* (primitive/list/1 literal.39))

(define source/slatex.*region-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*region-triggerers* (primitive/list/1 literal.40))

(define source/slatex.*math-triggerers* (ref (value-uninitialized)))

(ref-set! source/slatex.*math-triggerers* (value-null))

(define source/slatex.*slatex-in-protected-region?* (ref (value-uninitialized)))

(ref-set! source/slatex.*slatex-in-protected-region?* (value-boolean #f))

(define source/slatex.*protected-files* (ref (value-uninitialized)))

(ref-set! source/slatex.*protected-files* (value-null))

(define source/slatex.*include-onlys* (ref (value-uninitialized)))

(ref-set! source/slatex.*include-onlys* literal.41)

(define source/slatex.*latex?* (ref (value-uninitialized)))

(ref-set! source/slatex.*latex?* (value-boolean #t))

(define source/slatex.*slatex-separate-includes?* (ref (value-uninitialized)))

(ref-set! source/slatex.*slatex-separate-includes?* (value-boolean #f))

(define source/slatex.set-keyword (ref (value-uninitialized)))

(define body/source/slatex.set-keyword
  (lambda (source/x.3)
    (if (value-truth? (body/source/slatex.member-token source/x.3 (binding-value source/slatex.keyword-tokens)))
      literal.42
      (begin
        (begin
          (ref-set!
            source/slatex.constant-tokens
            (body/source/slatex.remove-token!
              source/x.3
              (binding-value source/slatex.constant-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.variable-tokens
            (body/source/slatex.remove-token!
              source/x.3
              (binding-value source/slatex.variable-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.keyword-tokens
            (primitive/cons/2 source/x.3 (binding-value source/slatex.keyword-tokens)))
          (value-unspecified))))))

(ref-set!
  source/slatex.set-keyword
  (value-procedure (ref (unit)) (function-1 body/source/slatex.set-keyword)))

(define source/slatex.set-constant (ref (value-uninitialized)))

(define body/source/slatex.set-constant
  (lambda (source/x.4)
    (if (value-truth? (body/source/slatex.member-token source/x.4 (binding-value source/slatex.constant-tokens)))
      literal.43
      (begin
        (begin
          (ref-set!
            source/slatex.keyword-tokens
            (body/source/slatex.remove-token!
              source/x.4
              (binding-value source/slatex.keyword-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.variable-tokens
            (body/source/slatex.remove-token!
              source/x.4
              (binding-value source/slatex.variable-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.constant-tokens
            (primitive/cons/2 source/x.4 (binding-value source/slatex.constant-tokens)))
          (value-unspecified))))))

(ref-set!
  source/slatex.set-constant
  (value-procedure (ref (unit)) (function-1 body/source/slatex.set-constant)))

(define source/slatex.set-variable (ref (value-uninitialized)))

(define body/source/slatex.set-variable
  (lambda (source/x.5)
    (if (value-truth? (body/source/slatex.member-token source/x.5 (binding-value source/slatex.variable-tokens)))
      literal.44
      (begin
        (begin
          (ref-set!
            source/slatex.keyword-tokens
            (body/source/slatex.remove-token!
              source/x.5
              (binding-value source/slatex.keyword-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.constant-tokens
            (body/source/slatex.remove-token!
              source/x.5
              (binding-value source/slatex.constant-tokens)))
          (value-unspecified))
        (begin
          (ref-set!
            source/slatex.variable-tokens
            (primitive/cons/2 source/x.5 (binding-value source/slatex.variable-tokens)))
          (value-unspecified))))))

(ref-set!
  source/slatex.set-variable
  (value-procedure (ref (unit)) (function-1 body/source/slatex.set-variable)))

(define source/slatex.set-special-symbol (ref (value-uninitialized)))

(define body/source/slatex.set-special-symbol
  (lambda (source/x.6 source/transl)
    ((lambda (source/c.5) (if (value-truth? source/c.5) (primitive/set-cdr!/2 source/c.5 source/transl) (begin (ref-set! source/slatex.special-symbols (primitive/cons/2 (primitive/cons/2 source/x.6 source/transl) (binding-value source/slatex.special-symbols))) (value-unspecified))))
      (body/source/slatex.assoc-token source/x.6 (binding-value source/slatex.special-symbols)))))

(ref-set!
  source/slatex.set-special-symbol
  (value-procedure (ref (unit)) (function-2 body/source/slatex.set-special-symbol)))

(define source/slatex.unset-special-symbol (ref (value-uninitialized)))

(define body/source/slatex.unset-special-symbol
  (lambda (source/x.7)
    (begin
      (ref-set!
        source/slatex.special-symbols
        (body/source/slatex.remove-if!
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/c.6)
                (body/source/slatex.token=? (primitive/car/1 source/c.6) source/x.7))))
          (binding-value source/slatex.special-symbols)))
      (value-unspecified))))

(ref-set!
  source/slatex.unset-special-symbol
  (value-procedure (ref (unit)) (function-1 body/source/slatex.unset-special-symbol)))

(define source/slatex.texify (ref (value-uninitialized)))

(define body/source/slatex.texify
  (lambda (source/s.12)
    (primitive/list->string/1 (invoke-1 (binding-value source/slatex.texify-aux) source/s.12))))

(ref-set!
  source/slatex.texify
  (value-procedure (ref (unit)) (function-1 body/source/slatex.texify)))

(define source/slatex.texify-data (ref (value-uninitialized)))

(define body/source/slatex.texify-data
  (lambda (source/s.13)
    (invoke-2
      ((lambda () (let ((source/loop.12 #f) (body/source/loop.12 #f)) (set! source/loop.12 (ref (value-uninitialized))) (set! body/source/loop.12 (lambda (source/l.17 source/r.3) (if (value-truth? (primitive/null?/1 source/l.17)) (primitive/list->string/1 (body/source/slatex.reverse! source/r.3)) ((lambda (source/c.7) (body/source/loop.12 (primitive/cdr/1 source/l.17) (if (value-truth? (primitive/char=?/2 source/c.7 (value-character #\-))) (body/source/slatex.append! (primitive/list/3 (value-character #\$) source/c.7 (value-character #\$)) source/r.3) (primitive/cons/2 source/c.7 source/r.3)))) (primitive/car/1 source/l.17))))) (ref-set! source/loop.12 (value-procedure (ref (unit)) (function-2 body/source/loop.12))) (binding-value source/loop.12)))
)
      (invoke-1 (binding-value source/slatex.texify-aux) source/s.13)
      (value-null))))

(ref-set!
  source/slatex.texify-data
  (value-procedure (ref (unit)) (function-1 body/source/slatex.texify-data)))

(define source/slatex.texify-aux (ref (value-uninitialized)))

(ref-set!
  source/slatex.texify-aux
  ((lambda (source/arrow) ((lambda (source/arrow-lh) ((lambda () (value-procedure (ref (unit)) (function-1 (lambda (source/s.14) ((lambda (source/sl) ((lambda (source/texified-sl) ((lambda () (begin (body/source/slatex.ormapcdr (value-procedure (ref (unit)) (function-1 (lambda (source/d.1) (begin (if (value-truth? (body/source/slatex.list-prefix? source/arrow source/d.1)) ((lambda (source/to) (begin (primitive/set-car!/2 source/d.1 (primitive/car/1 source/to)) (primitive/set-cdr!/2 source/d.1 (primitive/append/2 (primitive/cdr/1 source/to) (primitive/list-tail/2 source/d.1 source/arrow-lh))))) (primitive/string->list/1 literal.46)) (value-unspecified)) (value-boolean #f))))) source/texified-sl) source/texified-sl)))) (body/source/slatex.append-map! (value-procedure (ref (unit)) (function-1 (lambda (source/c.8) (primitive/string->list/1 (body/source/slatex.tex-analog source/c.8))))) source/sl))) (primitive/string->list/1 source/s.14)))))))) (primitive/length/1 source/arrow)))
    (primitive/string->list/1 literal.45)))

(define source/slatex.display-begin-sequence (ref (value-uninitialized)))

(define body/source/slatex.display-begin-sequence
  (lambda (source/out)
    (if (value-truth? ((lambda (source/value.2) (if (value-truth? source/value.2) source/value.2 (primitive/not/1 (binding-value source/slatex.*latex?*)))) (binding-value source/slatex.*intext?*)))
      (begin
        (primitive/display/2 literal.49 source/out)
        (primitive/display/2 (binding-value source/slatex.*code-env-spec*) source/out)
        (primitive/newline/1 source/out))
      (begin
        (primitive/display/2 literal.47 source/out)
        (primitive/display/2 (binding-value source/slatex.*code-env-spec*) source/out)
        (primitive/display/2 literal.48 source/out)
        (primitive/newline/1 source/out)))))

(ref-set!
  source/slatex.display-begin-sequence
  (value-procedure (ref (unit)) (function-1 body/source/slatex.display-begin-sequence)))

(define source/slatex.display-end-sequence (ref (value-uninitialized)))

(define body/source/slatex.display-end-sequence
  (lambda (source/out.1)
    (if (value-truth? ((lambda (source/value.3) (if (value-truth? source/value.3) source/value.3 (primitive/not/1 (binding-value source/slatex.*latex?*)))) (binding-value source/slatex.*intext?*)))
      (begin
        (primitive/display/2 literal.52 source/out.1)
        (primitive/display/2 (binding-value source/slatex.*code-env-spec*) source/out.1)
        (primitive/newline/1 source/out.1))
      (begin
        (primitive/display/2 literal.50 source/out.1)
        (primitive/display/2 (binding-value source/slatex.*code-env-spec*) source/out.1)
        (primitive/display/2 literal.51 source/out.1)
        (primitive/newline/1 source/out.1)))))

(ref-set!
  source/slatex.display-end-sequence
  (value-procedure (ref (unit)) (function-1 body/source/slatex.display-end-sequence)))

(define source/slatex.display-tex-char (ref (value-uninitialized)))

(define body/source/slatex.display-tex-char
  (lambda (source/c.9 source/p.1)
    (primitive/display/2
      (if (value-truth? (primitive/char?/1 source/c.9))
        (body/source/slatex.tex-analog source/c.9)
        source/c.9)
      source/p.1)))

(ref-set!
  source/slatex.display-tex-char
  (value-procedure (ref (unit)) (function-2 body/source/slatex.display-tex-char)))

(define source/slatex.display-token (ref (value-uninitialized)))

(define body/source/slatex.display-token
  (lambda (source/s.15 source/typ source/p.2)
    (if (value-truth? (primitive/eq?/2 source/typ literal.65))
      (begin
        (primitive/display/2 literal.63 source/p.2)
        (primitive/display/2 (body/source/slatex.texify source/s.15) source/p.2)
        (primitive/display/2 literal.64 source/p.2))
      (if (value-truth? (primitive/eq?/2 source/typ literal.62))
        (begin
          (primitive/display/2 literal.60 source/p.2)
          (primitive/display/2 (body/source/slatex.texify source/s.15) source/p.2)
          (primitive/display/2 literal.61 source/p.2))
        (if (value-truth? (primitive/eq?/2 source/typ literal.59))
          (begin
            (primitive/display/2 literal.57 source/p.2)
            (primitive/display/2 (body/source/slatex.texify source/s.15) source/p.2)
            (primitive/display/2 literal.58 source/p.2))
          (if (value-truth? (primitive/eq?/2 source/typ literal.56))
            (begin
              (primitive/display/2 literal.54 source/p.2)
              (primitive/display/2 (body/source/slatex.texify-data source/s.15) source/p.2)
              (primitive/display/2 literal.55 source/p.2))
            (body/source/slatex.error literal.53 source/typ)))))))

(ref-set!
  source/slatex.display-token
  (value-procedure (ref (unit)) (function-3 body/source/slatex.display-token)))

(define source/slatex.*max-line-length* (ref (value-uninitialized)))

(ref-set! source/slatex.*max-line-length* (value-number (exact-number 200)))

(define source/slatex.&inner-space (ref (value-uninitialized)))

(ref-set! source/slatex.&inner-space (primitive/integer->char/1 (value-number (exact-number 7))))

(define source/slatex.&quote-space (ref (value-uninitialized)))

(ref-set! source/slatex.&quote-space (primitive/integer->char/1 (value-number (exact-number 6))))

(define source/slatex.&bracket-space (ref (value-uninitialized)))

(ref-set! source/slatex.&bracket-space (primitive/integer->char/1 (value-number (exact-number 5))))

(define source/slatex.&paren-space (ref (value-uninitialized)))

(ref-set! source/slatex.&paren-space (primitive/integer->char/1 (value-number (exact-number 4))))

(define source/slatex.&init-plain-space (ref (value-uninitialized)))

(ref-set!
  source/slatex.&init-plain-space
  (primitive/integer->char/1 (value-number (exact-number 3))))

(define source/slatex.&init-space (ref (value-uninitialized)))

(ref-set! source/slatex.&init-space (primitive/integer->char/1 (value-number (exact-number 2))))

(define source/slatex.&plain-space (ref (value-uninitialized)))

(ref-set! source/slatex.&plain-space (primitive/integer->char/1 (value-number (exact-number 1))))

(define source/slatex.&void-space (ref (value-uninitialized)))

(ref-set! source/slatex.&void-space (primitive/integer->char/1 (value-number (exact-number 0))))

(define source/slatex.&plain-crg-ret (ref (value-uninitialized)))

(ref-set! source/slatex.&plain-crg-ret (primitive/integer->char/1 (value-number (exact-number 4))))

(define source/slatex.&tabbed-crg-ret (ref (value-uninitialized)))

(ref-set! source/slatex.&tabbed-crg-ret (primitive/integer->char/1 (value-number (exact-number 3))))

(define source/slatex.&move-tab (ref (value-uninitialized)))

(ref-set! source/slatex.&move-tab (primitive/integer->char/1 (value-number (exact-number 2))))

(define source/slatex.&set-tab (ref (value-uninitialized)))

(ref-set! source/slatex.&set-tab (primitive/integer->char/1 (value-number (exact-number 1))))

(define source/slatex.&void-tab (ref (value-uninitialized)))

(ref-set! source/slatex.&void-tab (primitive/integer->char/1 (value-number (exact-number 0))))

(define source/slatex.&end-math (ref (value-uninitialized)))

(ref-set! source/slatex.&end-math (primitive/integer->char/1 (value-number (exact-number 8))))

(define source/slatex.&mid-math (ref (value-uninitialized)))

(ref-set! source/slatex.&mid-math (primitive/integer->char/1 (value-number (exact-number 7))))

(define source/slatex.&begin-math (ref (value-uninitialized)))

(ref-set! source/slatex.&begin-math (primitive/integer->char/1 (value-number (exact-number 6))))

(define source/slatex.&end-string (ref (value-uninitialized)))

(ref-set! source/slatex.&end-string (primitive/integer->char/1 (value-number (exact-number 5))))

(define source/slatex.&mid-string (ref (value-uninitialized)))

(ref-set! source/slatex.&mid-string (primitive/integer->char/1 (value-number (exact-number 4))))

(define source/slatex.&begin-string (ref (value-uninitialized)))

(ref-set! source/slatex.&begin-string (primitive/integer->char/1 (value-number (exact-number 3))))

(define source/slatex.&mid-comment (ref (value-uninitialized)))

(ref-set! source/slatex.&mid-comment (primitive/integer->char/1 (value-number (exact-number 2))))

(define source/slatex.&begin-comment (ref (value-uninitialized)))

(ref-set! source/slatex.&begin-comment (primitive/integer->char/1 (value-number (exact-number 1))))

(define source/slatex.&void-notab (ref (value-uninitialized)))

(ref-set! source/slatex.&void-notab (primitive/integer->char/1 (value-number (exact-number 0))))

(define source/slatex.make-raw-line (ref (value-uninitialized)))

(define body/source/slatex.make-raw-line
  (lambda () (primitive/make-vector/1 (value-number (exact-number 5)))))

(ref-set!
  source/slatex.make-raw-line
  (value-procedure (ref (unit)) (function-0 body/source/slatex.make-raw-line)))

(define source/slatex.=notab (ref (value-uninitialized)))

(ref-set! source/slatex.=notab (value-number (exact-number 4)))

(define source/slatex.=tab (ref (value-uninitialized)))

(ref-set! source/slatex.=tab (value-number (exact-number 3)))

(define source/slatex.=space (ref (value-uninitialized)))

(ref-set! source/slatex.=space (value-number (exact-number 2)))

(define source/slatex.=char (ref (value-uninitialized)))

(ref-set! source/slatex.=char (value-number (exact-number 1)))

(define source/slatex.=rtedge (ref (value-uninitialized)))

(ref-set! source/slatex.=rtedge (value-number (exact-number 0)))

(define source/slatex.make-line (ref (value-uninitialized)))

(define body/source/slatex.make-line
  (lambda ()
    ((lambda (source/l.18) (begin (primitive/vector-set!/3 source/l.18 (binding-value source/slatex.=rtedge) (value-number (exact-number 0))) (primitive/vector-set!/3 source/l.18 (binding-value source/slatex.=char) (primitive/make-string/2 (binding-value source/slatex.*max-line-length*) (value-character #\space))) (primitive/vector-set!/3 source/l.18 (binding-value source/slatex.=space) (primitive/make-string/2 (binding-value source/slatex.*max-line-length*) (binding-value source/slatex.&void-space))) (primitive/vector-set!/3 source/l.18 (binding-value source/slatex.=tab) (primitive/make-string/2 (binding-value source/slatex.*max-line-length*) (binding-value source/slatex.&void-tab))) (primitive/vector-set!/3 source/l.18 (binding-value source/slatex.=notab) (primitive/make-string/2 (binding-value source/slatex.*max-line-length*) (binding-value source/slatex.&void-notab))) source/l.18))
      (body/source/slatex.make-raw-line))))

(ref-set!
  source/slatex.make-line
  (value-procedure (ref (unit)) (function-0 body/source/slatex.make-line)))

(define source/slatex.*line1* (ref (value-uninitialized)))

(ref-set! source/slatex.*line1* (body/source/slatex.make-line))

(define source/slatex.*line2* (ref (value-uninitialized)))

(ref-set! source/slatex.*line2* (body/source/slatex.make-line))

(define source/slatex.make-case-frame (ref (value-uninitialized)))

(define body/source/slatex.make-case-frame
  (lambda () (primitive/make-vector/1 (value-number (exact-number 3)))))

(ref-set!
  source/slatex.make-case-frame
  (value-procedure (ref (unit)) (function-0 body/source/slatex.make-case-frame)))

(define source/slatex.=in-case-exp (ref (value-uninitialized)))

(ref-set! source/slatex.=in-case-exp (value-number (exact-number 2)))

(define source/slatex.=in-bktd-ctag-exp (ref (value-uninitialized)))

(ref-set! source/slatex.=in-bktd-ctag-exp (value-number (exact-number 1)))

(define source/=in-ctag-tkn (ref (value-uninitialized)))

(ref-set! source/=in-ctag-tkn (value-number (exact-number 0)))

(define source/slatex.make-bq-frame (ref (value-uninitialized)))

(define body/source/slatex.make-bq-frame
  (lambda () (primitive/make-vector/1 (value-number (exact-number 3)))))

(ref-set!
  source/slatex.make-bq-frame
  (value-procedure (ref (unit)) (function-0 body/source/slatex.make-bq-frame)))

(define source/slatex.=in-bktd-bq-exp (ref (value-uninitialized)))

(ref-set! source/slatex.=in-bktd-bq-exp (value-number (exact-number 2)))

(define source/slatex.=in-bq-tkn (ref (value-uninitialized)))

(ref-set! source/slatex.=in-bq-tkn (value-number (exact-number 1)))

(define source/slatex.=in-comma (ref (value-uninitialized)))

(ref-set! source/slatex.=in-comma (value-number (exact-number 0)))

(define source/slatex.*latex-paragraph-mode?* (ref (value-uninitialized)))

(ref-set! source/slatex.*latex-paragraph-mode?* literal.66)

(define source/slatex.*intext?* (ref (value-uninitialized)))

(ref-set! source/slatex.*intext?* literal.67)

(define source/slatex.*code-env-spec* (ref (value-uninitialized)))

(ref-set! source/slatex.*code-env-spec* literal.68)

(define source/slatex.*in* (ref (value-uninitialized)))

(ref-set! source/slatex.*in* literal.69)

(define source/slatex.*out* (ref (value-uninitialized)))

(ref-set! source/slatex.*out* literal.70)

(define source/slatex.*in-qtd-tkn* (ref (value-uninitialized)))

(ref-set! source/slatex.*in-qtd-tkn* literal.71)

(define source/slatex.*in-bktd-qtd-exp* (ref (value-uninitialized)))

(ref-set! source/slatex.*in-bktd-qtd-exp* literal.72)

(define source/slatex.*in-mac-tkn* (ref (value-uninitialized)))

(ref-set! source/slatex.*in-mac-tkn* literal.73)

(define source/slatex.*in-bktd-mac-exp* (ref (value-uninitialized)))

(ref-set! source/slatex.*in-bktd-mac-exp* literal.74)

(define source/slatex.*case-stack* (ref (value-uninitialized)))

(ref-set! source/slatex.*case-stack* literal.75)

(define source/slatex.*bq-stack* (ref (value-uninitialized)))

(ref-set! source/slatex.*bq-stack* literal.76)

(define source/slatex.display-space (ref (value-uninitialized)))

(define body/source/slatex.display-space
  (lambda (source/s.16 source/p.3)
    (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&plain-space)))
      (primitive/display/2 (value-character #\space) source/p.3)
      (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&init-plain-space)))
        (primitive/display/2 (value-character #\space) source/p.3)
        (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&init-space)))
          (primitive/display/2 literal.81 source/p.3)
          (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&paren-space)))
            (primitive/display/2 literal.80 source/p.3)
            (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&bracket-space)))
              (primitive/display/2 literal.79 source/p.3)
              (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&quote-space)))
                (primitive/display/2 literal.78 source/p.3)
                (if (value-truth? (primitive/eqv?/2 source/s.16 (binding-value source/slatex.&inner-space)))
                  (primitive/display/2 literal.77 source/p.3)
                  (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))))))))))

(ref-set!
  source/slatex.display-space
  (value-procedure (ref (unit)) (function-2 body/source/slatex.display-space)))

(define source/slatex.display-tab (ref (value-uninitialized)))

(define body/source/slatex.display-tab
  (lambda (source/tab source/p.4)
    (if (value-truth? (primitive/eqv?/2 source/tab (binding-value source/slatex.&set-tab)))
      (primitive/display/2 literal.83 source/p.4)
      (if (value-truth? (primitive/eqv?/2 source/tab (binding-value source/slatex.&move-tab)))
        (primitive/display/2 literal.82 source/p.4)
        (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))))

(ref-set!
  source/slatex.display-tab
  (value-procedure (ref (unit)) (function-2 body/source/slatex.display-tab)))

(define source/slatex.display-notab (ref (value-uninitialized)))

(define body/source/slatex.display-notab
  (lambda (source/notab source/p.5)
    (if (value-truth? (primitive/eqv?/2 source/notab (binding-value source/slatex.&begin-string)))
      (primitive/display/2 literal.85 source/p.5)
      (if (value-truth? (primitive/eqv?/2 source/notab (binding-value source/slatex.&end-string)))
        (primitive/display/2 literal.84 source/p.5)
        (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))))

(ref-set!
  source/slatex.display-notab
  (value-procedure (ref (unit)) (function-2 body/source/slatex.display-notab)))

(define source/slatex.get-line (ref (value-uninitialized)))

(ref-set!
  source/slatex.get-line
  ((lambda (argument) (let ((source/curr-notab (ref argument))) (value-procedure (ref (unit)) (function-1 (lambda (source/line) ((lambda (argument.1) (let ((source/graphic-char-seen? (ref argument.1))) (invoke-1 ((lambda () (let ((source/loop.13 #f) (body/source/loop.13 #f)) (set! source/loop.13 (ref (value-uninitialized))) (set! body/source/loop.13 (lambda (source/i.7) ((lambda (argument.2) (let ((source/c.10 (ref argument.2))) (begin (if (value-truth? (ref-get source/graphic-char-seen?)) literal.87 (if (value-truth? ((lambda (source/value.4) (if (value-truth? source/value.4) source/value.4 ((lambda (source/value.5) (if (value-truth? source/value.5) source/value.5 ((lambda (source/value.6) (if (value-truth? source/value.6) source/value.6 ((lambda (source/value.7) (if (value-truth? source/value.7) source/value.7 (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*tab*)))) (primitive/char=?/2 (ref-get source/c.10) (value-character #\space))))) (primitive/char=?/2 (ref-get source/c.10) (value-character #\newline))))) (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*return*))))) (primitive/eof-object?/1 (ref-get source/c.10)))) literal.86 (begin (ref-set! source/graphic-char-seen? (value-boolean #t)) (value-unspecified)))) (if (value-truth? (primitive/eof-object?/1 (ref-get source/c.10))) (begin (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-string))) (if (value-truth? (primitive/>/2 source/i.7 (value-number (exact-number 0)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (primitive/-/2 source/i.7 (value-number (exact-number 1))) (binding-value source/slatex.&end-string)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-comment))) (begin (ref-set! source/curr-notab (binding-value source/slatex.&void-notab)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-math))) (body/source/slatex.error literal.91 literal.92) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (value-character #\newline)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&void-notab)) (primitive/vector-set!/3 source/line (binding-value source/slatex.=rtedge) source/i.7) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (value-number (exact-number 0))) (binding-value source/slatex.&mid-string))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (value-number (exact-number 0)) (binding-value source/slatex.&begin-string)) (value-unspecified)) (if (value-truth? (primitive/=/2 source/i.7 (value-number (exact-number 0)))) (value-boolean #f) (value-boolean #t))) (if (value-truth? ((lambda (source/value.8) (if (value-truth? source/value.8) source/value.8 (primitive/char=?/2 (ref-get source/c.10) (value-character #\newline)))) (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*return*)))) (begin (if (value-truth? (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.88)) (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*return*)) (value-boolean #f))) (if (value-truth? (primitive/char=?/2 (primitive/peek-char/1 (binding-value source/slatex.*in*)) (value-character #\newline))) (primitive/read-char/1 (binding-value source/slatex.*in*)) (value-unspecified)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-string))) (if (value-truth? (primitive/>/2 source/i.7 (value-number (exact-number 0)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (primitive/-/2 source/i.7 (value-number (exact-number 1))) (binding-value source/slatex.&end-string)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-comment))) (begin (ref-set! source/curr-notab (binding-value source/slatex.&void-notab)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-math))) (body/source/slatex.error literal.89 literal.90) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (value-character #\newline)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (if (value-truth? (primitive/eof-object?/1 (primitive/peek-char/1 (binding-value source/slatex.*in*)))) (binding-value source/slatex.&plain-crg-ret) (if (value-truth? (binding-value source/slatex.*intext?*)) (binding-value source/slatex.&plain-crg-ret) (binding-value source/slatex.&tabbed-crg-ret)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&void-notab)) (primitive/vector-set!/3 source/line (binding-value source/slatex.=rtedge) source/i.7) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (value-number (exact-number 0))) (binding-value source/slatex.&mid-string))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) (value-number (exact-number 0)) (binding-value source/slatex.&begin-string)) (value-unspecified)) (value-boolean #t)) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-comment))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\space))) (binding-value source/slatex.&plain-space) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*tab*))) (binding-value source/slatex.&plain-space) (binding-value source/slatex.&void-space)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&mid-comment)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\\))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (ref-get source/curr-notab)) ((lambda (source/i+1 argument.3) (let ((source/c+1 (ref argument.3))) (begin (if (value-truth? (primitive/char=?/2 (ref-get source/c+1) (binding-value source/slatex.*tab*))) (begin (ref-set! source/c+1 (value-character #\space)) (value-unspecified)) (value-unspecified)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i+1 (ref-get source/c+1)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i+1 (if (value-truth? (primitive/char=?/2 (ref-get source/c+1) (value-character #\space))) (binding-value source/slatex.&plain-space) (binding-value source/slatex.&void-space))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i+1 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i+1 (ref-get source/curr-notab)) (body/source/loop.13 (primitive/+/2 source/i+1 (value-number (exact-number 1))))))) (primitive/+/2 source/i.7 (value-number (exact-number 1))) (primitive/read-char/1 (binding-value source/slatex.*in*)))) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-math))) (begin (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*tab*))) (begin (ref-set! source/c.10 (value-character #\space)) (value-unspecified)) (value-unspecified)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\space))) (binding-value source/slatex.&plain-space) (binding-value source/slatex.&void-space))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (if (value-truth? (primitive/memv/2 (ref-get source/c.10) (binding-value source/slatex.*math-triggerers*))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (value-character #\$)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&end-math)) (begin (ref-set! source/curr-notab (binding-value source/slatex.&void-notab)) (value-unspecified))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&mid-math)))) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (ref-get source/curr-notab) (binding-value source/slatex.&mid-string))) (begin (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*tab*))) (begin (ref-set! source/c.10 (value-character #\space)) (value-unspecified)) (value-unspecified)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\space))) (binding-value source/slatex.&inner-space) (binding-value source/slatex.&void-space))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\"))) (begin (begin (ref-set! source/curr-notab (binding-value source/slatex.&void-notab)) (value-unspecified)) (binding-value source/slatex.&end-string)) (binding-value source/slatex.&mid-string))) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\space))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (if (value-truth? (binding-value source/slatex.*intext?*)) (binding-value source/slatex.&plain-space) (if (value-truth? (ref-get source/graphic-char-seen?)) (binding-value source/slatex.&inner-space) (binding-value source/slatex.&init-space)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&void-notab)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (binding-value source/slatex.*tab*))) (begin (invoke-2 ((lambda () (let ((source/loop2 #f) (body/source/loop2 #f)) (set! source/loop2 (ref (value-uninitialized))) (set! body/source/loop2 (lambda (source/i.8 source/j.1) (if (value-truth? (primitive/</2 source/j.1 (value-number (exact-number 8)))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.8 (value-character #\space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.8 (if (value-truth? (binding-value source/slatex.*intext?*)) (binding-value source/slatex.&plain-space) (if (value-truth? (ref-get source/graphic-char-seen?)) (binding-value source/slatex.&inner-space) (binding-value source/slatex.&init-space)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.8 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.8 (binding-value source/slatex.&void-notab)) (body/source/loop2 (primitive/+/2 source/i.8 (value-number (exact-number 1))) (primitive/+/2 source/j.1 (value-number (exact-number 1))))) (value-unspecified)))) (ref-set! source/loop2 (value-procedure (ref (unit)) (function-2 body/source/loop2))) (binding-value source/loop2)))) source/i.7 (value-number (exact-number 0))) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 8))))) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\"))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&begin-string)) (begin (ref-set! source/curr-notab (binding-value source/slatex.&mid-string)) (value-unspecified)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 (ref-get source/c.10) (value-character #\;))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&begin-comment)) (begin (ref-set! source/curr-notab (binding-value source/slatex.&mid-comment)) (value-unspecified)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (if (value-truth? (primitive/memv/2 (ref-get source/c.10) (binding-value source/slatex.*math-triggerers*))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (value-character #\$)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&begin-math)) (begin (ref-set! source/curr-notab (binding-value source/slatex.&mid-math)) (value-unspecified)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=char)) source/i.7 (ref-get source/c.10)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=space)) source/i.7 (binding-value source/slatex.&void-space)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=tab)) source/i.7 (binding-value source/slatex.&void-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/line (binding-value source/slatex.=notab)) source/i.7 (binding-value source/slatex.&void-notab)) (body/source/loop.13 (primitive/+/2 source/i.7 (value-number (exact-number 1))))))))))))))))))) (primitive/read-char/1 (binding-value source/slatex.*in*))))) (ref-set! source/loop.13 (value-procedure (ref (unit)) (function-1 body/source/loop.13))) (binding-value source/loop.13)))) (value-number (exact-number 0))))) (value-boolean #f)))))))
    (binding-value source/slatex.&void-notab)))

(define source/slatex.peephole-adjust (ref (value-uninitialized)))

(define body/source/slatex.peephole-adjust
  (lambda (source/curr source/prev)
    (if (value-truth? ((lambda (source/value.13) (if (value-truth? source/value.13) source/value.13 (body/source/slatex.flush-comment-line? source/curr))) (body/source/slatex.blank-line? source/curr)))
      (if (value-truth? (binding-value source/slatex.*latex-paragraph-mode?*))
        literal.101
        (begin
          (begin
            (ref-set! source/slatex.*latex-paragraph-mode?* (value-boolean #t))
            (value-unspecified))
          (if (value-truth? (binding-value source/slatex.*intext?*))
            literal.100
            (begin
              (body/source/slatex.remove-some-tabs source/prev (value-number (exact-number 0)))
              ((lambda (source/prev-rtedge) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/prev-rtedge) (binding-value source/slatex.&tabbed-crg-ret))) (primitive/string-set!/3 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) (primitive/vector-ref/2 source/prev (binding-value source/slatex.=rtedge)) (binding-value source/slatex.&plain-crg-ret)) (value-unspecified)))
                (primitive/vector-ref/2 source/prev (binding-value source/slatex.=rtedge)))))))
      (begin
        (if (value-truth? (binding-value source/slatex.*latex-paragraph-mode?*))
          (begin
            (ref-set! source/slatex.*latex-paragraph-mode?* (value-boolean #f))
            (value-unspecified))
          (if (value-truth? (binding-value source/slatex.*intext?*))
            literal.98
            ((lambda (argument.4) (let ((source/remove-tabs-from (ref argument.4))) (begin (invoke-1 ((lambda () (let ((source/loop.14 #f) (body/source/loop.14 #f)) (set! source/loop.14 (ref (value-uninitialized))) (set! body/source/loop.14 (lambda (source/i.9) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=char)) source/i.9) (value-character #\newline))) (begin (ref-set! source/remove-tabs-from source/i.9) (value-unspecified)) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) source/i.9) (value-character #\newline))) (begin (ref-set! source/remove-tabs-from (value-boolean #f)) (value-unspecified)) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=space)) source/i.9) (binding-value source/slatex.&init-space))) (begin (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=notab)) source/i.9) (binding-value source/slatex.&void-notab))) (begin (if (value-truth? ((lambda (source/value.12) (if (value-truth? source/value.12) source/value.12 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=space)) source/i.9) (binding-value source/slatex.&paren-space)))) (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) source/i.9) (value-character #\()))) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=space)) source/i.9 (binding-value source/slatex.&paren-space)) (if (value-truth? ((lambda (source/value.11) (if (value-truth? source/value.11) source/value.11 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=space)) source/i.9) (binding-value source/slatex.&bracket-space)))) (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) source/i.9) (value-character #\[)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=space)) source/i.9 (binding-value source/slatex.&bracket-space)) (if (value-truth? ((lambda (source/value.10) (if (value-truth? source/value.10) source/value.10 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=space)) source/i.9) (binding-value source/slatex.&quote-space)))) (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) source/i.9) literal.97))) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=space)) source/i.9 (binding-value source/slatex.&quote-space)) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))) (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/i.9) (primitive/list/2 (binding-value source/slatex.&set-tab) (binding-value source/slatex.&move-tab)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=tab)) source/i.9 (binding-value source/slatex.&move-tab)) (value-unspecified))) (value-unspecified)) (body/source/loop.14 (primitive/+/2 source/i.9 (value-number (exact-number 1))))) (if (value-truth? (primitive/=/2 source/i.9 (value-number (exact-number 0)))) (begin (ref-set! source/remove-tabs-from (value-number (exact-number 0))) (value-unspecified)) (if (value-truth? (primitive/not/1 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/i.9) (binding-value source/slatex.&void-tab)))) (begin (begin (ref-set! source/remove-tabs-from (primitive/+/2 source/i.9 (value-number (exact-number 1)))) (value-unspecified)) (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/i.9) (primitive/list/2 (binding-value source/slatex.&set-tab) (binding-value source/slatex.&move-tab)))) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=tab)) source/i.9 (binding-value source/slatex.&move-tab)) (value-unspecified))) (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=space)) source/i.9) (primitive/list/5 (binding-value source/slatex.&init-space) (binding-value source/slatex.&init-plain-space) (binding-value source/slatex.&paren-space) (binding-value source/slatex.&bracket-space) (binding-value source/slatex.&quote-space)))) (begin (ref-set! source/remove-tabs-from (primitive/+/2 source/i.9 (value-number (exact-number 1)))) (value-unspecified)) (if (value-truth? (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) (primitive/-/2 source/i.9 (value-number (exact-number 1)))) (value-character #\space))) (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=notab)) (primitive/-/2 source/i.9 (value-number (exact-number 1)))) (binding-value source/slatex.&void-notab)) (value-boolean #f))) (begin (begin (ref-set! source/remove-tabs-from (primitive/+/2 source/i.9 (value-number (exact-number 1)))) (value-unspecified)) (primitive/string-set!/3 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/i.9 (binding-value source/slatex.&set-tab)) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=tab)) source/i.9 (binding-value source/slatex.&move-tab))) (begin (begin (ref-set! source/remove-tabs-from (primitive/+/2 source/i.9 (value-number (exact-number 1)))) (value-unspecified)) (invoke-1 ((lambda () (let ((source/loop1 #f) (body/source/loop1 #f)) (set! source/loop1 (ref (value-uninitialized))) (set! body/source/loop1 (lambda (source/j.2) (if (value-truth? (primitive/<=/2 source/j.2 (value-number (exact-number 0)))) literal.96 (if (value-truth? (primitive/not/1 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=tab)) source/j.2) (binding-value source/slatex.&void-tab)))) literal.95 (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=space)) source/j.2) (primitive/list/3 (binding-value source/slatex.&paren-space) (binding-value source/slatex.&bracket-space) (binding-value source/slatex.&quote-space)))) (body/source/loop1 (primitive/-/2 source/j.2 (value-number (exact-number 1)))) (if (value-truth? ((lambda (source/value.9) (if (value-truth? source/value.9) source/value.9 (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=char)) source/j.2) (value-character #\space)))) (primitive/not/1 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=notab)) source/j.2) (binding-value source/slatex.&void-notab))))) ((lambda (source/k.1) (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=notab)) source/k.1) (primitive/list/5 (binding-value source/slatex.&mid-comment) (binding-value source/slatex.&mid-math) (binding-value source/slatex.&end-math) (binding-value source/slatex.&mid-string) (binding-value source/slatex.&end-string)))) literal.94 (begin (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/k.1) (binding-value source/slatex.&void-tab))) (primitive/string-set!/3 (primitive/vector-ref/2 source/prev (binding-value source/slatex.=tab)) source/k.1 (binding-value source/slatex.&set-tab)) (value-unspecified)) (primitive/string-set!/3 (primitive/vector-ref/2 source/curr (binding-value source/slatex.=tab)) source/k.1 (binding-value source/slatex.&move-tab))))) (primitive/+/2 source/j.2 (value-number (exact-number 1)))) literal.93)))))) (ref-set! source/loop1 (value-procedure (ref (unit)) (function-1 body/source/loop1))) (binding-value source/loop1)))) (primitive/-/2 source/i.9 (value-number (exact-number 1)))))))))))))) (ref-set! source/loop.14 (value-procedure (ref (unit)) (function-1 body/source/loop.14))) (binding-value source/loop.14)))) (value-number (exact-number 0))) (body/source/slatex.remove-some-tabs source/prev (ref-get source/remove-tabs-from)))))
              (value-boolean #f))))
        (if (value-truth? (binding-value source/slatex.*intext?*))
          literal.99
          (body/source/slatex.add-some-tabs source/curr))
        (body/source/slatex.clean-init-spaces source/curr)
        (body/source/slatex.clean-inner-spaces source/curr)))))

(ref-set!
  source/slatex.peephole-adjust
  (value-procedure (ref (unit)) (function-2 body/source/slatex.peephole-adjust)))

(define source/slatex.add-some-tabs (ref (value-uninitialized)))

(define body/source/slatex.add-some-tabs
  (lambda (source/line.1)
    (invoke-2
      ((lambda () (let ((source/loop.15 #f) (body/source/loop.15 #f)) (set! source/loop.15 (ref (value-uninitialized))) (set! body/source/loop.15 (lambda (source/i.10 source/succ-parens?) ((lambda (source/c.11) (if (value-truth? (primitive/char=?/2 source/c.11 (value-character #\newline))) literal.103 (if (value-truth? (primitive/not/1 (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=notab)) source/i.10) (binding-value source/slatex.&void-notab)))) (body/source/loop.15 (primitive/+/2 source/i.10 (value-number (exact-number 1))) (value-boolean #f)) (if (value-truth? (primitive/char=?/2 source/c.11 (value-character #\[))) (begin (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=tab)) source/i.10) (binding-value source/slatex.&void-tab))) (primitive/string-set!/3 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=tab)) source/i.10 (binding-value source/slatex.&set-tab)) (value-unspecified)) (body/source/loop.15 (primitive/+/2 source/i.10 (value-number (exact-number 1))) (value-boolean #f))) (if (value-truth? (primitive/char=?/2 source/c.11 (value-character #\())) (begin (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=tab)) source/i.10) (binding-value source/slatex.&void-tab))) (if (value-truth? source/succ-parens?) literal.102 (primitive/string-set!/3 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=tab)) source/i.10 (binding-value source/slatex.&set-tab))) (value-unspecified)) (body/source/loop.15 (primitive/+/2 source/i.10 (value-number (exact-number 1))) (value-boolean #t))) (body/source/loop.15 (primitive/+/2 source/i.10 (value-number (exact-number 1))) (value-boolean #f))))))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.1 (binding-value source/slatex.=char)) source/i.10)))) (ref-set! source/loop.15 (value-procedure (ref (unit)) (function-2 body/source/loop.15))) (binding-value source/loop.15)))
)
      (value-number (exact-number 1))
      (value-boolean #f))))

(ref-set!
  source/slatex.add-some-tabs
  (value-procedure (ref (unit)) (function-1 body/source/slatex.add-some-tabs)))

(define source/slatex.remove-some-tabs (ref (value-uninitialized)))

(define body/source/slatex.remove-some-tabs
  (lambda (source/line.2 source/i.11)
    (if (value-truth? source/i.11)
      (invoke-1
        ((lambda () (let ((source/loop.16 #f) (body/source/loop.16 #f)) (set! source/loop.16 (ref (value-uninitialized))) (set! body/source/loop.16 (lambda (source/i.12) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.2 (binding-value source/slatex.=char)) source/i.12) (value-character #\newline))) literal.104 (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.2 (binding-value source/slatex.=tab)) source/i.12) (binding-value source/slatex.&set-tab))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line.2 (binding-value source/slatex.=tab)) source/i.12 (binding-value source/slatex.&void-tab)) (body/source/loop.16 (primitive/+/2 source/i.12 (value-number (exact-number 1))))) (body/source/loop.16 (primitive/+/2 source/i.12 (value-number (exact-number 1)))))))) (ref-set! source/loop.16 (value-procedure (ref (unit)) (function-1 body/source/loop.16))) (binding-value source/loop.16)))
)
        source/i.11)
      (value-unspecified))))

(ref-set!
  source/slatex.remove-some-tabs
  (value-procedure (ref (unit)) (function-2 body/source/slatex.remove-some-tabs)))

(define source/slatex.clean-init-spaces (ref (value-uninitialized)))

(define body/source/slatex.clean-init-spaces
  (lambda (source/line.3)
    (invoke-1
      ((lambda () (let ((source/loop.17 #f) (body/source/loop.17 #f)) (set! source/loop.17 (ref (value-uninitialized))) (set! body/source/loop.17 (lambda (source/i.13) (if (value-truth? (primitive/</2 source/i.13 (value-number (exact-number 0)))) literal.106 (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.3 (binding-value source/slatex.=tab)) source/i.13) (binding-value source/slatex.&move-tab))) (invoke-1 ((lambda () (let ((source/loop2.1 #f) (body/source/loop2.1 #f)) (set! source/loop2.1 (ref (value-uninitialized))) (set! body/source/loop2.1 (lambda (source/i.14) (if (value-truth? (primitive/</2 source/i.14 (value-number (exact-number 0)))) literal.105 (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.3 (binding-value source/slatex.=space)) source/i.14) (primitive/list/4 (binding-value source/slatex.&init-space) (binding-value source/slatex.&paren-space) (binding-value source/slatex.&bracket-space) (binding-value source/slatex.&quote-space)))) (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line.3 (binding-value source/slatex.=space)) source/i.14 (binding-value source/slatex.&init-plain-space)) (body/source/loop2.1 (primitive/-/2 source/i.14 (value-number (exact-number 1))))) (body/source/loop2.1 (primitive/-/2 source/i.14 (value-number (exact-number 1)))))))) (ref-set! source/loop2.1 (value-procedure (ref (unit)) (function-1 body/source/loop2.1))) (binding-value source/loop2.1)))) (primitive/-/2 source/i.13 (value-number (exact-number 1)))) (body/source/loop.17 (primitive/-/2 source/i.13 (value-number (exact-number 1)))))))) (ref-set! source/loop.17 (value-procedure (ref (unit)) (function-1 body/source/loop.17))) (binding-value source/loop.17)))
)
      (primitive/vector-ref/2 source/line.3 (binding-value source/slatex.=rtedge)))))

(ref-set!
  source/slatex.clean-init-spaces
  (value-procedure (ref (unit)) (function-1 body/source/slatex.clean-init-spaces)))

(define source/slatex.clean-inner-spaces (ref (value-uninitialized)))

(define body/source/slatex.clean-inner-spaces
  (lambda (source/line.4)
    (invoke-2
      ((lambda () (let ((source/loop.18 #f) (body/source/loop.18 #f)) (set! source/loop.18 (ref (value-uninitialized))) (set! body/source/loop.18 (lambda (source/i.15 source/succ-inner-spaces?) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.4 (binding-value source/slatex.=char)) source/i.15) (value-character #\newline))) literal.108 (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.4 (binding-value source/slatex.=space)) source/i.15) (binding-value source/slatex.&inner-space))) (begin (if (value-truth? source/succ-inner-spaces?) literal.107 (primitive/string-set!/3 (primitive/vector-ref/2 source/line.4 (binding-value source/slatex.=space)) source/i.15 (binding-value source/slatex.&plain-space))) (body/source/loop.18 (primitive/+/2 source/i.15 (value-number (exact-number 1))) (value-boolean #t))) (body/source/loop.18 (primitive/+/2 source/i.15 (value-number (exact-number 1))) (value-boolean #f)))))) (ref-set! source/loop.18 (value-procedure (ref (unit)) (function-2 body/source/loop.18))) (binding-value source/loop.18)))
)
      (value-number (exact-number 0))
      (value-boolean #f))))

(ref-set!
  source/slatex.clean-inner-spaces
  (value-procedure (ref (unit)) (function-1 body/source/slatex.clean-inner-spaces)))

(define source/slatex.blank-line? (ref (value-uninitialized)))

(define body/source/slatex.blank-line?
  (lambda (source/line.5)
    (invoke-1
      ((lambda () (let ((source/loop.19 #f) (body/source/loop.19 #f)) (set! source/loop.19 (ref (value-uninitialized))) (set! body/source/loop.19 (lambda (source/i.16) ((lambda (source/c.12) (if (value-truth? (primitive/char=?/2 source/c.12 (value-character #\space))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.5 (binding-value source/slatex.=notab)) source/i.16) (binding-value source/slatex.&void-notab))) (body/source/loop.19 (primitive/+/2 source/i.16 (value-number (exact-number 1)))) (value-boolean #f)) (if (value-truth? (primitive/char=?/2 source/c.12 (value-character #\newline))) (begin (invoke-1 ((lambda () (let ((source/loop2.2 #f) (body/source/loop2.2 #f)) (set! source/loop2.2 (ref (value-uninitialized))) (set! body/source/loop2.2 (lambda (source/j.3) (if (value-truth? (primitive/<=/2 source/j.3 (value-number (exact-number 0)))) literal.109 (begin (primitive/string-set!/3 (primitive/vector-ref/2 source/line.5 (binding-value source/slatex.=space)) source/i.16 (binding-value source/slatex.&void-space)) (body/source/loop2.2 (primitive/-/2 source/j.3 (value-number (exact-number 1)))))))) (ref-set! source/loop2.2 (value-procedure (ref (unit)) (function-1 body/source/loop2.2))) (binding-value source/loop2.2)))) (primitive/-/2 source/i.16 (value-number (exact-number 1)))) (value-boolean #t)) (value-boolean #f)))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.5 (binding-value source/slatex.=char)) source/i.16)))) (ref-set! source/loop.19 (value-procedure (ref (unit)) (function-1 body/source/loop.19))) (binding-value source/loop.19)))
)
      (value-number (exact-number 0)))))

(ref-set!
  source/slatex.blank-line?
  (value-procedure (ref (unit)) (function-1 body/source/slatex.blank-line?)))

(define source/slatex.flush-comment-line? (ref (value-uninitialized)))

(define body/source/slatex.flush-comment-line?
  (lambda (source/line.6)
    (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.6 (binding-value source/slatex.=char)) (value-number (exact-number 0))) (value-character #\;)))
      (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.6 (binding-value source/slatex.=notab)) (value-number (exact-number 0))) (binding-value source/slatex.&begin-comment)))
        (primitive/not/1
          (primitive/char=?/2
            (primitive/string-ref/2
              (primitive/vector-ref/2 source/line.6 (binding-value source/slatex.=char))
              (value-number (exact-number 1)))
            (value-character #\;)))
        (value-boolean #f))
      (value-boolean #f))))

(ref-set!
  source/slatex.flush-comment-line?
  (value-procedure (ref (unit)) (function-1 body/source/slatex.flush-comment-line?)))

(define source/slatex.do-all-lines (ref (value-uninitialized)))

(define body/source/slatex.do-all-lines
  (lambda ()
    (invoke-2
      ((lambda () (let ((source/loop.20 #f) (body/source/loop.20 #f)) (set! source/loop.20 (ref (value-uninitialized))) (set! body/source/loop.20 (lambda (source/line1 source/line2) ((lambda (source/line2-paragraph?) ((lambda (source/more?) ((lambda () (begin (body/source/slatex.peephole-adjust source/line1 source/line2) (invoke-1 (if (value-truth? source/line2-paragraph?) (binding-value source/slatex.display-tex-line) (binding-value source/slatex.display-scm-line)) source/line2) (if (value-truth? (primitive/eq?/2 source/line2-paragraph? (binding-value source/slatex.*latex-paragraph-mode?*))) literal.110 (invoke-1 (if (value-truth? (binding-value source/slatex.*latex-paragraph-mode?*)) (binding-value source/slatex.display-end-sequence) (binding-value source/slatex.display-begin-sequence)) (binding-value source/slatex.*out*))) (if (value-truth? source/more?) (body/source/loop.20 source/line2 source/line1) (value-unspecified)))))) (invoke-1 (binding-value source/slatex.get-line) source/line1))) (binding-value source/slatex.*latex-paragraph-mode?*)))) (ref-set! source/loop.20 (value-procedure (ref (unit)) (function-2 body/source/loop.20))) (binding-value source/loop.20)))
)
      (binding-value source/slatex.*line1*)
      (binding-value source/slatex.*line2*))))

(ref-set!
  source/slatex.do-all-lines
  (value-procedure (ref (unit)) (function-0 body/source/slatex.do-all-lines)))

(define source/scheme2tex (ref (value-uninitialized)))

(define body/source/scheme2tex
  (lambda (source/inport source/outport)
    (begin
      (begin (ref-set! source/slatex.*in* source/inport) (value-unspecified))
      (begin (ref-set! source/slatex.*out* source/outport) (value-unspecified))
      (begin
        (ref-set! source/slatex.*latex-paragraph-mode?* (value-boolean #t))
        (value-unspecified))
      (begin (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #f)) (value-unspecified))
      (begin
        (ref-set! source/slatex.*in-bktd-qtd-exp* (value-number (exact-number 0)))
        (value-unspecified))
      (begin (ref-set! source/slatex.*in-mac-tkn* (value-boolean #f)) (value-unspecified))
      (begin
        (ref-set! source/slatex.*in-bktd-mac-exp* (value-number (exact-number 0)))
        (value-unspecified))
      (begin (ref-set! source/slatex.*case-stack* (value-null)) (value-unspecified))
      (begin (ref-set! source/slatex.*bq-stack* (value-null)) (value-unspecified))
      ((lambda (source/flush-line) (begin (invoke-1 source/flush-line (binding-value source/slatex.*line1*)) (invoke-1 source/flush-line (binding-value source/slatex.*line2*))))
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/line.7)
              (begin
                (primitive/vector-set!/3
                  source/line.7
                  (binding-value source/slatex.=rtedge)
                  (value-number (exact-number 0)))
                (primitive/string-set!/3
                  (primitive/vector-ref/2 source/line.7 (binding-value source/slatex.=char))
                  (value-number (exact-number 0))
                  (value-character #\newline))
                (primitive/string-set!/3
                  (primitive/vector-ref/2 source/line.7 (binding-value source/slatex.=space))
                  (value-number (exact-number 0))
                  (binding-value source/slatex.&void-space))
                (primitive/string-set!/3
                  (primitive/vector-ref/2 source/line.7 (binding-value source/slatex.=tab))
                  (value-number (exact-number 0))
                  (binding-value source/slatex.&void-tab))
                (primitive/string-set!/3
                  (primitive/vector-ref/2 source/line.7 (binding-value source/slatex.=notab))
                  (value-number (exact-number 0))
                  (binding-value source/slatex.&void-notab)))))))
      (body/source/slatex.do-all-lines))))

(ref-set! source/scheme2tex (value-procedure (ref (unit)) (function-2 body/source/scheme2tex)))

(define source/slatex.display-tex-line (ref (value-uninitialized)))

(define body/source/slatex.display-tex-line
  (lambda (source/line.8)
    (invoke-1
      ((lambda () (let ((source/loop.21 #f) (body/source/loop.21 #f)) (set! source/loop.21 (ref (value-uninitialized))) (set! body/source/loop.21 (lambda (source/i.17) ((lambda (source/c.13) (if (value-truth? (primitive/char=?/2 source/c.13 (value-character #\newline))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.8 (binding-value source/slatex.=tab)) source/i.17) (binding-value source/slatex.&void-tab))) literal.111 (primitive/newline/1 (binding-value source/slatex.*out*))) (begin (primitive/display/2 source/c.13 (binding-value source/slatex.*out*)) (body/source/loop.21 (primitive/+/2 source/i.17 (value-number (exact-number 1))))))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.8 (binding-value source/slatex.=char)) source/i.17)))) (ref-set! source/loop.21 (value-procedure (ref (unit)) (function-1 body/source/loop.21))) (binding-value source/loop.21)))
)
      (if (value-truth? (body/source/slatex.flush-comment-line? source/line.8))
        (value-number (exact-number 1))
        (value-number (exact-number 0))))))

(ref-set!
  source/slatex.display-tex-line
  (value-procedure (ref (unit)) (function-1 body/source/slatex.display-tex-line)))

(define source/slatex.display-scm-line (ref (value-uninitialized)))

(define body/source/slatex.display-scm-line
  (lambda (source/line.9)
    (invoke-1
      ((lambda () (let ((source/loop.22 #f) (body/source/loop.22 #f)) (set! source/loop.22 (ref (value-uninitialized))) (set! body/source/loop.22 (lambda (source/i.18) ((lambda (source/c.14) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\newline))) ((lambda (source/tab.1) (if (value-truth? (primitive/eqv?/2 source/tab.1 (binding-value source/slatex.&tabbed-crg-ret))) (begin (primitive/display/2 literal.122 (binding-value source/slatex.*out*)) (primitive/newline/1 (binding-value source/slatex.*out*))) (if (value-truth? (primitive/eqv?/2 source/tab.1 (binding-value source/slatex.&plain-crg-ret))) (primitive/newline/1 (binding-value source/slatex.*out*)) (if (value-truth? (primitive/eqv?/2 source/tab.1 (binding-value source/slatex.&void-tab))) (begin (primitive/display/2 (value-character #\%) (binding-value source/slatex.*out*)) (primitive/newline/1 (binding-value source/slatex.*out*))) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18)) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&begin-comment))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&mid-comment))) (begin (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&begin-string))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 literal.121 (binding-value source/slatex.*out*)) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\space))) (body/source/slatex.display-space (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=space)) source/i.18) (binding-value source/slatex.*out*)) (body/source/slatex.display-tex-char source/c.14 (binding-value source/slatex.*out*))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&mid-string))) (begin (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\space))) (body/source/slatex.display-space (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=space)) source/i.18) (binding-value source/slatex.*out*)) (body/source/slatex.display-tex-char source/c.14 (binding-value source/slatex.*out*))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&end-string))) (begin (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\space))) (body/source/slatex.display-space (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=space)) source/i.18) (binding-value source/slatex.*out*)) (body/source/slatex.display-tex-char source/c.14 (binding-value source/slatex.*out*))) (primitive/display/2 literal.120 (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/eqv?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (binding-value source/slatex.&begin-math))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/memv/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=notab)) source/i.18) (primitive/list/2 (binding-value source/slatex.&mid-math) (binding-value source/slatex.&end-math)))) (begin (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\space))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (body/source/slatex.display-space (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=space)) source/i.18) (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\'))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (if (value-truth? ((lambda (source/value.16) (if (value-truth? source/value.16) source/value.16 (primitive/>/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 0))))) (binding-value source/slatex.*in-qtd-tkn*))) literal.119 (begin (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #t)) (value-unspecified))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\`))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (if (value-truth? ((lambda (source/value.15) (if (value-truth? source/value.15) source/value.15 (primitive/vector-ref/2 (primitive/car/1 (binding-value source/slatex.*bq-stack*)) (binding-value source/slatex.=in-comma)))) (primitive/null?/1 (binding-value source/slatex.*bq-stack*)))) (begin (ref-set! source/slatex.*bq-stack* (primitive/cons/2 ((lambda (source/f.7) (begin (primitive/vector-set!/3 source/f.7 (binding-value source/slatex.=in-comma) (value-boolean #f)) (primitive/vector-set!/3 source/f.7 (binding-value source/slatex.=in-bq-tkn) (value-boolean #t)) (primitive/vector-set!/3 source/f.7 (binding-value source/slatex.=in-bktd-bq-exp) (value-number (exact-number 0))) source/f.7)) (body/source/slatex.make-bq-frame)) (binding-value source/slatex.*bq-stack*))) (value-unspecified)) (value-unspecified)) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/char=?/2 source/c.14 (value-character #\,))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (if (value-truth? ((lambda (source/value.14) (if (value-truth? source/value.14) source/value.14 (primitive/vector-ref/2 (primitive/car/1 (binding-value source/slatex.*bq-stack*)) (binding-value source/slatex.=in-comma)))) (primitive/null?/1 (binding-value source/slatex.*bq-stack*)))) literal.118 (begin (ref-set! source/slatex.*bq-stack* (primitive/cons/2 ((lambda (source/f.6) (begin (primitive/vector-set!/3 source/f.6 (binding-value source/slatex.=in-comma) (value-boolean #t)) (primitive/vector-set!/3 source/f.6 (binding-value source/slatex.=in-bq-tkn) (value-boolean #t)) (primitive/vector-set!/3 source/f.6 (binding-value source/slatex.=in-bktd-bq-exp) (value-number (exact-number 0))) source/f.6)) (body/source/slatex.make-bq-frame)) (binding-value source/slatex.*bq-stack*))) (value-unspecified))) (if (value-truth? (primitive/char=?/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=char)) (primitive/+/2 source/i.18 (value-number (exact-number 1)))) (value-character #\@))) (begin (body/source/slatex.display-tex-char (value-character #\@) (binding-value source/slatex.*out*)) (body/source/loop.22 (primitive/+/2 (value-number (exact-number 2)) source/i.18))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1)))))) (if (value-truth? (primitive/memv/2 source/c.14 literal.117)) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (if (value-truth? (binding-value source/slatex.*in-qtd-tkn*)) (begin (begin (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #f)) (value-unspecified)) (begin (ref-set! source/slatex.*in-bktd-qtd-exp* (value-number (exact-number 1))) (value-unspecified))) (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 0)))) (begin (ref-set! source/slatex.*in-bktd-qtd-exp* (primitive/+/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 1)))) (value-unspecified)) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))) (if (value-truth? (binding-value source/slatex.*in-mac-tkn*)) (begin (begin (ref-set! source/slatex.*in-mac-tkn* (value-boolean #f)) (value-unspecified)) (begin (ref-set! source/slatex.*in-bktd-mac-exp* (value-number (exact-number 1))) (value-unspecified))) (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-mac-exp*) (value-number (exact-number 0)))) (begin (ref-set! source/slatex.*in-bktd-mac-exp* (primitive/+/2 (binding-value source/slatex.*in-bktd-mac-exp*) (value-number (exact-number 1)))) (value-unspecified)) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))) (if (value-truth? (primitive/null?/1 (binding-value source/slatex.*bq-stack*))) literal.115 ((lambda (source/top.2) (if (value-truth? (primitive/vector-ref/2 source/top.2 (binding-value source/slatex.=in-bq-tkn))) (begin (primitive/vector-set!/3 source/top.2 (binding-value source/slatex.=in-bq-tkn) (value-boolean #f)) (primitive/vector-set!/3 source/top.2 (binding-value source/slatex.=in-bktd-bq-exp) (value-number (exact-number 1)))) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top.2 (binding-value source/slatex.=in-bktd-bq-exp)) (value-number (exact-number 0)))) (primitive/vector-set!/3 source/top.2 (binding-value source/slatex.=in-bktd-bq-exp) (primitive/+/2 (primitive/vector-ref/2 source/top.2 (binding-value source/slatex.=in-bktd-bq-exp)) (value-number (exact-number 1)))) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))) (primitive/car/1 (binding-value source/slatex.*bq-stack*)))) (if (value-truth? (primitive/null?/1 (binding-value source/slatex.*case-stack*))) literal.116 ((lambda (source/top.3) (if (value-truth? (primitive/vector-ref/2 source/top.3 (binding-value source/=in-ctag-tkn))) (begin (primitive/vector-set!/3 source/top.3 (binding-value source/=in-ctag-tkn) (value-boolean #f)) (primitive/vector-set!/3 source/top.3 (binding-value source/slatex.=in-bktd-ctag-exp) (value-number (exact-number 1)))) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top.3 (binding-value source/slatex.=in-bktd-ctag-exp)) (value-number (exact-number 0)))) (primitive/vector-set!/3 source/top.3 (binding-value source/slatex.=in-bktd-ctag-exp) (primitive/+/2 (primitive/vector-ref/2 source/top.3 (binding-value source/slatex.=in-bktd-ctag-exp)) (value-number (exact-number 1)))) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top.3 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 0)))) (begin (primitive/vector-set!/3 source/top.3 (binding-value source/slatex.=in-case-exp) (primitive/+/2 (primitive/vector-ref/2 source/top.3 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 1)))) (if (value-truth? (primitive/=/2 (primitive/vector-ref/2 source/top.3 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 2)))) (begin (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #t)) (value-unspecified)) (value-unspecified))) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))))) (primitive/car/1 (binding-value source/slatex.*case-stack*)))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (if (value-truth? (primitive/memv/2 source/c.14 literal.114)) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (primitive/display/2 source/c.14 (binding-value source/slatex.*out*)) (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 0)))) (begin (ref-set! source/slatex.*in-bktd-qtd-exp* (primitive/-/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 1)))) (value-unspecified)) (value-unspecified)) (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-mac-exp*) (value-number (exact-number 0)))) (begin (ref-set! source/slatex.*in-bktd-mac-exp* (primitive/-/2 (binding-value source/slatex.*in-bktd-mac-exp*) (value-number (exact-number 1)))) (value-unspecified)) (value-unspecified)) (if (value-truth? (primitive/null?/1 (binding-value source/slatex.*bq-stack*))) literal.112 ((lambda (source/top) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top (binding-value source/slatex.=in-bktd-bq-exp)) (value-number (exact-number 0)))) (begin (primitive/vector-set!/3 source/top (binding-value source/slatex.=in-bktd-bq-exp) (primitive/-/2 (primitive/vector-ref/2 source/top (binding-value source/slatex.=in-bktd-bq-exp)) (value-number (exact-number 1)))) (if (value-truth? (primitive/=/2 (primitive/vector-ref/2 source/top (binding-value source/slatex.=in-bktd-bq-exp)) (value-number (exact-number 0)))) (begin (ref-set! source/slatex.*bq-stack* (primitive/cdr/1 (binding-value source/slatex.*bq-stack*))) (value-unspecified)) (value-unspecified))) (value-unspecified))) (primitive/car/1 (binding-value source/slatex.*bq-stack*)))) (invoke-0 ((lambda () (let ((source/loop.23 #f) (body/source/loop.23 #f)) (set! source/loop.23 (ref (value-uninitialized))) (set! body/source/loop.23 (lambda () (if (value-truth? (primitive/null?/1 (binding-value source/slatex.*case-stack*))) literal.113 ((lambda (source/top.1) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-bktd-ctag-exp)) (value-number (exact-number 0)))) (begin (primitive/vector-set!/3 source/top.1 (binding-value source/slatex.=in-bktd-ctag-exp) (primitive/-/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-bktd-ctag-exp)) (value-number (exact-number 1)))) (if (value-truth? (primitive/=/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-bktd-ctag-exp)) (value-number (exact-number 0)))) (primitive/vector-set!/3 source/top.1 (binding-value source/slatex.=in-case-exp) (value-number (exact-number 1))) (value-unspecified))) (if (value-truth? (primitive/>/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 0)))) (begin (primitive/vector-set!/3 source/top.1 (binding-value source/slatex.=in-case-exp) (primitive/-/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 1)))) (if (value-truth? (primitive/=/2 (primitive/vector-ref/2 source/top.1 (binding-value source/slatex.=in-case-exp)) (value-number (exact-number 0)))) (begin (begin (ref-set! source/slatex.*case-stack* (primitive/cdr/1 (binding-value source/slatex.*case-stack*))) (value-unspecified)) (body/source/loop.23)) (value-unspecified))) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))) (primitive/car/1 (binding-value source/slatex.*case-stack*)))))) (ref-set! source/loop.23 (value-procedure (ref (unit)) (function-0 body/source/loop.23))) (binding-value source/loop.23))))) (body/source/loop.22 (primitive/+/2 source/i.18 (value-number (exact-number 1))))) (begin (body/source/slatex.display-tab (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=tab)) source/i.18) (binding-value source/slatex.*out*)) (body/source/loop.22 (invoke-2 (binding-value source/slatex.do-token) source/line.9 source/i.18)))))))))))))))))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.9 (binding-value source/slatex.=char)) source/i.18)))) (ref-set! source/loop.22 (value-procedure (ref (unit)) (function-1 body/source/loop.22))) (binding-value source/loop.22)))
)
      (value-number (exact-number 0)))))

(ref-set!
  source/slatex.display-scm-line
  (value-procedure (ref (unit)) (function-1 body/source/slatex.display-scm-line)))

(define source/slatex.do-token (ref (value-uninitialized)))

(ref-set!
  source/slatex.do-token
  ((lambda (source/token-delims) (value-procedure (ref (unit)) (function-2 (lambda (source/line.10 source/i.19) (invoke-2 ((lambda () (let ((source/loop.24 #f) (body/source/loop.24 #f)) (set! source/loop.24 (ref (value-uninitialized))) (set! body/source/loop.24 (lambda (source/buf source/i.20) ((lambda (source/c.15) (if (value-truth? (primitive/char=?/2 source/c.15 (value-character #\\))) (body/source/loop.24 (primitive/cons/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.10 (binding-value source/slatex.=char)) (primitive/+/2 source/i.20 (value-number (exact-number 1)))) (primitive/cons/2 source/c.15 source/buf)) (primitive/+/2 source/i.20 (value-number (exact-number 2)))) (if (value-truth? ((lambda (source/value.17) (if (value-truth? source/value.17) source/value.17 (primitive/memv/2 source/c.15 (binding-value source/slatex.*math-triggerers*)))) (primitive/memv/2 source/c.15 source/token-delims))) (begin (body/source/slatex.output-token (primitive/list->string/1 (body/source/slatex.reverse! source/buf))) source/i.20) (if (value-truth? (primitive/char?/1 source/c.15)) (body/source/loop.24 (primitive/cons/2 (primitive/string-ref/2 (primitive/vector-ref/2 source/line.10 (binding-value source/slatex.=char)) source/i.20) source/buf) (primitive/+/2 source/i.20 (value-number (exact-number 1)))) (body/source/slatex.error literal.123 (value-number (exact-number 1))))))) (primitive/string-ref/2 (primitive/vector-ref/2 source/line.10 (binding-value source/slatex.=char)) source/i.20)))) (ref-set! source/loop.24 (value-procedure (ref (unit)) (function-2 body/source/loop.24))) (binding-value source/loop.24)))) (value-null) source/i.19)))))
    (primitive/list/10
      (value-character #\()
      (value-character #\))
      (value-character #\[)
      (value-character #\])
      (value-character #\space)
      (binding-value source/slatex.*return*)
      (value-character #\newline)
      (value-character #\,)
      (value-character #\@)
      (value-character #\;))))

(define source/slatex.output-token (ref (value-uninitialized)))

(define body/source/slatex.output-token
  (lambda (source/token)
    (begin
      (if (value-truth? (primitive/null?/1 (binding-value source/slatex.*case-stack*)))
        literal.124
        ((lambda (source/top.4) (if (value-truth? (primitive/vector-ref/2 source/top.4 (binding-value source/=in-ctag-tkn))) (begin (primitive/vector-set!/3 source/top.4 (binding-value source/=in-ctag-tkn) (value-boolean #f)) (primitive/vector-set!/3 source/top.4 (binding-value source/slatex.=in-case-exp) (value-number (exact-number 1)))) (value-unspecified)))
          (primitive/car/1 (binding-value source/slatex.*case-stack*))))
      (if (value-truth? (body/source/slatex.assoc-token source/token (binding-value source/slatex.special-symbols)))
        (primitive/display/2
          (primitive/cdr/1
            (body/source/slatex.assoc-token
              source/token
              (binding-value source/slatex.special-symbols)))
          (binding-value source/slatex.*out*))
        (body/source/slatex.display-token
          source/token
          (if (value-truth? (binding-value source/slatex.*in-qtd-tkn*))
            (begin
              (begin (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #f)) (value-unspecified))
              (if (value-truth? (primitive/equal?/2 source/token literal.138))
                literal.137
                (if (value-truth? (body/source/slatex.data-token? source/token))
                  literal.136
                  literal.135)))
            (if (value-truth? (body/source/slatex.data-token? source/token))
              literal.134
              (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-qtd-exp*) (value-number (exact-number 0))))
                literal.133
                (if (value-truth? (if (value-truth? (primitive/not/1 (primitive/null?/1 (binding-value source/slatex.*bq-stack*)))) (primitive/not/1 (primitive/vector-ref/2 (primitive/car/1 (binding-value source/slatex.*bq-stack*)) (binding-value source/slatex.=in-comma))) (value-boolean #f)))
                  literal.132
                  (if (value-truth? (binding-value source/slatex.*in-mac-tkn*))
                    (begin
                      (begin
                        (ref-set! source/slatex.*in-mac-tkn* (value-boolean #f))
                        (value-unspecified))
                      (body/source/slatex.set-keyword source/token)
                      literal.131)
                    (if (value-truth? (primitive/>/2 (binding-value source/slatex.*in-bktd-mac-exp*) (value-number (exact-number 0))))
                      (begin (body/source/slatex.set-keyword source/token) literal.130)
                      (if (value-truth? (body/source/slatex.member-token source/token (binding-value source/slatex.constant-tokens)))
                        literal.129
                        (if (value-truth? (body/source/slatex.member-token source/token (binding-value source/slatex.variable-tokens)))
                          literal.128
                          (if (value-truth? (body/source/slatex.member-token source/token (binding-value source/slatex.keyword-tokens)))
                            (begin
                              (if (value-truth? (body/source/slatex.token=? source/token literal.126))
                                (begin
                                  (ref-set! source/slatex.*in-qtd-tkn* (value-boolean #t))
                                  (value-unspecified))
                                (if (value-truth? (body/source/slatex.member-token source/token (binding-value source/slatex.macro-definers)))
                                  (begin
                                    (ref-set! source/slatex.*in-mac-tkn* (value-boolean #t))
                                    (value-unspecified))
                                  (if (value-truth? (body/source/slatex.member-token source/token (binding-value source/slatex.case-and-ilk)))
                                    (begin
                                      (ref-set!
                                        source/slatex.*case-stack*
                                        (primitive/cons/2
                                          ((lambda (source/f.8) (begin (primitive/vector-set!/3 source/f.8 (binding-value source/=in-ctag-tkn) (value-boolean #t)) (primitive/vector-set!/3 source/f.8 (binding-value source/slatex.=in-bktd-ctag-exp) (value-number (exact-number 0))) (primitive/vector-set!/3 source/f.8 (binding-value source/slatex.=in-case-exp) (value-number (exact-number 0))) source/f.8))
                                            (body/source/slatex.make-case-frame))
                                          (binding-value source/slatex.*case-stack*)))
                                      (value-unspecified))
                                    (if (value-truth? (value-boolean #f))
                                      (value-boolean #f)
                                      (value-unspecified)))))
                              literal.127)
                            literal.125)))))))))
          (binding-value source/slatex.*out*)))
      (if (value-truth? (if (value-truth? (primitive/not/1 (primitive/null?/1 (binding-value source/slatex.*bq-stack*)))) (primitive/vector-ref/2 (primitive/car/1 (binding-value source/slatex.*bq-stack*)) (binding-value source/slatex.=in-bq-tkn)) (value-boolean #f)))
        (begin
          (ref-set!
            source/slatex.*bq-stack*
            (primitive/cdr/1 (binding-value source/slatex.*bq-stack*)))
          (value-unspecified))
        (value-unspecified)))))

(ref-set!
  source/slatex.output-token
  (value-procedure (ref (unit)) (function-1 body/source/slatex.output-token)))

(define source/slatex.data-token? (ref (value-uninitialized)))

(define body/source/slatex.data-token?
  (lambda (source/token.1)
    ((lambda (source/value.18) (if (value-truth? source/value.18) source/value.18 (primitive/string->number/1 source/token.1)))
      (primitive/char=?/2
        (primitive/string-ref/2 source/token.1 (value-number (exact-number 0)))
        (value-character #\#)))))

(ref-set!
  source/slatex.data-token?
  (value-procedure (ref (unit)) (function-1 body/source/slatex.data-token?)))

(define source/slatex.*texinputs* (ref (value-uninitialized)))

(ref-set! source/slatex.*texinputs* literal.139)

(define source/slatex.*texinputs-list* (ref (value-uninitialized)))

(ref-set! source/slatex.*texinputs-list* (value-null))

(define source/slatex.*path-separator* (ref (value-uninitialized)))

(ref-set!
  source/slatex.*path-separator*
  (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.143))
    (value-character #\:)
    (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.142))
      (value-character #\;)
      (body/source/slatex.error literal.140 literal.141))))

(define source/slatex.*directory-mark* (ref (value-uninitialized)))

(ref-set!
  source/slatex.*directory-mark*
  (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.149))
    literal.148
    (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.147))
      literal.146
      (body/source/slatex.error literal.144 literal.145))))

(define source/slatex.*file-hider* (ref (value-uninitialized)))

(ref-set!
  source/slatex.*file-hider*
  (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.154))
    literal.153
    (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.152))
      literal.151
      literal.150)))

(define source/slatex.path->list (ref (value-uninitialized)))

(define body/source/slatex.path->list
  (lambda (source/p.6)
    (invoke-2
      ((lambda () (let ((source/loop.25 #f) (body/source/loop.25 #f)) (set! source/loop.25 (ref (value-uninitialized))) (set! body/source/loop.25 (lambda (source/p.7 source/r.4) ((lambda (source/separator-pos) (if (value-truth? source/separator-pos) (body/source/loop.25 (primitive/list-tail/2 source/p.7 (primitive/+/2 source/separator-pos (value-number (exact-number 1)))) (primitive/cons/2 (primitive/list->string/1 (body/source/slatex.sublist source/p.7 (value-number (exact-number 0)) source/separator-pos)) source/r.4)) (body/source/slatex.reverse! (primitive/cons/2 (primitive/list->string/1 source/p.7) source/r.4)))) (body/source/slatex.position-char (binding-value source/slatex.*path-separator*) source/p.7)))) (ref-set! source/loop.25 (value-procedure (ref (unit)) (function-2 body/source/loop.25))) (binding-value source/loop.25)))
)
      (primitive/string->list/1 source/p.6)
      (primitive/list/1 literal.155))))

(ref-set!
  source/slatex.path->list
  (value-procedure (ref (unit)) (function-1 body/source/slatex.path->list)))

(define source/slatex.find-some-file (ref (value-uninitialized)))

(define body/source/slatex.find-some-file
  (lambda (source/path source/files)
    (invoke-1
      ((lambda () (let ((source/loop.26 #f) (body/source/loop.26 #f)) (set! source/loop.26 (ref (value-uninitialized))) (set! body/source/loop.26 (lambda (source/path.1) (if (value-truth? (primitive/null?/1 source/path.1)) (value-boolean #f) ((lambda (source/dir) (invoke-1 ((lambda () (let ((source/loop2.3 #f) (body/source/loop2.3 #f)) (set! source/loop2.3 (ref (value-uninitialized))) (set! body/source/loop2.3 (lambda (source/files.1) (if (value-truth? (primitive/null?/1 source/files.1)) (body/source/loop.26 (primitive/cdr/1 source/path.1)) ((lambda (source/file.1) (if (value-truth? (body/source/slatex.file-exists? source/file.1)) source/file.1 (body/source/loop2.3 (primitive/cdr/1 source/files.1)))) (primitive/car/1 source/files.1))))) (ref-set! source/loop2.3 (value-procedure (ref (unit)) (function-1 body/source/loop2.3))) (binding-value source/loop2.3)))) (if (value-truth? ((lambda (source/value.19) (if (value-truth? source/value.19) source/value.19 (primitive/string=?/2 source/dir literal.157))) (primitive/string=?/2 source/dir literal.156))) source/files (primitive/map/2 (value-procedure (ref (unit)) (function-1 (lambda (source/file) (primitive/string-append/3 source/dir (binding-value source/slatex.*directory-mark*) source/file)))) source/files)))) (primitive/car/1 source/path.1))))) (ref-set! source/loop.26 (value-procedure (ref (unit)) (function-1 body/source/loop.26))) (binding-value source/loop.26)))
)
      source/path)))

(ref-set!
  source/slatex.find-some-file
  (value-procedure (ref (unit)) (function-rest-1 body/source/slatex.find-some-file)))

(define source/slatex.file-extension (ref (value-uninitialized)))

(define body/source/slatex.file-extension
  (lambda (source/filename)
    ((lambda (source/i.21) (if (value-truth? source/i.21) (primitive/substring/3 source/filename source/i.21 (primitive/string-length/1 source/filename)) (value-boolean #f)))
      (body/source/slatex.string-position-right (value-character #\.) source/filename))))

(ref-set!
  source/slatex.file-extension
  (value-procedure (ref (unit)) (function-1 body/source/slatex.file-extension)))

(define source/slatex.basename (ref (value-uninitialized)))

(define body/source/slatex.basename
  (lambda (source/filename.1 source/ext)
    ((lambda (source/filename-len) ((lambda (source/ext-len) ((lambda (source/len-diff) ((lambda () (if (value-truth? (primitive/>/2 source/ext-len source/filename-len)) source/filename.1 (if (value-truth? (primitive/equal?/2 source/ext (primitive/substring/3 source/filename.1 source/len-diff source/filename-len))) (primitive/substring/3 source/filename.1 (value-number (exact-number 0)) source/len-diff) source/filename.1))))) (primitive/-/2 source/filename-len source/ext-len))) (primitive/string-length/1 source/ext)))
      (primitive/string-length/1 source/filename.1))))

(ref-set!
  source/slatex.basename
  (value-procedure (ref (unit)) (function-2 body/source/slatex.basename)))

(define source/slatex.full-texfile-name (ref (value-uninitialized)))

(define body/source/slatex.full-texfile-name
  (lambda (source/filename.2)
    ((lambda (source/extn) (if (value-truth? (if (value-truth? source/extn) ((lambda (source/value.20) (if (value-truth? source/value.20) source/value.20 (primitive/string=?/2 source/extn literal.160))) (primitive/string=?/2 source/extn literal.159)) (value-boolean #f))) (body/source/slatex.find-some-file (binding-value source/slatex.*texinputs-list*) (value-cons source/filename.2 (value-null))) (body/source/slatex.find-some-file (binding-value source/slatex.*texinputs-list*) (value-cons (primitive/string-append/2 source/filename.2 literal.158) (value-cons source/filename.2 (value-null))))))
      (body/source/slatex.file-extension source/filename.2))))

(ref-set!
  source/slatex.full-texfile-name
  (value-procedure (ref (unit)) (function-1 body/source/slatex.full-texfile-name)))

(define source/slatex.full-scmfile-name (ref (value-uninitialized)))

(define body/source/slatex.full-scmfile-name
  (lambda (source/filename.3)
    (primitive/apply/4
      (binding-value source/slatex.find-some-file)
      (binding-value source/slatex.*texinputs-list*)
      source/filename.3
      (primitive/map/2
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/extn.1) (primitive/string-append/2 source/filename.3 source/extn.1))))
        literal.161))))

(ref-set!
  source/slatex.full-scmfile-name
  (value-procedure (ref (unit)) (function-1 body/source/slatex.full-scmfile-name)))

(define source/slatex.new-aux-file (ref (value-uninitialized)))

(define body/source/slatex.new-aux-file
  (lambda (source/e)
    (primitive/apply/2
      (if (value-truth? (binding-value source/slatex.*slatex-in-protected-region?*))
        (binding-value source/slatex.new-secondary-aux-file)
        (binding-value source/slatex.new-primary-aux-file))
      source/e)))

(ref-set!
  source/slatex.new-aux-file
  (value-procedure (ref (unit)) (function-rest-0 body/source/slatex.new-aux-file)))

(define source/slatex.subjobname (ref (value-uninitialized)))

(ref-set! source/slatex.subjobname literal.162)

(define source/primary-aux-file-count (ref (value-uninitialized)))

(ref-set! source/primary-aux-file-count (value-number (exact-number -1)))

(define source/slatex.new-primary-aux-file (ref (value-uninitialized)))

(define body/source/slatex.new-primary-aux-file
  (lambda (source/e.1)
    (begin
      (begin
        (ref-set!
          source/primary-aux-file-count
          (primitive/+/2
            (binding-value source/primary-aux-file-count)
            (value-number (exact-number 1))))
        (value-unspecified))
      (primitive/apply/5
        primitive-value/string-append
        (binding-value source/slatex.*file-hider*)
        literal.163
        (primitive/number->string/1 (binding-value source/primary-aux-file-count))
        source/e.1))))

(ref-set!
  source/slatex.new-primary-aux-file
  (value-procedure (ref (unit)) (function-rest-0 body/source/slatex.new-primary-aux-file)))

(define source/slatex.new-secondary-aux-file (ref (value-uninitialized)))

(ref-set!
  source/slatex.new-secondary-aux-file
  ((lambda (argument.5) (let ((source/n.1 (ref argument.5))) (value-procedure (ref (unit)) (function-rest-0 (lambda (source/e.2) (begin (begin (ref-set! source/n.1 (primitive/+/2 (ref-get source/n.1) (value-number (exact-number 1)))) (value-unspecified)) (primitive/apply/5 primitive-value/string-append (binding-value source/slatex.*file-hider*) literal.164 (primitive/number->string/1 (ref-get source/n.1)) source/e.2)))))))
    (value-number (exact-number -1))))

(define source/slatex.eat-till-newline (ref (value-uninitialized)))

(define body/source/slatex.eat-till-newline
  (lambda (source/in)
    (invoke-0
      ((lambda () (let ((source/loop.27 #f) (body/source/loop.27 #f)) (set! source/loop.27 (ref (value-uninitialized))) (set! body/source/loop.27 (lambda () ((lambda (source/c.16) (if (value-truth? (primitive/eof-object?/1 source/c.16)) literal.166 (if (value-truth? (primitive/char=?/2 source/c.16 (value-character #\newline))) literal.165 (body/source/loop.27)))) (primitive/read-char/1 source/in)))) (ref-set! source/loop.27 (value-procedure (ref (unit)) (function-0 body/source/loop.27))) (binding-value source/loop.27)))
))))

(ref-set!
  source/slatex.eat-till-newline
  (value-procedure (ref (unit)) (function-1 body/source/slatex.eat-till-newline)))

(define source/slatex.read-ctrl-seq (ref (value-uninitialized)))

(define body/source/slatex.read-ctrl-seq
  (lambda (source/in.1)
    ((lambda (source/c.17) (begin (if (value-truth? (primitive/eof-object?/1 source/c.17)) (body/source/slatex.error literal.167 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char-alphabetic?/1 source/c.17)) (primitive/list->string/1 (body/source/slatex.reverse! (invoke-1 ((lambda () (let ((source/loop.28 #f) (body/source/loop.28 #f)) (set! source/loop.28 (ref (value-uninitialized))) (set! body/source/loop.28 (lambda (source/s.17) ((lambda (source/c.18) (if (value-truth? (primitive/eof-object?/1 source/c.18)) source/s.17 (if (value-truth? (primitive/char-alphabetic?/1 source/c.18)) (begin (primitive/read-char/1 source/in.1) (body/source/loop.28 (primitive/cons/2 source/c.18 source/s.17))) (if (value-truth? (primitive/char=?/2 source/c.18 (value-character #\%))) (begin (body/source/slatex.eat-till-newline source/in.1) (body/source/loop.28 source/s.17)) source/s.17)))) (primitive/peek-char/1 source/in.1)))) (ref-set! source/loop.28 (value-procedure (ref (unit)) (function-1 body/source/loop.28))) (binding-value source/loop.28)))) (primitive/list/1 source/c.17)))) (primitive/string/1 source/c.17))))
      (primitive/read-char/1 source/in.1))))

(ref-set!
  source/slatex.read-ctrl-seq
  (value-procedure (ref (unit)) (function-1 body/source/slatex.read-ctrl-seq)))

(define source/slatex.eat-tabspace (ref (value-uninitialized)))

(define body/source/slatex.eat-tabspace
  (lambda (source/in.2)
    (invoke-0
      ((lambda () (let ((source/loop.29 #f) (body/source/loop.29 #f)) (set! source/loop.29 (ref (value-uninitialized))) (set! body/source/loop.29 (lambda () ((lambda (source/c.19) (if (value-truth? (primitive/eof-object?/1 source/c.19)) literal.169 (if (value-truth? ((lambda (source/value.21) (if (value-truth? source/value.21) source/value.21 (primitive/char=?/2 source/c.19 (binding-value source/slatex.*tab*)))) (primitive/char=?/2 source/c.19 (value-character #\space)))) (begin (primitive/read-char/1 source/in.2) (body/source/loop.29)) literal.168))) (primitive/peek-char/1 source/in.2)))) (ref-set! source/loop.29 (value-procedure (ref (unit)) (function-0 body/source/loop.29))) (binding-value source/loop.29)))
))))

(ref-set!
  source/slatex.eat-tabspace
  (value-procedure (ref (unit)) (function-1 body/source/slatex.eat-tabspace)))

(define source/slatex.eat-whitespace (ref (value-uninitialized)))

(define body/source/slatex.eat-whitespace
  (lambda (source/in.3)
    (invoke-0
      ((lambda () (let ((source/loop.30 #f) (body/source/loop.30 #f)) (set! source/loop.30 (ref (value-uninitialized))) (set! body/source/loop.30 (lambda () ((lambda (source/c.20) (if (value-truth? (primitive/eof-object?/1 source/c.20)) literal.171 (if (value-truth? (primitive/char-whitespace?/1 source/c.20)) (begin (primitive/read-char/1 source/in.3) (body/source/loop.30)) literal.170))) (primitive/peek-char/1 source/in.3)))) (ref-set! source/loop.30 (value-procedure (ref (unit)) (function-0 body/source/loop.30))) (binding-value source/loop.30)))
))))

(ref-set!
  source/slatex.eat-whitespace
  (value-procedure (ref (unit)) (function-1 body/source/slatex.eat-whitespace)))

(define source/slatex.eat-latex-whitespace (ref (value-uninitialized)))

(define body/source/slatex.eat-latex-whitespace
  (lambda (source/in.4)
    (invoke-0
      ((lambda () (let ((source/loop.31 #f) (body/source/loop.31 #f)) (set! source/loop.31 (ref (value-uninitialized))) (set! body/source/loop.31 (lambda () ((lambda (source/c.21) (if (value-truth? (primitive/eof-object?/1 source/c.21)) literal.173 (if (value-truth? (primitive/char-whitespace?/1 source/c.21)) (begin (primitive/read-char/1 source/in.4) (body/source/loop.31)) (if (value-truth? (primitive/char=?/2 source/c.21 (value-character #\%))) (body/source/slatex.eat-till-newline source/in.4) literal.172)))) (primitive/peek-char/1 source/in.4)))) (ref-set! source/loop.31 (value-procedure (ref (unit)) (function-0 body/source/loop.31))) (binding-value source/loop.31)))
))))

(ref-set!
  source/slatex.eat-latex-whitespace
  (value-procedure (ref (unit)) (function-1 body/source/slatex.eat-latex-whitespace)))

(define source/slatex.chop-off-whitespace (ref (value-uninitialized)))

(define body/source/slatex.chop-off-whitespace
  (lambda (source/l.19)
    (body/source/slatex.ormapcdr
      (value-procedure
        (ref (unit))
        (function-1
          (lambda (source/d.2)
            (if (value-truth? (primitive/char-whitespace?/1 (primitive/car/1 source/d.2)))
              (value-boolean #f)
              source/d.2))))
      source/l.19)))

(ref-set!
  source/slatex.chop-off-whitespace
  (value-procedure (ref (unit)) (function-1 body/source/slatex.chop-off-whitespace)))

(define source/slatex.read-grouped-latexexp (ref (value-uninitialized)))

(define body/source/slatex.read-grouped-latexexp
  (lambda (source/in.5)
    (begin
      (body/source/slatex.eat-latex-whitespace source/in.5)
      ((lambda (source/c.22) (begin (if (value-truth? (primitive/eof-object?/1 source/c.22)) (body/source/slatex.error literal.174 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.22 (value-character #\{))) literal.176 (body/source/slatex.error literal.175 (value-number (exact-number 2)))) (body/source/slatex.eat-latex-whitespace source/in.5) (primitive/list->string/1 (body/source/slatex.reverse! (body/source/slatex.chop-off-whitespace (invoke-3 ((lambda () (let ((source/loop.32 #f) (body/source/loop.32 #f)) (set! source/loop.32 (ref (value-uninitialized))) (set! body/source/loop.32 (lambda (source/s.18 source/nesting source/escape?) ((lambda (source/c.23) (begin (if (value-truth? (primitive/eof-object?/1 source/c.23)) (body/source/slatex.error literal.177 (value-number (exact-number 3))) (value-unspecified)) (if (value-truth? source/escape?) (body/source/loop.32 (primitive/cons/2 source/c.23 source/s.18) source/nesting (value-boolean #f)) (if (value-truth? (primitive/char=?/2 source/c.23 (value-character #\\))) (body/source/loop.32 (primitive/cons/2 source/c.23 source/s.18) source/nesting (value-boolean #t)) (if (value-truth? (primitive/char=?/2 source/c.23 (value-character #\%))) (begin (body/source/slatex.eat-till-newline source/in.5) (body/source/loop.32 source/s.18 source/nesting (value-boolean #f))) (if (value-truth? (primitive/char=?/2 source/c.23 (value-character #\{))) (body/source/loop.32 (primitive/cons/2 source/c.23 source/s.18) (primitive/+/2 source/nesting (value-number (exact-number 1))) (value-boolean #f)) (if (value-truth? (primitive/char=?/2 source/c.23 (value-character #\}))) (if (value-truth? (primitive/=/2 source/nesting (value-number (exact-number 0)))) source/s.18 (body/source/loop.32 (primitive/cons/2 source/c.23 source/s.18) (primitive/-/2 source/nesting (value-number (exact-number 1))) (value-boolean #f))) (body/source/loop.32 (primitive/cons/2 source/c.23 source/s.18) source/nesting (value-boolean #f))))))))) (primitive/read-char/1 source/in.5)))) (ref-set! source/loop.32 (value-procedure (ref (unit)) (function-3 body/source/loop.32))) (binding-value source/loop.32)))) (value-null) (value-number (exact-number 0)) (value-boolean #f)))))))
        (primitive/read-char/1 source/in.5)))))

(ref-set!
  source/slatex.read-grouped-latexexp
  (value-procedure (ref (unit)) (function-1 body/source/slatex.read-grouped-latexexp)))

(define source/slatex.read-filename (ref (value-uninitialized)))

(ref-set!
  source/slatex.read-filename
  ((lambda (source/filename-delims) (value-procedure (ref (unit)) (function-1 (lambda (source/in.6) (begin (body/source/slatex.eat-latex-whitespace source/in.6) ((lambda (source/c.24) (begin (if (value-truth? (primitive/eof-object?/1 source/c.24)) (body/source/slatex.error literal.178 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.24 (value-character #\{))) (body/source/slatex.read-grouped-latexexp source/in.6) (primitive/list->string/1 (body/source/slatex.reverse! (invoke-2 ((lambda () (let ((source/loop.33 #f) (body/source/loop.33 #f)) (set! source/loop.33 (ref (value-uninitialized))) (set! body/source/loop.33 (lambda (source/s.19 source/escape?.1) ((lambda (source/c.25) (if (value-truth? (primitive/eof-object?/1 source/c.25)) (if (value-truth? source/escape?.1) (body/source/slatex.error literal.179 (value-number (exact-number 2))) source/s.19) (if (value-truth? source/escape?.1) (begin (primitive/read-char/1 source/in.6) (body/source/loop.33 (primitive/cons/2 source/c.25 source/s.19) (value-boolean #f))) (if (value-truth? (primitive/char=?/2 source/c.25 (value-character #\\))) (begin (primitive/read-char/1 source/in.6) (body/source/loop.33 (primitive/cons/2 source/c.25 source/s.19) (value-boolean #t))) (if (value-truth? (primitive/memv/2 source/c.25 source/filename-delims)) source/s.19 (begin (primitive/read-char/1 source/in.6) (body/source/loop.33 (primitive/cons/2 source/c.25 source/s.19) (value-boolean #f)))))))) (primitive/peek-char/1 source/in.6)))) (ref-set! source/loop.33 (value-procedure (ref (unit)) (function-2 body/source/loop.33))) (binding-value source/loop.33)))) (value-null) (value-boolean #f))))))) (primitive/peek-char/1 source/in.6)))))))
    (primitive/list/14
      (value-character #\{)
      (value-character #\})
      (value-character #\[)
      (value-character #\])
      (value-character #\()
      (value-character #\))
      (value-character #\#)
      (value-character #\%)
      (value-character #\\)
      (value-character #\,)
      (value-character #\space)
      (binding-value source/slatex.*return*)
      (value-character #\newline)
      (binding-value source/slatex.*tab*))))

(define source/slatex.read-schemeid (ref (value-uninitialized)))

(ref-set!
  source/slatex.read-schemeid
  ((lambda (source/schemeid-delims) (value-procedure (ref (unit)) (function-1 (lambda (source/in.7) (begin (body/source/slatex.eat-whitespace source/in.7) (primitive/list->string/1 (body/source/slatex.reverse! (invoke-2 ((lambda () (let ((source/loop.34 #f) (body/source/loop.34 #f)) (set! source/loop.34 (ref (value-uninitialized))) (set! body/source/loop.34 (lambda (source/s.20 source/escape?.2) ((lambda (source/c.26) (if (value-truth? (primitive/eof-object?/1 source/c.26)) source/s.20 (if (value-truth? source/escape?.2) (begin (primitive/read-char/1 source/in.7) (body/source/loop.34 (primitive/cons/2 source/c.26 source/s.20) (value-boolean #f))) (if (value-truth? (primitive/char=?/2 source/c.26 (value-character #\\))) (begin (primitive/read-char/1 source/in.7) (body/source/loop.34 (primitive/cons/2 source/c.26 source/s.20) (value-boolean #t))) (if (value-truth? (primitive/memv/2 source/c.26 source/schemeid-delims)) source/s.20 (begin (primitive/read-char/1 source/in.7) (body/source/loop.34 (primitive/cons/2 source/c.26 source/s.20) (value-boolean #f)))))))) (primitive/peek-char/1 source/in.7)))) (ref-set! source/loop.34 (value-procedure (ref (unit)) (function-2 body/source/loop.34))) (binding-value source/loop.34)))) (value-null) (value-boolean #f)))))))))
    (primitive/list/10
      (value-character #\{)
      (value-character #\})
      (value-character #\[)
      (value-character #\])
      (value-character #\()
      (value-character #\))
      (value-character #\space)
      (binding-value source/slatex.*return*)
      (value-character #\newline)
      (binding-value source/slatex.*tab*))))

(define source/slatex.read-delimed-commaed-filenames (ref (value-uninitialized)))

(define body/source/slatex.read-delimed-commaed-filenames
  (lambda (source/in.8 source/lft-delim source/rt-delim)
    (begin
      (body/source/slatex.eat-latex-whitespace source/in.8)
      ((lambda (source/c.27) (begin (if (value-truth? (primitive/eof-object?/1 source/c.27)) (body/source/slatex.error literal.180 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.27 source/lft-delim)) literal.182 (body/source/slatex.error literal.181 (value-number (exact-number 2)))) (invoke-1 ((lambda () (let ((source/loop.35 #f) (body/source/loop.35 #f)) (set! source/loop.35 (ref (value-uninitialized))) (set! body/source/loop.35 (lambda (source/s.21) (begin (body/source/slatex.eat-latex-whitespace source/in.8) ((lambda (source/c.28) (begin (if (value-truth? (primitive/eof-object?/1 source/c.28)) (body/source/slatex.error literal.183 (value-number (exact-number 3))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.28 source/rt-delim)) (begin (primitive/read-char/1 source/in.8) (body/source/slatex.reverse! source/s.21)) ((lambda (source/s.22) (begin (body/source/slatex.eat-latex-whitespace source/in.8) ((lambda (source/c.29) (begin (if (value-truth? (primitive/eof-object?/1 source/c.29)) (body/source/slatex.error literal.184 (value-number (exact-number 4))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.29 (value-character #\,))) (primitive/read-char/1 source/in.8) (if (value-truth? (primitive/char=?/2 source/c.29 source/rt-delim)) literal.186 (body/source/slatex.error literal.185 (value-number (exact-number 5))))) (body/source/loop.35 source/s.22))) (primitive/peek-char/1 source/in.8)))) (primitive/cons/2 (invoke-1 (binding-value source/slatex.read-filename) source/in.8) source/s.21))))) (primitive/peek-char/1 source/in.8))))) (ref-set! source/loop.35 (value-procedure (ref (unit)) (function-1 body/source/loop.35))) (binding-value source/loop.35)))) (value-null))))
        (primitive/read-char/1 source/in.8)))))

(ref-set!
  source/slatex.read-delimed-commaed-filenames
  (value-procedure (ref (unit)) (function-3 body/source/slatex.read-delimed-commaed-filenames)))

(define source/slatex.read-grouped-commaed-filenames (ref (value-uninitialized)))

(define body/source/slatex.read-grouped-commaed-filenames
  (lambda (source/in.9)
    (body/source/slatex.read-delimed-commaed-filenames
      source/in.9
      (value-character #\{)
      (value-character #\}))))

(ref-set!
  source/slatex.read-grouped-commaed-filenames
  (value-procedure (ref (unit)) (function-1 body/source/slatex.read-grouped-commaed-filenames)))

(define source/slatex.read-bktd-commaed-filenames (ref (value-uninitialized)))

(define body/source/slatex.read-bktd-commaed-filenames
  (lambda (source/in.10)
    (body/source/slatex.read-delimed-commaed-filenames
      source/in.10
      (value-character #\[)
      (value-character #\]))))

(ref-set!
  source/slatex.read-bktd-commaed-filenames
  (value-procedure (ref (unit)) (function-1 body/source/slatex.read-bktd-commaed-filenames)))

(define source/slatex.read-grouped-schemeids (ref (value-uninitialized)))

(define body/source/slatex.read-grouped-schemeids
  (lambda (source/in.11)
    (begin
      (body/source/slatex.eat-latex-whitespace source/in.11)
      ((lambda (source/c.30) (begin (if (value-truth? (primitive/eof-object?/1 source/c.30)) (body/source/slatex.error literal.187 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.30 (value-character #\{))) literal.189 (body/source/slatex.error literal.188 (value-number (exact-number 2)))) (invoke-1 ((lambda () (let ((source/loop.36 #f) (body/source/loop.36 #f)) (set! source/loop.36 (ref (value-uninitialized))) (set! body/source/loop.36 (lambda (source/s.23) (begin (body/source/slatex.eat-whitespace source/in.11) ((lambda (source/c.31) (begin (if (value-truth? (primitive/eof-object?/1 source/c.31)) (body/source/slatex.error literal.190 (value-number (exact-number 3))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.31 (value-character #\}))) (begin (primitive/read-char/1 source/in.11) (body/source/slatex.reverse! source/s.23)) (body/source/loop.36 (primitive/cons/2 (invoke-1 (binding-value source/slatex.read-schemeid) source/in.11) source/s.23))))) (primitive/peek-char/1 source/in.11))))) (ref-set! source/loop.36 (value-procedure (ref (unit)) (function-1 body/source/loop.36))) (binding-value source/loop.36)))) (value-null))))
        (primitive/read-char/1 source/in.11)))))

(ref-set!
  source/slatex.read-grouped-schemeids
  (value-procedure (ref (unit)) (function-1 body/source/slatex.read-grouped-schemeids)))

(define source/slatex.disable-slatex-temply (ref (value-uninitialized)))

(define body/source/slatex.disable-slatex-temply
  (lambda (source/in.12)
    (begin
      (begin (ref-set! source/slatex.*slatex-enabled?* (value-boolean #f)) (value-unspecified))
      (begin
        (ref-set!
          source/slatex.*slatex-reenabler*
          (body/source/slatex.read-grouped-latexexp source/in.12))
        (value-unspecified)))))

(ref-set!
  source/slatex.disable-slatex-temply
  (value-procedure (ref (unit)) (function-1 body/source/slatex.disable-slatex-temply)))

(define source/slatex.enable-slatex-again (ref (value-uninitialized)))

(define body/source/slatex.enable-slatex-again
  (lambda ()
    (begin
      (begin (ref-set! source/slatex.*slatex-enabled?* (value-boolean #t)) (value-unspecified))
      (begin (ref-set! source/slatex.*slatex-reenabler* literal.191) (value-unspecified)))))

(ref-set!
  source/slatex.enable-slatex-again
  (value-procedure (ref (unit)) (function-0 body/source/slatex.enable-slatex-again)))

(define source/slatex.ignore2 (ref (value-uninitialized)))

(define body/source/slatex.ignore2 (lambda (source/i.22 source/ii) literal.192))

(ref-set!
  source/slatex.ignore2
  (value-procedure (ref (unit)) (function-2 body/source/slatex.ignore2)))

(define source/slatex.add-to-slatex-db (ref (value-uninitialized)))

(define body/source/slatex.add-to-slatex-db
  (lambda (source/in.13 source/categ)
    (if (value-truth? (primitive/memq/2 source/categ literal.193))
      (body/source/slatex.add-to-slatex-db-basic source/in.13 source/categ)
      (body/source/slatex.add-to-slatex-db-special source/in.13 source/categ))))

(ref-set!
  source/slatex.add-to-slatex-db
  (value-procedure (ref (unit)) (function-2 body/source/slatex.add-to-slatex-db)))

(define source/slatex.add-to-slatex-db-basic (ref (value-uninitialized)))

(define body/source/slatex.add-to-slatex-db-basic
  (lambda (source/in.14 source/categ.1)
    ((lambda (source/setter source/ids) (primitive/for-each/2 source/setter source/ids))
      (if (value-truth? (primitive/eq?/2 source/categ.1 literal.197))
        (binding-value source/slatex.set-keyword)
        (if (value-truth? (primitive/eq?/2 source/categ.1 literal.196))
          (binding-value source/slatex.set-constant)
          (if (value-truth? (primitive/eq?/2 source/categ.1 literal.195))
            (binding-value source/slatex.set-variable)
            (body/source/slatex.error literal.194 (value-number (exact-number 1))))))
      (body/source/slatex.read-grouped-schemeids source/in.14))))

(ref-set!
  source/slatex.add-to-slatex-db-basic
  (value-procedure (ref (unit)) (function-2 body/source/slatex.add-to-slatex-db-basic)))

(define source/slatex.add-to-slatex-db-special (ref (value-uninitialized)))

(define body/source/slatex.add-to-slatex-db-special
  (lambda (source/in.15 source/what)
    ((lambda (source/ids.1) (if (value-truth? (primitive/eq?/2 source/what literal.203)) (primitive/for-each/2 (binding-value source/slatex.unset-special-symbol) source/ids.1) (if (value-truth? (primitive/eq?/2 source/what literal.202)) (begin (if (value-truth? (primitive/=/2 (primitive/length/1 source/ids.1) (value-number (exact-number 1)))) literal.201 (body/source/slatex.error literal.199 literal.200)) ((lambda (source/transl.1) (body/source/slatex.set-special-symbol (primitive/car/1 source/ids.1) source/transl.1)) (body/source/slatex.read-grouped-latexexp source/in.15))) (body/source/slatex.error literal.198 (value-number (exact-number 2))))))
      (body/source/slatex.read-grouped-schemeids source/in.15))))

(ref-set!
  source/slatex.add-to-slatex-db-special
  (value-procedure (ref (unit)) (function-2 body/source/slatex.add-to-slatex-db-special)))

(define source/slatex.process-slatex-alias (ref (value-uninitialized)))

(define body/source/slatex.process-slatex-alias
  (lambda (source/in.16 source/what.1 source/which)
    ((lambda (source/triggerer) (if (value-truth? (primitive/eq?/2 source/which literal.214)) (begin (ref-set! source/slatex.*intext-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*intext-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.213)) (begin (ref-set! source/slatex.*resultintext-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*resultintext-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.212)) (begin (ref-set! source/slatex.*display-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*display-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.211)) (begin (ref-set! source/slatex.*box-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*box-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.210)) (begin (ref-set! source/slatex.*input-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*input-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.209)) (begin (ref-set! source/slatex.*region-triggerers* (invoke-2 source/what.1 source/triggerer (binding-value source/slatex.*region-triggerers*))) (value-unspecified)) (if (value-truth? (primitive/eq?/2 source/which literal.208)) (begin (if (value-truth? (primitive/=/2 (primitive/string-length/1 source/triggerer) (value-number (exact-number 1)))) literal.207 (body/source/slatex.error literal.205 literal.206)) (begin (ref-set! source/slatex.*math-triggerers* (invoke-2 source/what.1 (primitive/string-ref/2 source/triggerer (value-number (exact-number 0))) (binding-value source/slatex.*math-triggerers*))) (value-unspecified))) (body/source/slatex.error literal.204 (value-number (exact-number 2)))))))))))
      (body/source/slatex.read-grouped-latexexp source/in.16))))

(ref-set!
  source/slatex.process-slatex-alias
  (value-procedure (ref (unit)) (function-3 body/source/slatex.process-slatex-alias)))

(define source/slatex.decide-latex-or-tex (ref (value-uninitialized)))

(define body/source/slatex.decide-latex-or-tex
  (lambda (source/latex?)
    (begin
      (begin (ref-set! source/slatex.*latex?* source/latex?) (value-unspecified))
      ((lambda (source/pltexchk.jnk) (begin (if (value-truth? (body/source/slatex.file-exists? source/pltexchk.jnk)) (body/source/slatex.delete-file source/pltexchk.jnk) (value-unspecified)) (if (value-truth? (primitive/not/1 (binding-value source/slatex.*latex?*))) (primitive/call-with-output-file/2 source/pltexchk.jnk (value-procedure (ref (unit)) (function-1 (lambda (source/outp) (begin (primitive/display/2 literal.216 source/outp) (primitive/newline/1 source/outp)))))) (value-unspecified))))
        literal.215))))

(ref-set!
  source/slatex.decide-latex-or-tex
  (value-procedure (ref (unit)) (function-1 body/source/slatex.decide-latex-or-tex)))

(define source/slatex.process-include-only (ref (value-uninitialized)))

(define body/source/slatex.process-include-only
  (lambda (source/in.17)
    (begin
      (begin (ref-set! source/slatex.*include-onlys* (value-null)) (value-unspecified))
      (primitive/for-each/2
        (value-procedure
          (ref (unit))
          (function-1
            (lambda (source/filename.4)
              ((lambda (source/filename.5) (if (value-truth? source/filename.5) (begin (ref-set! source/slatex.*include-onlys* (body/source/slatex.adjoin-string source/filename.5 (binding-value source/slatex.*include-onlys*))) (value-unspecified)) (value-unspecified)))
                (body/source/slatex.full-texfile-name source/filename.4)))))
        (body/source/slatex.read-grouped-commaed-filenames source/in.17)))))

(ref-set!
  source/slatex.process-include-only
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-include-only)))

(define source/slatex.process-documentstyle (ref (value-uninitialized)))

(define body/source/slatex.process-documentstyle
  (lambda (source/in.18)
    (begin
      (body/source/slatex.eat-latex-whitespace source/in.18)
      (if (value-truth? (primitive/char=?/2 (primitive/peek-char/1 source/in.18) (value-character #\[)))
        (primitive/for-each/2
          (value-procedure
            (ref (unit))
            (function-1
              (lambda (source/filename.6)
                ((lambda (source/%:g0%) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* (value-boolean #f)) (value-unspecified)) ((lambda (source/%temp%) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* source/%:g0%) (value-unspecified)) source/%temp%)) (body/source/slatex.process-tex-file (primitive/string-append/2 source/filename.6 literal.217)))))
                  (binding-value source/slatex.*slatex-in-protected-region?*)))))
          (body/source/slatex.read-bktd-commaed-filenames source/in.18))
        (value-unspecified)))))

(ref-set!
  source/slatex.process-documentstyle
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-documentstyle)))

(define source/slatex.process-case-info (ref (value-uninitialized)))

(define body/source/slatex.process-case-info
  (lambda (source/in.19)
    ((lambda (source/bool) (begin (ref-set! source/slatex.*slatex-case-sensitive?* (if (value-truth? (primitive/string-ci=?/2 source/bool literal.221)) (value-boolean #t) (if (value-truth? (primitive/string-ci=?/2 source/bool literal.220)) (value-boolean #f) (body/source/slatex.error literal.218 literal.219)))) (value-unspecified)))
      (body/source/slatex.read-grouped-latexexp source/in.19))))

(ref-set!
  source/slatex.process-case-info
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-case-info)))

(define source/slatex.seen-first-command? (ref (value-uninitialized)))

(ref-set! source/slatex.seen-first-command? (value-boolean #f))

(define source/slatex.process-main-tex-file (ref (value-uninitialized)))

(define body/source/slatex.process-main-tex-file
  (lambda (source/filename.7)
    (begin
      (begin
        (ref-set!
          source/slatex.*texinputs-list*
          (body/source/slatex.path->list (binding-value source/slatex.*texinputs*)))
        (value-unspecified))
      ((lambda (source/file-hide-file) (begin (if (value-truth? (body/source/slatex.file-exists? source/file-hide-file)) (body/source/slatex.delete-file source/file-hide-file) (value-unspecified)) (if (value-truth? (primitive/eq?/2 (binding-value source/*op-sys*) literal.224)) (primitive/call-with-output-file/2 source/file-hide-file (value-procedure (ref (unit)) (function-1 (lambda (source/out.2) (begin (primitive/display/2 literal.223 source/out.2) (primitive/newline/1 source/out.2)))))) (value-unspecified))))
        literal.222)
      (begin
        (ref-set!
          source/slatex.subjobname
          (body/source/slatex.basename source/filename.7 literal.225))
        (value-unspecified))
      (begin (ref-set! source/slatex.seen-first-command? (value-boolean #f)) (value-unspecified))
      (body/source/slatex.process-tex-file source/filename.7))))

(ref-set!
  source/slatex.process-main-tex-file
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-main-tex-file)))

(define source/slatex.dump-intext (ref (value-uninitialized)))

(define body/source/slatex.dump-intext
  (lambda (source/in.20 source/out.3)
    ((lambda (source/display) ((lambda (source/delim-char) ((lambda (source/delim-char.1) ((lambda () (begin (if (value-truth? (primitive/eof-object?/1 source/delim-char.1)) (body/source/slatex.error literal.226 (value-number (exact-number 1))) (value-unspecified)) (invoke-0 ((lambda () (let ((source/loop.37 #f) (body/source/loop.37 #f)) (set! source/loop.37 (ref (value-uninitialized))) (set! body/source/loop.37 (lambda () ((lambda (source/c.32) (begin (if (value-truth? (primitive/eof-object?/1 source/c.32)) (body/source/slatex.error literal.227 (value-number (exact-number 2))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.32 source/delim-char.1)) literal.228 (begin (invoke-2 source/display source/c.32 source/out.3) (body/source/loop.37))))) (primitive/read-char/1 source/in.20)))) (ref-set! source/loop.37 (value-procedure (ref (unit)) (function-0 body/source/loop.37))) (binding-value source/loop.37))))))))) (if (value-truth? (primitive/char=?/2 source/delim-char (value-character #\{))) (value-character #\}) source/delim-char))) (begin (body/source/slatex.eat-whitespace source/in.20) (primitive/read-char/1 source/in.20))))
      (if (value-truth? source/out.3) primitive-value/display (binding-value source/slatex.ignore2)))))

(ref-set!
  source/slatex.dump-intext
  (value-procedure (ref (unit)) (function-2 body/source/slatex.dump-intext)))

(define source/slatex.dump-display (ref (value-uninitialized)))

(define body/source/slatex.dump-display
  (lambda (source/in.21 source/out.4 source/ender)
    (begin
      (body/source/slatex.eat-tabspace source/in.21)
      ((lambda (source/display.1 source/ender-lh source/c.33) (begin (if (value-truth? (primitive/eof-object?/1 source/c.33)) (body/source/slatex.error literal.229 (value-number (exact-number 1))) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.33 (value-character #\newline))) (primitive/read-char/1 source/in.21) (value-unspecified)) (invoke-1 ((lambda () (let ((source/loop.38 #f) (body/source/loop.38 #f)) (set! source/loop.38 (ref (value-uninitialized))) (set! body/source/loop.38 (lambda (source/buf.1) ((lambda (source/c.34) (begin (if (value-truth? (primitive/eof-object?/1 source/c.34)) (body/source/slatex.error literal.231 (value-number (exact-number 2))) (value-unspecified)) ((lambda (source/buf.2) (if (value-truth? (body/source/slatex.string-prefix? source/buf.2 source/ender)) (if (value-truth? (primitive/=/2 (primitive/string-length/1 source/buf.2) source/ender-lh)) literal.233 (body/source/loop.38 source/buf.2)) (begin (invoke-2 source/display.1 source/buf.2 source/out.4) (body/source/loop.38 literal.232)))) (primitive/string-append/2 source/buf.1 (primitive/string/1 source/c.34))))) (primitive/read-char/1 source/in.21)))) (ref-set! source/loop.38 (value-procedure (ref (unit)) (function-1 body/source/loop.38))) (binding-value source/loop.38)))) literal.230)))
        (if (value-truth? source/out.4)
          primitive-value/display
          (binding-value source/slatex.ignore2))
        (primitive/string-length/1 source/ender)
        (primitive/peek-char/1 source/in.21)))))

(ref-set!
  source/slatex.dump-display
  (value-procedure (ref (unit)) (function-3 body/source/slatex.dump-display)))

(define source/slatex.debug? (ref (value-uninitialized)))

(ref-set! source/slatex.debug? (value-boolean #f))

(define source/slatex.process-tex-file (ref (value-uninitialized)))

(define body/source/slatex.process-tex-file
  (lambda (source/raw-filename)
    (begin
      (if (value-truth? (binding-value source/slatex.debug?))
        (begin
          (primitive/display/1 literal.234)
          (primitive/display/1 source/raw-filename)
          (primitive/newline/0))
        (value-unspecified))
      ((lambda (source/filename.8) (if (value-truth? (primitive/not/1 source/filename.8)) (begin (primitive/display/1 literal.295) (primitive/display/1 source/raw-filename) (primitive/display/1 literal.296) (body/source/slatex.force-output (value-null))) (primitive/call-with-input-file/2 source/filename.8 (value-procedure (ref (unit)) (function-1 (lambda (source/in.22) ((lambda (argument.6) (let ((source/done? (ref argument.6))) (invoke-0 ((lambda () (let ((source/loop.39 #f) (body/source/loop.39 #f)) (set! source/loop.39 (ref (value-uninitialized))) (set! body/source/loop.39 (lambda () (if (value-truth? (ref-get source/done?)) literal.294 (begin ((lambda (source/c.35) (if (value-truth? (primitive/eof-object?/1 source/c.35)) (begin (ref-set! source/done? (value-boolean #t)) (value-unspecified)) (if (value-truth? (primitive/char=?/2 source/c.35 (value-character #\%))) (body/source/slatex.eat-till-newline source/in.22) (if (value-truth? (primitive/char=?/2 source/c.35 (value-character #\\))) ((lambda (source/cs) (begin (if (value-truth? (binding-value source/slatex.seen-first-command?)) literal.236 (begin (begin (ref-set! source/slatex.seen-first-command? (value-boolean #t)) (value-unspecified)) (body/source/slatex.decide-latex-or-tex (primitive/string=?/2 source/cs literal.235)))) (if (value-truth? (primitive/not/1 (binding-value source/slatex.*slatex-enabled?*))) (if (value-truth? (primitive/string=?/2 source/cs (binding-value source/slatex.*slatex-reenabler*))) (body/source/slatex.enable-slatex-again) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.293)) (begin (ref-set! source/done? (value-boolean #t)) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.292)) (if (value-truth? (binding-value source/slatex.*latex?*)) (begin (ref-set! source/slatex.*slatex-separate-includes?* (value-boolean #t)) (value-unspecified)) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.291)) (body/source/slatex.disable-slatex-temply source/in.22) (if (value-truth? (primitive/string=?/2 source/cs literal.290)) ((lambda (source/cs.1) (if (value-truth? (primitive/member/2 source/cs.1 (binding-value source/slatex.*display-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.289 source/in.22 source/cs.1) (if (value-truth? (primitive/member/2 source/cs.1 (binding-value source/slatex.*box-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.288 source/in.22 source/cs.1) (if (value-truth? (primitive/member/2 source/cs.1 (binding-value source/slatex.*region-triggerers*))) (body/source/slatex.trigger-region literal.287 source/in.22 source/cs.1) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))))) (body/source/slatex.read-grouped-latexexp source/in.22)) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*intext-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.286 source/in.22 (value-boolean #f)) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*resultintext-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.285 source/in.22 (value-boolean #f)) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*display-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.284 source/in.22 source/cs) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*box-triggerers*))) (body/source/slatex.trigger-scheme2tex literal.283 source/in.22 source/cs) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*region-triggerers*))) (body/source/slatex.trigger-region literal.282 source/in.22 source/cs) (if (value-truth? (primitive/member/2 source/cs (binding-value source/slatex.*input-triggerers*))) (body/source/slatex.process-scheme-file (invoke-1 (binding-value source/slatex.read-filename) source/in.22)) (if (value-truth? (primitive/string=?/2 source/cs literal.281)) ((lambda (source/%:g1%) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* (value-boolean #f)) (value-unspecified)) ((lambda (source/%temp%.2) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* source/%:g1%) (value-unspecified)) source/%temp%.2)) (body/source/slatex.process-tex-file (invoke-1 (binding-value source/slatex.read-filename) source/in.22))))) (binding-value source/slatex.*slatex-in-protected-region?*)) (if (value-truth? (primitive/string=?/2 source/cs literal.280)) (if (value-truth? (binding-value source/slatex.*latex?*)) ((lambda (source/f.9) (if (value-truth? (if (value-truth? source/f.9) ((lambda (source/value.22) (if (value-truth? source/value.22) source/value.22 (primitive/member/2 source/f.9 (binding-value source/slatex.*include-onlys*)))) (primitive/eq?/2 (binding-value source/slatex.*include-onlys*) literal.279)) (value-boolean #f))) ((lambda (source/%:g2% source/%:g3% source/%:g4%) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* (value-boolean #f)) (value-unspecified)) (begin (ref-set! source/slatex.subjobname (binding-value source/slatex.subjobname)) (value-unspecified)) (begin (ref-set! source/primary-aux-file-count (binding-value source/primary-aux-file-count)) (value-unspecified)) ((lambda (source/%temp%.1) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* source/%:g2%) (value-unspecified)) (begin (ref-set! source/slatex.subjobname source/%:g3%) (value-unspecified)) (begin (ref-set! source/primary-aux-file-count source/%:g4%) (value-unspecified)) source/%temp%.1)) (begin (if (value-truth? (binding-value source/slatex.*slatex-separate-includes?*)) (begin (begin (ref-set! source/slatex.subjobname (body/source/slatex.basename source/f.9 literal.278)) (value-unspecified)) (begin (ref-set! source/primary-aux-file-count (value-number (exact-number -1))) (value-unspecified))) (value-unspecified)) (body/source/slatex.process-tex-file source/f.9))))) (binding-value source/slatex.*slatex-in-protected-region?*) (binding-value source/slatex.subjobname) (binding-value source/primary-aux-file-count)) (value-unspecified))) (body/source/slatex.full-texfile-name (invoke-1 (binding-value source/slatex.read-filename) source/in.22))) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.277)) (if (value-truth? (binding-value source/slatex.*latex?*)) (body/source/slatex.process-include-only source/in.22) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.276)) (if (value-truth? (binding-value source/slatex.*latex?*)) (body/source/slatex.process-documentstyle source/in.22) (value-unspecified)) (if (value-truth? (primitive/string=?/2 source/cs literal.275)) (body/source/slatex.process-case-info source/in.22) (if (value-truth? (primitive/string=?/2 source/cs literal.274)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.273) (if (value-truth? (primitive/string=?/2 source/cs literal.272)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.271) (if (value-truth? (primitive/string=?/2 source/cs literal.270)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.269) (if (value-truth? (primitive/string=?/2 source/cs literal.268)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.267) (if (value-truth? (primitive/string=?/2 source/cs literal.266)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.265) (if (value-truth? (primitive/string=?/2 source/cs literal.264)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.263) (if (value-truth? (primitive/string=?/2 source/cs literal.262)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.261) (if (value-truth? (primitive/string=?/2 source/cs literal.260)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.259) (if (value-truth? (primitive/string=?/2 source/cs literal.258)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.257) (if (value-truth? (primitive/string=?/2 source/cs literal.256)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.255) (if (value-truth? (primitive/string=?/2 source/cs literal.254)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-string) literal.253) (if (value-truth? (primitive/string=?/2 source/cs literal.252)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-string!) literal.251) (if (value-truth? (primitive/string=?/2 source/cs literal.250)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.adjoin-char) literal.249) (if (value-truth? (primitive/string=?/2 source/cs literal.248)) (body/source/slatex.process-slatex-alias source/in.22 (binding-value source/slatex.remove-char!) literal.247) (if (value-truth? (primitive/string=?/2 source/cs literal.246)) (body/source/slatex.add-to-slatex-db source/in.22 literal.245) (if (value-truth? (primitive/string=?/2 source/cs literal.244)) (body/source/slatex.add-to-slatex-db source/in.22 literal.243) (if (value-truth? (primitive/string=?/2 source/cs literal.242)) (body/source/slatex.add-to-slatex-db source/in.22 literal.241) (if (value-truth? (primitive/string=?/2 source/cs literal.240)) (body/source/slatex.add-to-slatex-db source/in.22 literal.239) (if (value-truth? (primitive/string=?/2 source/cs literal.238)) (body/source/slatex.add-to-slatex-db source/in.22 literal.237) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified))))))))))))))))))))))))))))))))))))))) (body/source/slatex.read-ctrl-seq source/in.22)) (if (value-truth? (value-boolean #f)) (value-boolean #f) (value-unspecified)))))) (primitive/read-char/1 source/in.22)) (body/source/loop.39))))) (ref-set! source/loop.39 (value-procedure (ref (unit)) (function-0 body/source/loop.39))) (binding-value source/loop.39))))))) (value-boolean #f))))))))
        (body/source/slatex.full-texfile-name source/raw-filename))
      (if (value-truth? (binding-value source/slatex.debug?))
        (begin
          (primitive/display/1 literal.297)
          (primitive/display/1 source/raw-filename)
          (primitive/newline/0))
        (value-unspecified)))))

(ref-set!
  source/slatex.process-tex-file
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-tex-file)))

(define source/slatex.process-scheme-file (ref (value-uninitialized)))

(define body/source/slatex.process-scheme-file
  (lambda (source/raw-filename.1)
    ((lambda (source/filename.9) (if (value-truth? (primitive/not/1 source/filename.9)) (begin (primitive/display/1 literal.300) (primitive/display/1 source/raw-filename.1) (primitive/display/1 literal.301) (primitive/newline/0)) ((lambda (source/aux.tex) (begin (body/source/slatex.force-output (value-null)) (if (value-truth? (body/source/slatex.file-exists? source/aux.tex)) (body/source/slatex.delete-file source/aux.tex) (value-unspecified)) (primitive/call-with-input-file/2 source/filename.9 (value-procedure (ref (unit)) (function-1 (lambda (source/in.23) (primitive/call-with-output-file/2 source/aux.tex (value-procedure (ref (unit)) (function-1 (lambda (source/out.5) ((lambda (source/%:g5% source/%:g6%) (begin (begin (ref-set! source/slatex.*intext?* (value-boolean #f)) (value-unspecified)) (begin (ref-set! source/slatex.*code-env-spec* literal.299) (value-unspecified)) ((lambda (source/%temp%.3) (begin (begin (ref-set! source/slatex.*intext?* source/%:g5%) (value-unspecified)) (begin (ref-set! source/slatex.*code-env-spec* source/%:g6%) (value-unspecified)) source/%temp%.3)) (body/source/scheme2tex source/in.23 source/out.5)))) (binding-value source/slatex.*intext?*) (binding-value source/slatex.*code-env-spec*)))))))))) (if (value-truth? (binding-value source/slatex.*slatex-in-protected-region?*)) (begin (ref-set! source/slatex.*protected-files* (primitive/cons/2 source/aux.tex (binding-value source/slatex.*protected-files*))) (value-unspecified)) (value-unspecified)) (body/source/slatex.process-tex-file source/filename.9))) (body/source/slatex.new-aux-file (value-cons literal.298 (value-null))))))
      (body/source/slatex.full-scmfile-name source/raw-filename.1))))

(ref-set!
  source/slatex.process-scheme-file
  (value-procedure (ref (unit)) (function-1 body/source/slatex.process-scheme-file)))

(define source/slatex.trigger-scheme2tex (ref (value-uninitialized)))

(define body/source/slatex.trigger-scheme2tex
  (lambda (source/typ.1 source/in.24 source/env)
    ((lambda (source/aux) ((lambda (source/aux.scm) ((lambda (source/aux.tex.1) ((lambda () (begin (if (value-truth? (body/source/slatex.file-exists? source/aux.scm)) (body/source/slatex.delete-file source/aux.scm) (value-unspecified)) (if (value-truth? (body/source/slatex.file-exists? source/aux.tex.1)) (body/source/slatex.delete-file source/aux.tex.1) (value-unspecified)) (body/source/slatex.force-output (value-null)) (primitive/call-with-output-file/2 source/aux.scm (value-procedure (ref (unit)) (function-1 (lambda (source/out.6) (if (value-truth? (primitive/memq/2 source/typ.1 literal.310)) (body/source/slatex.dump-intext source/in.24 source/out.6) (if (value-truth? (primitive/memq/2 source/typ.1 literal.309)) (body/source/slatex.dump-display source/in.24 source/out.6 (primitive/string-append/3 literal.307 source/env literal.308)) (if (value-truth? (primitive/memq/2 source/typ.1 literal.306)) (body/source/slatex.dump-display source/in.24 source/out.6 (primitive/string-append/2 literal.305 source/env)) (body/source/slatex.error literal.304 (value-number (exact-number 1)))))))))) (primitive/call-with-input-file/2 source/aux.scm (value-procedure (ref (unit)) (function-1 (lambda (source/in.25) (primitive/call-with-output-file/2 source/aux.tex.1 (value-procedure (ref (unit)) (function-1 (lambda (source/out.7) ((lambda (source/%:g7% source/%:g8%) (begin (begin (ref-set! source/slatex.*intext?* (primitive/memq/2 source/typ.1 literal.311)) (value-unspecified)) (begin (ref-set! source/slatex.*code-env-spec* (if (value-truth? (primitive/eq?/2 source/typ.1 literal.320)) literal.319 (if (value-truth? (primitive/eq?/2 source/typ.1 literal.318)) literal.317 (if (value-truth? (primitive/memq/2 source/typ.1 literal.316)) literal.315 (if (value-truth? (primitive/memq/2 source/typ.1 literal.314)) literal.313 (body/source/slatex.error literal.312 (value-number (exact-number 2)))))))) (value-unspecified)) ((lambda (source/%temp%.4) (begin (begin (ref-set! source/slatex.*intext?* source/%:g7%) (value-unspecified)) (begin (ref-set! source/slatex.*code-env-spec* source/%:g8%) (value-unspecified)) source/%temp%.4)) (body/source/scheme2tex source/in.25 source/out.7)))) (binding-value source/slatex.*intext?*) (binding-value source/slatex.*code-env-spec*)))))))))) (if (value-truth? (binding-value source/slatex.*slatex-in-protected-region?*)) (begin (ref-set! source/slatex.*protected-files* (primitive/cons/2 source/aux.tex.1 (binding-value source/slatex.*protected-files*))) (value-unspecified)) (value-unspecified)) (if (value-truth? (primitive/memq/2 source/typ.1 literal.321)) (body/source/slatex.process-tex-file source/aux.tex.1) (value-unspecified)) (body/source/slatex.delete-file source/aux.scm))))) (primitive/string-append/2 source/aux literal.303))) (primitive/string-append/2 source/aux literal.302)))
      (body/source/slatex.new-aux-file (value-null)))))

(ref-set!
  source/slatex.trigger-scheme2tex
  (value-procedure (ref (unit)) (function-3 body/source/slatex.trigger-scheme2tex)))

(define source/slatex.trigger-region (ref (value-uninitialized)))

(define body/source/slatex.trigger-region
  (lambda (source/typ.2 source/in.26 source/env.1)
    ((lambda (source/aux.tex.2 source/aux2.tex) (begin (if (value-truth? (body/source/slatex.file-exists? source/aux2.tex)) (body/source/slatex.delete-file source/aux2.tex) (value-unspecified)) (if (value-truth? (body/source/slatex.file-exists? source/aux.tex.2)) (body/source/slatex.delete-file source/aux.tex.2) (value-unspecified)) (body/source/slatex.force-output (value-null)) ((lambda (source/%:g9% source/%:g10%) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* (value-boolean #t)) (value-unspecified)) (begin (ref-set! source/slatex.*protected-files* (value-null)) (value-unspecified)) ((lambda (source/%temp%.5) (begin (begin (ref-set! source/slatex.*slatex-in-protected-region?* source/%:g9%) (value-unspecified)) (begin (ref-set! source/slatex.*protected-files* source/%:g10%) (value-unspecified)) source/%temp%.5)) (begin (primitive/call-with-output-file/2 source/aux2.tex (value-procedure (ref (unit)) (function-1 (lambda (source/out.8) (if (value-truth? (primitive/eq?/2 source/typ.2 literal.329)) (body/source/slatex.dump-display source/in.26 source/out.8 (primitive/string-append/3 literal.327 source/env.1 literal.328)) (if (value-truth? (primitive/eq?/2 source/typ.2 literal.326)) (body/source/slatex.dump-display source/in.26 source/out.8 (primitive/string-append/2 literal.325 source/env.1)) (body/source/slatex.error literal.324 (value-number (exact-number 1))))))))) (body/source/slatex.process-tex-file source/aux2.tex) (begin (ref-set! source/slatex.*protected-files* (body/source/slatex.reverse! (binding-value source/slatex.*protected-files*))) (value-unspecified)) (primitive/call-with-input-file/2 source/aux2.tex (value-procedure (ref (unit)) (function-1 (lambda (source/in.27) (primitive/call-with-output-file/2 source/aux.tex.2 (value-procedure (ref (unit)) (function-1 (lambda (source/out.9) (body/source/slatex.inline-protected-files source/in.27 source/out.9))))))))) (body/source/slatex.delete-file source/aux2.tex))))) (binding-value source/slatex.*slatex-in-protected-region?*) (binding-value source/slatex.*protected-files*))))
      (body/source/slatex.new-primary-aux-file (value-cons literal.322 (value-null)))
      (invoke-1 (binding-value source/slatex.new-secondary-aux-file) literal.323))))

(ref-set!
  source/slatex.trigger-region
  (value-procedure (ref (unit)) (function-3 body/source/slatex.trigger-region)))

(define source/slatex.inline-protected-files (ref (value-uninitialized)))

(define body/source/slatex.inline-protected-files
  (lambda (source/in.28 source/out.10)
    ((lambda (argument.7) (let ((source/done?.1 (ref argument.7))) (invoke-0 ((lambda () (let ((source/loop.40 #f) (body/source/loop.40 #f)) (set! source/loop.40 (ref (value-uninitialized))) (set! body/source/loop.40 (lambda () (if (value-truth? (ref-get source/done?.1)) literal.344 (begin ((lambda (source/c.36) (if (value-truth? (primitive/eof-object?/1 source/c.36)) (begin (primitive/display/2 literal.343 source/out.10) (begin (ref-set! source/done?.1 (value-boolean #t)) (value-unspecified))) (if (value-truth? (primitive/char=?/2 source/c.36 (value-character #\%))) (body/source/slatex.eat-till-newline source/in.28) (if (value-truth? (primitive/char=?/2 source/c.36 (value-character #\\))) ((lambda (source/cs.2) (if (value-truth? (primitive/string=?/2 source/cs.2 literal.342)) ((lambda (source/cs.3) (if (value-truth? (primitive/member/2 source/cs.3 (binding-value source/slatex.*display-triggerers*))) (body/source/slatex.inline-protected literal.341 source/in.28 source/out.10 source/cs.3) (if (value-truth? (primitive/member/2 source/cs.3 (binding-value source/slatex.*box-triggerers*))) (body/source/slatex.inline-protected literal.340 source/in.28 source/out.10 source/cs.3) (if (value-truth? (primitive/member/2 source/cs.3 (binding-value source/slatex.*region-triggerers*))) (body/source/slatex.inline-protected literal.339 source/in.28 source/out.10 source/cs.3) (begin (primitive/display/2 literal.337 source/out.10) (primitive/display/2 source/cs.3 source/out.10) (primitive/display/2 literal.338 source/out.10)))))) (body/source/slatex.read-grouped-latexexp source/in.28)) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*intext-triggerers*))) (body/source/slatex.inline-protected literal.336 source/in.28 source/out.10 (value-boolean #f)) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*resultintext-triggerers*))) (body/source/slatex.inline-protected literal.335 source/in.28 source/out.10 (value-boolean #f)) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*display-triggerers*))) (body/source/slatex.inline-protected literal.334 source/in.28 source/out.10 source/cs.2) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*box-triggerers*))) (body/source/slatex.inline-protected literal.333 source/in.28 source/out.10 source/cs.2) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*region-triggerers*))) (body/source/slatex.inline-protected literal.332 source/in.28 source/out.10 source/cs.2) (if (value-truth? (primitive/member/2 source/cs.2 (binding-value source/slatex.*input-triggerers*))) (body/source/slatex.inline-protected literal.331 source/in.28 source/out.10 source/cs.2) (begin (primitive/display/2 literal.330 source/out.10) (primitive/display/2 source/cs.2 source/out.10)))))))))) (body/source/slatex.read-ctrl-seq source/in.28)) (primitive/display/2 source/c.36 source/out.10))))) (primitive/read-char/1 source/in.28)) (body/source/loop.40))))) (ref-set! source/loop.40 (value-procedure (ref (unit)) (function-0 body/source/loop.40))) (binding-value source/loop.40)))))))
      (value-boolean #f))))

(ref-set!
  source/slatex.inline-protected-files
  (value-procedure (ref (unit)) (function-2 body/source/slatex.inline-protected-files)))

(define source/slatex.inline-protected (ref (value-uninitialized)))

(define body/source/slatex.inline-protected
  (lambda (source/typ.3 source/in.29 source/out.11 source/env.2)
    (if (value-truth? (primitive/eq?/2 source/typ.3 literal.363))
      (begin
        (primitive/display/2 literal.357 source/out.11)
        (primitive/display/2 source/env.2 source/out.11)
        (primitive/display/2 literal.358 source/out.11)
        (body/source/slatex.dump-display
          source/in.29
          source/out.11
          (primitive/string-append/3 literal.359 source/env.2 literal.360))
        (primitive/display/2 literal.361 source/out.11)
        (primitive/display/2 source/env.2 source/out.11)
        (primitive/display/2 literal.362 source/out.11))
      (if (value-truth? (primitive/eq?/2 source/typ.3 literal.356))
        (begin
          (primitive/display/2 literal.353 source/out.11)
          (primitive/display/2 source/env.2 source/out.11)
          (body/source/slatex.dump-display
            source/in.29
            source/out.11
            (primitive/string-append/2 literal.354 source/env.2))
          (primitive/display/2 literal.355 source/out.11)
          (primitive/display/2 source/env.2 source/out.11))
        (begin
          ((lambda (source/f.10) (begin (begin (ref-set! source/slatex.*protected-files* (primitive/cdr/1 (binding-value source/slatex.*protected-files*))) (value-unspecified)) (primitive/call-with-input-file/2 source/f.10 (value-procedure (ref (unit)) (function-1 (lambda (source/in.30) (body/source/slatex.inline-protected-files source/in.30 source/out.11))))) (body/source/slatex.delete-file source/f.10)))
            (primitive/car/1 (binding-value source/slatex.*protected-files*)))
          (if (value-truth? (primitive/memq/2 source/typ.3 literal.352))
            (body/source/slatex.dump-intext source/in.29 (value-boolean #f))
            (if (value-truth? (primitive/memq/2 source/typ.3 literal.351))
              (body/source/slatex.dump-display
                source/in.29
                (value-boolean #f)
                (primitive/string-append/3 literal.349 source/env.2 literal.350))
              (if (value-truth? (primitive/memq/2 source/typ.3 literal.348))
                (body/source/slatex.dump-display
                  source/in.29
                  (value-boolean #f)
                  (primitive/string-append/2 literal.347 source/env.2))
                (if (value-truth? (primitive/eq?/2 source/typ.3 literal.346))
                  (invoke-1 (binding-value source/slatex.read-filename) source/in.29)
                  (body/source/slatex.error literal.345 (value-number (exact-number 1))))))))))))

(ref-set!
  source/slatex.inline-protected
  (value-procedure (ref (unit)) (function-4 body/source/slatex.inline-protected)))

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
        (begin
          (read-value! (read port))
          (specification count input (datum->value (read-value! (read port)))))))))

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
              (body/source/slatex.process-main-tex-file
                (if (barrier) (specification-input configured) (unreachable))))
            1)))
      (repeat 0 (value-boolean #f)))))

(unit)

;; ---- The canonical count and original predicate govern the control ----
(define (monotonic-nanoseconds)
 (let ((now (current-time 'time-monotonic))) (+ (* (time-second now) 1000000000) (time-nanosecond now))))
(let* ((count (configured-count)) (start (monotonic-nanoseconds)) (result (bench count))
       (seconds (inexact (/ (- (monotonic-nanoseconds) start) 1000000000))))
 (unless (= result 1) (error 'slatex "incorrect result" result))
 (display "+!CSVLINE!+chez-adapted,slatex:") (display count) (display ",") (write seconds) (newline))
