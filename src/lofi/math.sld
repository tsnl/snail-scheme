;; Scalar real mathematics shared by the native and linked Wasm runtimes.
(define-library (lofi math)
  (export sin cos tan asin acos atan atan2 exp log pow)
  (import
   (lofi base))

  ;; ---- Binary64 trigonometry ----

  ;; These ordinary typed externs never pass Lofi values to Rust. atan is
  ;; the one-argument arctangent; quadrant selection belongs to its caller.
  (begin
    (define-extern sin "snail.library" "snail:math/sin" (-> F64 F64))
    (define-extern cos "snail.library" "snail:math/cos" (-> F64 F64))
    (define-extern tan "snail.library" "snail:math/tan" (-> F64 F64))
    (define-extern asin "snail.library" "snail:math/asin" (-> F64 F64))
    (define-extern acos "snail.library" "snail:math/acos" (-> F64 F64))
    (define-extern atan "snail.library" "snail:math/atan" (-> F64 F64))
    (define-extern atan2 "snail.library" "snail:math/atan2" (-> F64 F64 F64))

    ;; ---- Real-valued exponentials and logarithms ----

    ;; Invalid real domains return NaN. Numeric-tower libraries choose when to
    ;; promote an operation to complex arithmetic before calling these scalars.
    (define-extern exp "snail.library" "snail:math/exp" (-> F64 F64))
    (define-extern log "snail.library" "snail:math/log" (-> F64 F64))
    (define-extern pow "snail.library" "snail:math/pow" (-> F64 F64 F64))))
