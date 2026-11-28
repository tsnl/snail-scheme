;; Unicode character properties and case mapping, as ICU4X computes them in
;; the runtime (crates/snail-scheme-support/src/text.rs). A program that
;; imports this library is linked with the runtime's `unicode` feature
;; ((snail shell project build), "Programs").
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
   (snail core base))
  (begin

    ;; ---- The runtime's services ----

    (extern char-upcase "snail.core.support" "snail:text/simple-upper" (Fn Char → Char))
    (extern char-downcase "snail.core.support" "snail:text/simple-lower" (Fn Char → Char))
    (extern char-foldcase "snail.core.support" "snail:text/simple-fold" (Fn Char → Char))
    (extern properties "snail.core.support" "snail:text/properties" (Fn Char → I32))
    (extern digit-value "snail.core.support" "snail:text/digit-value" (Fn Char → I32))
    (extern upcase "snail.core.support" "snail:text/upcase" (Fn String → I32))
    (extern downcase "snail.core.support" "snail:text/downcase" (Fn String → I32))
    (extern foldcase "snail.core.support" "snail:text/foldcase" (Fn String → I32))
    (extern reply-character "snail.core.support" "snail:io/reply-character" (Fn I32 → Char))

    ;; ---- Properties ----

    ;; The binary properties are bits of one answer: 1 Alphabetic,
    ;; 2 White_Space, 4 Lowercase and 8 Uppercase.

    (define (property? (char Char) (bit I32)) (→ Bool)
      (not (= (i32-and (properties char) bit) 0)))

    (define (char-unicode-alphabetic? (char Char)) (→ Bool)
      (property? char 1))

    (define (char-unicode-whitespace? (char Char)) (→ Bool)
      (property? char 2))

    (define (char-lower-case? (char Char)) (→ Bool)
      (property? char 4))

    (define (char-upper-case? (char Char)) (→ Bool)
      (property? char 8))

    ;; A decimal digit's value in any script, or nothing for anything else.

    (define (char-digit-value (char Char)) (→ (Option I64))
      (let ((value (digit-value char)))
        (if (< value 0) (None) (Some (i32->i64 value)))))

    (define (char-unicode-numeric? (char Char)) (→ Bool)
      (match (char-digit-value char)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Strings ----

    ;; Full case mapping, which may expand one scalar into several, as "ß"
    ;; into "SS"; folded strings compare equal ignoring case. The runtime
    ;; answers a mapping's length and holds its scalars until the next.

    (define (string-upcase (text String)) (→ String)
      (reply (upcase text)))

    (define (string-downcase (text String)) (→ String)
      (reply (downcase text)))

    (define (string-foldcase (text String)) (→ String)
      (reply (foldcase text)))

    (define (reply (count I32)) (→ String)
      (string-generate (i32->i64 count) (lambda (index) (reply-character (i64->i32 index)))))

    ))
