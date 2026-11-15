;; Unicode character properties and case mapping, read from the tables of
;; (snail shell text unicode), which Rust's Unicode properties generate
;; (crates/snail-scheme-support/examples/unicode-tables).
(define-library (snail shell text)
  (export
   char-upcase
   char-downcase
   char-foldcase
   char-unicode-alphabetic?
   char-unicode-numeric?
   char-unicode-whitespace?
   char-lower-case?
   char-upper-case?
   char-digit-value
   string-upcase
   string-downcase
   string-foldcase)
  (import
   (snail core base)
   (snail shell text unicode))
  (begin

    ;; ---- Records ----

    ;; A scalar's record holds its properties. Its block, the scalar
    ;; shifted right, names a run of record numbers, which blocks with the
    ;; same records share; its place in the block picks its record.

    (define (record (char Char)) (→ I64)
      (let* ((point (char->integer char))
             (shift (unicode-shift))
             (block (u8->i64
                     (constant-array-ref (unicode-blocks) (i64-shift-right/logical point shift))))
             (place (i64-and point (- (i64-shift-left 1 shift) 1))))
        (u8->i64 (constant-array-ref (unicode-runs) (+ (i64-shift-left block shift) place)))))

    (define (u8->i64 (byte U8)) (→ I64)
      (i32->i64 (u8->i32 byte)))

    (define (flag? (char Char) (bit I64)) (→ Bool)
      (not (= (i64-and (u8->i64 (constant-array-ref (unicode-flags) (record char))) bit) 0)))

    ;; A scalar moved by the delta its record holds for the mapping `table`.

    (define (mapped (char Char) (table (ConstantArray I32))) (→ Char)
      (integer->char (+ (char->integer char) (i32->i64 (constant-array-ref table (record char))))))

    ;; ---- Properties ----

    (define (char-unicode-alphabetic? (char Char)) (→ Bool)
      (flag? char 1))

    (define (char-unicode-whitespace? (char Char)) (→ Bool)
      (flag? char 2))

    (define (char-lower-case? (char Char)) (→ Bool)
      (flag? char 4))

    (define (char-upper-case? (char Char)) (→ Bool)
      (flag? char 8))

    ;; A decimal digit's value in any script, or nothing for anything else;
    ;; the table holds -1 for anything else.

    (define (char-digit-value (char Char)) (→ (Option I64))
      (let ((value (i32->i64 (constant-array-ref (unicode-digits) (record char)))))
        (if (< value 0) (None) (Some value))))

    (define (char-unicode-numeric? (char Char)) (→ Bool)
      (match (char-digit-value char)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Case ----

    ;; Simple case mapping, one scalar to one scalar.

    (define (char-upcase (char Char)) (→ Char)
      (mapped char (unicode-upper)))

    (define (char-downcase (char Char)) (→ Char)
      (mapped char (unicode-lower)))

    (define (char-foldcase (char Char)) (→ Char)
      (mapped char (unicode-fold)))

    (define (string-upcase (text String)) (→ String)
      (string-generate (string-length text) (lambda (index) (char-upcase (string-ref text index)))))

    (define (string-downcase (text String)) (→ String)
      (string-generate (string-length text)
                       (lambda (index) (char-downcase (string-ref text index)))))

    ;; Full case folding, which may expand one scalar into several, as "ß"
    ;; into "ss"; folded strings compare equal ignoring case. A scalar whose
    ;; full folding is not its simple one is among the sorted fold points,
    ;; with its scalars from its start to the next.

    (define (string-foldcase (text String)) (→ String)
      (string-concatenate (map full-fold (string->list text))))

    (define (full-fold (char Char)) (→ String)
      (match (fold-point (char->integer char) 0 (constant-array-length (unicode-fold-points)))
        ((Some index)
         (let ((start (i32->i64 (constant-array-ref (unicode-fold-starts) index)))
               (end (i32->i64 (constant-array-ref (unicode-fold-starts) (+ index 1)))))
           (string-generate (- end start)
                            (lambda (offset)
                              (integer->char
                               (i32->i64
                                (constant-array-ref (unicode-fold-scalars) (+ start offset))))))))
        ((None) (make-string 1 (char-foldcase char)))))

    ;; The index of `point` among the fold points from `low` up to `high`.

    (define (fold-point (point I64) (low I64) (high I64)) (→ (Option I64))
      (if (>= low high)
          (None)
          (let* ((middle (quotient (+ low high) 2))
                 (at (i32->i64 (constant-array-ref (unicode-fold-points) middle))))
            (cond ((= at point) (Some middle))
                  ((< at point) (fold-point point (+ middle 1) high))
                  (else (fold-point point low middle))))))

    ))
