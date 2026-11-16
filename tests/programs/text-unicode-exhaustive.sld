;; Every Unicode scalar through (snail shell text), folded into the
;; checksum its generator computes from Rust's answers for the same
;; scalars (crates/snail-scheme-support/examples/unicode-tables), so the
;; tables and the code reading them agree with the reference everywhere.
(import
 (snail core base)
 (snail core io)
 (snail shell text)
 (only (snail shell text unicode) unicode-checksum))

(define (mix (hash I64) (value I64)) (→ I64)
  (modulo (+ (* hash 31) value) 2147483647))

(define (flags (char Char)) (→ I64)
  (fold-left +
             0
             (list (if (char-unicode-alphabetic? char) 1 0)
                   (if (char-unicode-whitespace? char) 2 0)
                   (if (char-lower-case? char) 4 0)
                   (if (char-upper-case? char) 8 0))))

(define (digit (char Char)) (→ I64)
  (match (char-digit-value char)
    ((Some value) (+ value 1))
    ((None) 0)))

(define (mix-scalar (hash I64) (char Char)) (→ I64)
  (let* ((folded (string-foldcase (make-string 1 char)))
         (hash (fold-left mix
                          hash
                          (list (char->integer (char-upcase char))
                                (char->integer (char-downcase char))
                                (char->integer (char-foldcase char))
                                (flags char)
                                (digit char)
                                (string-length folded)))))
    (fold-left (lambda (hash scalar) (mix hash (char->integer scalar)))
               hash
               (string->list folded))))

;; Each scalar from `point`, skipping the surrogates, which are not.

(define (checksum (point I64) (hash I64)) (→ I64)
  (cond ((= point 1114112) hash)
        ((= point 55296) (checksum 57344 hash))
        (else (checksum (+ point 1) (mix-scalar hash (integer->char point))))))

(define (main) (→ Unit) (! output-port)
  (write-line (if (= (checksum 0 0) unicode-checksum) "every scalar agrees" "disagrees")))
