(define-library (scheme char)
  (export char-alphabetic? char-numeric? char-whitespace? char-ci=?)
  (import (only (snail-scheme core)
                char-alphabetic? char-numeric? char-whitespace? char-ci=?)))
