(define-library (scheme char)
  (export char-alphabetic? char-numeric? char-whitespace? char-upper-case? char-lower-case? digit-value
          char-ci=? char-ci<? char-ci<=? char-ci>? char-ci>=? char-upcase char-downcase char-foldcase
          string-ci=? string-ci<? string-ci<=? string-ci>? string-ci>=? string-upcase string-downcase string-foldcase)
  (import (only (snail-scheme core)
                char-alphabetic? char-numeric? char-whitespace? char-upper-case? char-lower-case? digit-value
                char-ci=? char-ci<? char-ci<=? char-ci>? char-ci>=? char-upcase char-downcase char-foldcase
                string-ci=? string-ci<? string-ci<=? string-ci>? string-ci>=? string-upcase string-downcase string-foldcase)))
