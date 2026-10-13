(import (snail strict))

;; ---- Native providers ----

;; These are raw scalar carriers. The provider validates Unicode on writes;
;; read-code returns a Unicode scalar, -1 for EOF, or -2 for a saved error.
(define-extern read-code "snail.library" "snail:io/read-code" (-> I32 I32))
(define-extern write-code "snail.library" "snail:io/write-code" (-> I32 I32 I32))
(define-extern raise-error "snail.library" "snail:io/raise-error" (-> Unit))
(define-extern output-id "snail.abi" "probe:output-id" (-> I32))

;; ---- Character-by-character copy ----

(: copy-code (-> I32 Unit))
(define (copy-code input-id)
  (let ((code (read-code input-id)))
    (if (i32-eq code (ann -1 I32))
        (unit)
        (begin
          (when (i32-eq code (ann -2 I32)) (raise-error) (unreachable))
          (when (i32-eq (write-code (output-id) code) (ann -2 I32))
            (raise-error)
            (unreachable))
          (copy-code input-id)))))

(unit)
