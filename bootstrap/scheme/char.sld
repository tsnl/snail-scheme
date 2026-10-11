(define-library (scheme char)
  (export char-alphabetic? char-numeric? char-whitespace? char-ci=? string-ci=?)
  (import (scheme base) (only (snail-scheme core)
                              char-alphabetic? char-numeric? char-whitespace? char-ci=?))
  (begin
    ;; Follow the runtime's existing per-character case-insensitive comparison.
    (define (same-text? a b)
      (and (= (string-length a) (string-length b))
           (let loop ((index 0))
             (or (= index (string-length a))
                 (and (char-ci=? (string-ref a index) (string-ref b index)) (loop (+ index 1)))))))
    (define (string-ci=? first second . rest)
      (and (same-text? first second)
           (or (null? rest) (apply string-ci=? second rest))))))
