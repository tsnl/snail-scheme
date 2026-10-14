;; Scalar real mathematics shared by the native and linked Wasm runtimes.
(define-library (snail math)
  (export sin cos atan)
  (import (snail strict))
  (begin

    ;; ---- Binary64 trigonometry ----

    ;; These ordinary typed externs never pass Scheme values to Rust. atan is
    ;; the one-argument arctangent; quadrant selection belongs to its caller.
    (define-extern sin "snail.library" "snail:math/sin" (-> F64 F64))
    (define-extern cos "snail.library" "snail:math/cos" (-> F64 F64))
    (define-extern atan "snail.library" "snail:math/atan" (-> F64 F64))))
