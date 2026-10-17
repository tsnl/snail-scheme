;; Text crosses scalar services as owned token handles. Symbols keep only an
;; interned identity; strings and exact I64 formatting remain managed Lofi data.
(define-library (lofi scalar-text)
  (export Symbol string->symbol symbol->string symbol=? i64->string datum-fail
          stage-text token-close token->symbol)
  (import
   (scheme base)
   (only (lofi core) data def ann define-extern -> I32 I64 Char Unit String Bool Never)
   (only (lofi base) i64->i32 i32-eq unreachable))
  (begin

    ;; ---- Owned scalar text handles ----

    (define-extern token-open "snail.library" "snail:datum/token-open" (-> I32))
    (define-extern token-character "snail.library" "snail:datum/token-character" (-> I32 Char Unit))
    (define-extern token-close "snail.library" "snail:datum/token-close" (-> I32 Unit))
    (define-extern token-intern "snail.library" "snail:datum/token-intern" (-> I32 I32))
    (define-extern raw-fail "snail.library" "snail:datum/fail" (-> I32 Unit))
    (define-extern symbol-length "snail.library" "snail:datum/symbol-length" (-> I32 I64))
    (define-extern symbol-character "snail.library" "snail:datum/symbol-character" (-> I32 I32 Char))

    ;; No callback runs while staging. The caller must close the returned token
    ;; or consume it through interning/failure; the provider releases it on traps.
    (def stage-text (-> String I32)
         (lambda (text)
           (let ((handle (token-open)))
             (let loop ((at (ann 0 I64)))
               (unless (= at (string-length text))
                 (token-character handle (string-ref text at))
                 (loop (+ at (ann 1 I64))))) handle)))
    (def datum-fail (-> String Never)
         (lambda (message) (raw-fail (stage-text message)) (unreachable)))

    ;; ---- Interned symbols own no temporary text ----

    (data Symbol ()
      (symbol
       (id I32 symbol-id)))
    (def token->symbol (-> I32 Symbol)
         (lambda (handle) (symbol (token-intern handle))))
    (def string->symbol (-> String Symbol)
         (lambda (text) (token->symbol (stage-text text))))
    (def symbol=? (-> Symbol Symbol Bool)
         (lambda (left right) (i32-eq (symbol-id left) (symbol-id right))))
    (def symbol->string (-> Symbol String)
         (lambda (value)
           (let* ((id (symbol-id value)) (count (symbol-length id)) (text (make-string count)))
             (let loop ((at (ann 0 I64)))
               (unless (= at count)
                 (string-set! text at (symbol-character id (i64->i32 at)))
                 (loop (+ at (ann 1 I64))))) text)))

    ;; ---- Exact decimal formatting ----

    ;; A nonpositive magnitude also represents I64_MIN. Every remainder is in
    ;; [-9, 0], so converting a digit never negates the whole minimum integer.
    (define (decimal-digits value)
      (let loop ((value value) (count (ann 1 I64)))
        (if (> value (ann -10 I64)) count
            (loop (quotient value (ann 10 I64)) (+ count (ann 1 I64))))))
    (define (write-decimal! text value at)
      (string-set! text at (integer->char (- (ann 48 I64) (remainder value (ann 10 I64)))))
      (unless (> value (ann -10 I64))
        (write-decimal! text (quotient value (ann 10 I64)) (- at (ann 1 I64)))))
    (def i64->string (-> I64 String)
         (lambda (value)
           (let* ((negative (< value (ann 0 I64)))
                  (magnitude (if negative value (- (ann 0 I64) value)))
                  (count (+ (decimal-digits magnitude) (if negative (ann 1 I64) (ann 0 I64))))
                  (text (make-string count)))
             (when negative (string-set! text (ann 0 I64) #\-))
             (write-decimal! text magnitude (- count (ann 1 I64))) text)))))
