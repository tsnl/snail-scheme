;; Unicode scalar services and ordinary Lofi string ordering. Foreign calls
;; carry only Char/I32 scalars; strings remain in traced Lofi storage.
(define-library (lofi text)
  (export char-downcase char-upcase char-foldcase char-lower-case?
          char-alphabetic? char-numeric? char-whitespace? string<? string-foldcase
          test-text)
  (import (lofi base))

  ;; ---- Existing Unicode properties through the scalar ABI ----

  (begin
    (define-extern char-downcase "snail.library" "snail:text/downcase" (-> Char Char))
    (define-extern char-upcase "snail.library" "snail:text/upcase" (-> Char Char))
    (define-extern char-foldcase "snail.library" "snail:text/foldcase" (-> Char Char))
    (define-extern full-fold-length "snail.library" "snail:text/full-fold-length" (-> Char I32))
    (define-extern full-fold-scalar "snail.library" "snail:text/full-fold-scalar" (-> Char I32 Char))
    (define-extern raw-lowercase "snail.library" "snail:text/lowercase" (-> Char I32))
    (define-extern raw-alphabetic "snail.library" "snail:text/alphabetic" (-> Char I32))
    (define-extern raw-numeric "snail.library" "snail:text/numeric" (-> Char I32))
    ;; This is the reader's exact provider, including scalar validation/cleanup.
    (define-extern raw-whitespace "snail.library" "snail:datum/whitespace" (-> Char I32))

    (def char-alphabetic? (-> Char Bool)
         (lambda (character) (i32-eq (raw-alphabetic character) (ann 1 I32))))

    (def char-lower-case? (-> Char Bool)
         (lambda (character) (i32-eq (raw-lowercase character) (ann 1 I32))))

    (def char-numeric? (-> Char Bool)
         (lambda (character) (i32-eq (raw-numeric character) (ann 1 I32))))

    (def char-whitespace? (-> Char Bool)
         (lambda (character) (i32-eq (raw-whitespace character) (ann 1 I32))))

    ;; ---- Full case folding owns fresh storage and permits scalar expansions ----

    ;; The first traversal computes the exact allocation length. Each prefix is
    ;; checked against the string representation's U32_MAX - 1 limit before the
    ;; next small scalar count is added, so the I64 addition cannot wrap.
    (def folded-length (-> String I64)
         (lambda (source)
           (begin
             (def loop
                  (lambda (index count)
                    (if (> count (ann 4294967294 I64))
                        (unreachable)
                        (if (= index (string-length source))
                            count
                            (loop (+ index (ann 1 I64)) (+ count (i32->i64 (full-fold-length (string-ref source index)))))))))
             (loop (ann 0 I64) (ann 0 I64)))))

    (def copy-folded-character! (-> String I64 Char I64)
         (lambda (target offset character)
           (begin (let count (full-fold-length character))
                  (begin
                    (def loop
                         (lambda (component position)
                           (if (i32-eq component count)
                               position
                               (begin
                                 (string-set! target position (full-fold-scalar character component))
                                 (loop (i32-add component (ann 1 I32)) (+ position (ann 1 I64)))))))
                    (loop (ann 0 I32) offset)))))

    ;; No callbacks or source mutations occur between the two traversals. Their
    ;; counts therefore agree. The source and initialized destination remain live
    ;; managed references; every foreign call receives and returns only scalars.
    (def string-foldcase (-> String String)
         (lambda (source)
           (begin (let result (make-string (folded-length source)))
                  (begin
                    (def loop
                         (lambda (index offset)
                           (if (= index (string-length source))
                               result
                               (loop (+ index (ann 1 I64)) (copy-folded-character! result offset (string-ref source index))))))
                    (loop (ann 0 I64) (ann 0 I64))))))

    ;; ---- First unequal scalar or proper prefix decides ordering ----

    ;; Every scalar before index is equal. Check both ends before either read;
    ;; no callback or mutation occurs during this invocation's character loop.

    (def string<? (-> String String Bool)
         (lambda (left right)
           (begin (let lofi-migration-let-1 (string-length left)) (let lofi-migration-let-2 (string-length right))
                  (let left-count lofi-migration-let-1)
                  (let right-count lofi-migration-let-2)
                  (begin
                    (def loop
                         (lambda (index)
                           (if (= index left-count)
                               (< index right-count)
                               (if (= index right-count)
                                   #f
                                   (begin (let lofi-migration-let-3 (string-ref left index)) (let lofi-migration-let-4 (string-ref right index))
                                          (let a lofi-migration-let-3)
                                          (let b lofi-migration-let-4)
                                          (if (char=? a b) (loop (+ index (ann 1 I64))) (char<? a b)))))))
                    (loop (ann 0 I64))))))

    ;; ---- Tests ----

    ;; Test entry points are ordinary Lofi exports; no feature expansion is required.

    (def test-text (-> I64)
         (lambda ()
           (if (if (not (string<? "" ""))
                   (if (string<? "" "a")
                       (if (not (string<? "a" ""))
                           (if (not (string<? "same" "same"))
                               (if (string<? "a" "aa")
                                   (if (not (string<? "aa" "a"))
                                       (if (string<? "Z" "a")
                                           (if (string<? "\xe000;" "\x10000;") (string<? "e\x301;" "é") #f)
                                           #f)
                                       #f)
                                   #f)
                               #f)
                           #f)
                       #f)
                   #f)
               (ann 42 I64)
               (ann 0 I64))))))
