;; The prototype transports data, never expressions to evaluate or live roots.
;; Record/variant codecs derived from types remain a separate planned layer.
(define-library (snail-scheme actor-wire)
  (export decode-call encode-result)
  (import (scheme base) (scheme write)
          (snail-scheme reader) (snail-scheme syntax-parser) (snail-scheme syntax))
  (begin

    ;; ---- Bounded portable data ----

    (define smallest-wire-integer (string->number "-9223372036854775808"))
    (define largest-wire-integer (string->number "9223372036854775807"))

    ;; Count tree occurrences, including shared subtrees. A depth bound rejects
    ;; cycles without preserving object identity in the receiving heap.
    (define (check-value value depth budget)
      (if (or (> depth 64) (<= budget 0)) (error "actor datum exceeds its budget"))
      (cond ((pair? value)
             (check-value (cdr value) (+ depth 1)
                          (check-value (car value) (+ depth 1) (- budget 1))))
            ((vector? value) (check-vector value depth (- budget 1)))
            ((or (string? value) (symbol? value))
             (- budget (string-length (if (symbol? value) (symbol->string value) value)) 1))
            ((or (null? value) (boolean? value) (wire-integer? value)) (- budget 1))
            (else (error "unsupported actor datum"))))

    (define (wire-integer? value)
      (and (exact-integer? value)
           (<= smallest-wire-integer value largest-wire-integer)))

    (define (check-vector items depth budget)
      (let loop ((index 0) (remaining budget))
        (if (= index (vector-length items)) remaining
            (loop (+ index 1) (check-value (vector-ref items index) (+ depth 1) remaining)))))

    (define (check-datum value)
      (if (< (check-value value 0 16384) 0) (error "actor datum exceeds its budget")))

    ;; ---- Calls from the existing reader ----

    ;; The vector is an internal AWI adapter result, not the wire representation.
    ;; Quoted forms in arguments remain ordinary list data; nothing calls eval.
    (define (decode-call text)
      (if (> (string-length text) 65536) (error "actor message is too large"))
      (let ((forms (reader->syntax-list (string->reader "<actor message>" text))))
        (if (not (= (length forms) 1)) (error "expected one actor call"))
        (let ((call (syntax->datum (car forms))))
          (check-datum call)
          (if (not (and (pair? call) (list? call) (symbol? (car call))))
              (error "expected (method argument ...)"))
          (vector (symbol->string (car call)) (list->vector (cdr call))))))

    ;; ---- Readable results ----

    ;; Always quote symbols: the runtime's ordinary writer also serves display
    ;; and currently emits symbol names literally, including spaces and digits.
    (define (write-symbol value port)
      (display "|" port)
      (for-each
       (lambda (character)
         (if (or (char=? character #\|) (char=? character #\\)) (display "\\" port))
         (display character port))
       (string->list (symbol->string value)))
      (display "|" port))

    (define (write-tail value port)
      (cond ((null? value) (display ")" port))
            ((pair? value)
             (display " " port) (write-datum (car value) port) (write-tail (cdr value) port))
            (else (display " . " port) (write-datum value port) (display ")" port))))

    (define (write-datum value port)
      (cond ((symbol? value) (write-symbol value port))
            ((pair? value)
             (display "(" port) (write-datum (car value) port) (write-tail (cdr value) port))
            ((vector? value)
             (display "#(" port)
             (if (zero? (vector-length value)) (display ")" port)
                 (begin (write-datum (vector-ref value 0) port)
                        (write-tail (cdr (vector->list value)) port))))
            (else (write value port))))

    (define (encode-result value)
      (check-datum value)
      (let ((port (open-output-string)))
        (write-datum value port)
        (let ((text (get-output-string port)))
          (close-port port)
          (if (> (string-length text) 65536) (error "actor result is too large"))
          text))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-actor-wire)
    (import (snail-scheme test-utils))
    (begin
      (define (roundtrip value)
        (vector-ref (vector-ref (decode-call (string-append "(echo " (encode-result value) ")")) 1) 0))

      (define (rejected? thunk)
        (guard (condition (else #t)) (thunk) #f))

      (define (test-actor-wire)
        (for-each (lambda (value) (expect (roundtrip value) value))
                  (list #t #f '() '(hello . world) '#(1 "a\nλ")
                        (string->symbol "a | b\\c") (string->symbol "123")
                        (string->number "-9223372036854775808")))
        (expect (vector-ref (decode-call "(echo (set! x 3))") 1) '#((set! x 3)))
        (for-each (lambda (text) (expect (rejected? (lambda () (decode-call text))) #t))
                  '("" "(echo) (echo)" "(echo . 1)" "(1 2)" "(" "(echo 1.5)"))
        (expect (rejected? (lambda () (encode-result (lambda () #t)))) #t)
        (let ((cycle (cons 1 '())))
          (set-cdr! cycle cycle)
          (expect (rejected? (lambda () (encode-result cycle))) #t)))))))
