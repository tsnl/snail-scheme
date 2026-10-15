(import (snail strict))

;; ---- Native character provider and scalar results ----

;; A successful read returns one Unicode scalar, regardless of its UTF-8 width.
;; The frozen provider returns -1 for EOF and -2 for a saved fatal diagnostic.
(define-extern read-code "snail.library" "snail:io/read-code" (-> I32 I32))
(define-extern raise-error "snail.library" "snail:io/raise-error" (-> Unit))
(define-extern submit-counts "snail.abi" "probe:counts" (-> I64 I64 I64 Unit))

(: read-character (-> I32 I32))
(define (read-character input-id)
  (let ((code (read-code input-id)))
    (when (i32-eq code (ann -2 I32)) (raise-error) (unreachable))
    code))

;; ---- Original wc state transitions ----

;; Only ASCII space and newline delimit words. Tabs, carriage returns, NUL,
;; and every other Unicode scalar belong to a word, as in the original source.
(: separator? (-> I32 Bool))
(define (separator? code)
  (or (i32-eq code (ann 32 I32)) (i32-eq code (ann 10 I32))))

(: count-loop (-> I32 I64 I64 I64 Bool Unit))
(define (count-loop input-id lines words characters inword?)
  (let* ((code (read-character input-id)) (separator (separator? code)))
    (if (i32-eq code (ann -1 I32))
        (submit-counts lines words characters)
        (count-loop input-id
                    (if (i32-eq code (ann 10 I32)) (i64-add lines 1) lines)
                    (if (or separator inword?) words (i64-add words 1))
                    (i64-add characters 1)
                    (not separator)))))

(: count-code (-> I32 Unit))
(define (count-code input-id)
  (count-loop input-id 0 0 0 #f))

(unit)
