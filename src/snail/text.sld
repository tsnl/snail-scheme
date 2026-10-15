;; Unicode scalar services and ordinary Scheme string ordering. Foreign calls
;; carry only Char/I32 scalars; strings remain in traced Scheme storage.
(define-library (snail text)
  (export char-downcase char-alphabetic? char-numeric? char-whitespace? string<?)
  (import (snail strict))
  (begin

    ;; ---- Existing Unicode properties through the scalar ABI ----

    (define-extern char-downcase "snail.library" "snail:text/downcase" (-> Char Char))
    (define-extern raw-alphabetic "snail.library" "snail:text/alphabetic" (-> Char I32))
    (define-extern raw-numeric "snail.library" "snail:text/numeric" (-> Char I32))
    ;; This is the reader's exact provider, including scalar validation/cleanup.
    (define-extern raw-whitespace "snail.library" "snail:datum/whitespace" (-> Char I32))
    (: char-alphabetic? (-> Char Bool))
    (define (char-alphabetic? character) (i32-eq (raw-alphabetic character) (ann 1 I32)))
    (: char-numeric? (-> Char Bool))
    (define (char-numeric? character) (i32-eq (raw-numeric character) (ann 1 I32)))
    (: char-whitespace? (-> Char Bool))
    (define (char-whitespace? character) (i32-eq (raw-whitespace character) (ann 1 I32)))

    ;; ---- First unequal scalar or proper prefix decides ordering ----

    ;; Every scalar before index is equal. Check both ends before either read;
    ;; no callback or mutation occurs during this invocation's character loop.
    (: string<? (-> String String Bool))
    (define (string<? left right)
      (let ((left-count (string-length left)) (right-count (string-length right)))
        (let loop ((index 0))
          (if (= index left-count) (< index right-count)
              (if (= index right-count) #f
                  (let ((a (string-ref left index)) (b (string-ref right index)))
                    (if (char=? a b) (loop (+ index 1)) (char<? a b)))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-text)
    (begin
      (: test-text (-> I64))
      (define (test-text)
        (if (and (not (string<? "" "")) (string<? "" "a")
                 (not (string<? "a" "")) (not (string<? "same" "same"))
                 (string<? "a" "aa") (not (string<? "aa" "a"))
                 (string<? "Z" "a") (string<? "\xe000;" "\x10000;")
                 (string<? "e\x301;" "é"))
            42 0))))))
