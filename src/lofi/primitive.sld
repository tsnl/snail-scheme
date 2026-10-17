;; Intrinsic primitive functions have this public source manifest.
(define-library (lofi primitive)
  (export i32-add i32-sub i32-mul i32-eq i32-lt i32-le i32-gt i32-ge i32-quotient i32-remainder
          i32-bitwise-and i32-bitwise-xor i32-shift-right/logical i64-add i64-sub i64-mul
          i64-wrapping-add i64-wrapping-mul i64-eq i64-lt i64-le i64-gt i64-ge i64-quotient
          i64-remainder i64-bitwise-and i64-bitwise-xor i64-shift-right/logical f32-add f32-sub
          f32-mul f32-eq f32-lt f32-le f32-gt f32-ge f32-div f32-sqrt f32-truncate f32-round
          f32-floor f32-ceiling f64-add f64-sub f64-mul f64-eq f64-lt f64-le f64-gt f64-ge f64-div
          f64-ieee-add f64-ieee-sub f64-ieee-mul f64-ieee-div f64-sqrt f64-truncate f64-round
          f64-floor f64-ceiling i64->f64 i32->i64 i64->i32 f32->f64 f32->i32 f64->f32 f64->i64
          char=? char<? char<=? char>? char>=? char->integer integer->char make-string string-
          length string-ref string-set! string-eq? string-copy! substring string=? utf8->string
          string->utf8 make-bytevector bytevector-length bytevector-u8-ref bytevector-u8-set!
          bytevector-eq? bytevector-copy! not unit ref ref-get ref-set! ref-eq? empty-list cons
          car cdr null? unreachable empty-vector make-vector vector-length vector-ref vector-set!
          vector-eq? vector-copy!))
