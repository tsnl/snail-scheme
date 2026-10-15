(import (snail strict) (snail text) (snail io))

;; ---- Public Char APIs retain scalar types across the worker boundary ----

(: lower (-> Char Char))
(define (lower value) (char-downcase value))
(: alphabetic (-> Char Bool))
(define (alphabetic value) (char-alphabetic? value))
(: numeric (-> Char Bool))
(define (numeric value) (char-numeric? value))
(: whitespace (-> Char Bool))
(define (whitespace value) (char-whitespace? value))

;; ---- Hosts populate ordinary mutable Scheme strings through scalar workers ----

(define left (ref (make-string 0)))
(define right (ref (make-string 0)))
(: fresh-strings (-> I64 I64 Unit))
(define (fresh-strings a b) (ref-set! left (make-string a)) (ref-set! right (make-string b)))
(: fill-left (-> I64 Char Unit))
(define (fill-left index value) (string-set! (ref-get left) index value))
(: fill-right (-> I64 Char Unit))
(define (fill-right index value) (string-set! (ref-get right) index value))
(: ordered (-> Bool))
(define (ordered) (string<? (ref-get left) (ref-get right)))
(: self-ordered (-> Bool))
(define (self-ordered) (string<? (ref-get left) (ref-get left)))

;; ---- Malformed raw callers must release files before the fatal diagnostic ----

(define-extern raw-downcase "snail.library" "snail:text/downcase" (-> I32 I32))
(define-extern raw-alphabetic "snail.library" "snail:text/alphabetic" (-> I32 I32))
(define-extern raw-numeric "snail.library" "snail:text/numeric" (-> I32 I32))
(define-extern raw-whitespace "snail.library" "snail:datum/whitespace" (-> I32 I32))
(: malformed (-> I64 I32 Unit))
(define (malformed operation code)
  (let ((port (open-output-file "pending.txt"))) (write-string "buffered" port))
  (if (= operation 0) (raw-downcase code)
      (if (= operation 1) (raw-alphabetic code)
          (if (= operation 2) (raw-numeric code) (raw-whitespace code))))
  (unreachable))
(unit)
