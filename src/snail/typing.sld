;; Opt-in type syntax for compiled Snail programs. The compiler's synthetic core
;; owns these identities; reexports preserve them through rename and prefix.
(define-library (snail typing)
  (export : ann inst All -> U ? Any Never Boolean False True Null ExactInteger InexactReal Number
          String Symbol Char Pair Vector Bytevector Procedure Record Unspecified i32)
  (import (only (snail-scheme core)
                : ann inst All -> U ? Any Never Boolean False True Null ExactInteger InexactReal Number
                String Symbol Char Pair Vector Bytevector Procedure Record Unspecified i32)))
