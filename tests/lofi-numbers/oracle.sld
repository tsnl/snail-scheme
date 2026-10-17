(import
 (lofi base)
 (lofi integer)
 (lofi rational))

;; ---- Scalar test transport leaves exact values in Lofi ----

(define-extern argument-length "oracle" "argument_length" (-> I32 I64))
(define-extern argument-character "oracle" "argument_character" (-> I32 I64 Char))
(define-extern emit-character "oracle" "emit_character" (-> Char Unit))
(def argument
     (lambda (index)
       (begin (let count (argument-length index))
              (begin (let text (make-string count))
                     (begin
                       (def loop
                            (lambda (at)
                              (if (= at count)
                                  text
                                  (begin (string-set! text at (argument-character index at)) (loop (+ at (ann 1 I64)))))))
                       (loop (ann 0 I64)))))))
(def emit
     (lambda (text)
       (begin
         (def loop
              (lambda (at)
                (if (= at (string-length text))
                    (unit)
                    (begin
                      (emit-character (string-ref text at)) (loop (+ at (ann 1 I64)))
                      (unit)))))
         (loop (ann 0 I64)))))

;; ---- Public conversion and rounding contracts ----

;; Fixture fractions are decimal and intentionally independent of the reader.
(def rational-input
     (lambda (text)
       (begin
         (def loop
              (lambda (at)
                (if (= at (string-length text))
                    (rational-from-integer (integer-from-string text))
                    (if (char=? (string-ref text at) #\/)
                        (make-rational (integer-from-string (substring text (ann 0 I64) at))
                                       (integer-from-string (substring text (+ at (ann 1 I64)) (string-length text))))
                        (loop (+ at (ann 1 I64)))))))
         (loop (ann 0 I64)))))
(def rational-operation
     (lambda (operation left right)
       (if (= operation (ann 8 I64))
           (rational->string (+ left right))
           (if (= operation (ann 9 I64))
               (rational->string (- left right))
               (if (= operation (ann 10 I64))
                   (rational->string (* left right))
                   (if (= operation (ann 11 I64))
                       (rational->string (/ left right))
                       (integer->string
                        (if (= operation (ann 12 I64))
                            (integer-from-i64 (rational-compare left right))
                            (if (= operation (ann 13 I64)) (truncate left) (rational-floor left))))))))))
(def rational-probe
     (lambda (operation value)
       (if (= operation (ann 15 I64))
           (rational->f64 (rational-from-f64 value))
           (begin
             (emit (if (= operation (ann 14 I64))
                       (rational->string (rational-from-f64 value))
                       (rational-operation operation (rational-input (argument (ann 0 I32)))
                                           (rational-input (argument (ann 1 I32))))))
             0.0))))

(def probe (-> I64 F64 F64)
     (lambda (operation value)
       (if (>= operation (ann 8 I64))
           (rational-probe operation value)
           (begin (let lofi-migration-let-1 (integer-from-string (argument (ann 0 I32))))
                  (let lofi-migration-let-2 (integer-from-string (argument (ann 1 I32))))
                  (let a lofi-migration-let-1)
                  (let b lofi-migration-let-2)
                  (if (= operation (ann 0 I64))
                      (integer-ratio->f64 a b)
                      (if (= operation (ann 5 I64))
                          (integer->f64 a)
                          (if (= operation (ann 7 I64))
                              (begin (emit (rational->string (make-rational a b))) 0.0)
                              (begin
                                (emit (integer->string
                                       (if (= operation (ann 1 I64))
                                           (integer-from-f64 value)
                                           (if (= operation (ann 2 I64))
                                               (integer-truncate-f64 value)
                                               (if (= operation (ann 3 I64))
                                                   (integer-floor-quotient a b)
                                                   (if (= operation (ann 4 I64)) (integer-modulo a b) (integer-gcd a b)))))))
                                0.0))))))))
(unit)
