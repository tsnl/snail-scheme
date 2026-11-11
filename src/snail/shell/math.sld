;; Elementary functions on F64, computed by the runtime.
(define-library (snail shell math)
  (export
   pi
   sin
   cos
   tan
   asin
   acos
   atan
   atan2
   exp
   log
   expt)
  (import
   (snail core base))
  (begin

    (define pi 3.141592653589793)

    (extern sin "snail.core.support" "snail:math/sin" (impl (Fn F64 -> F64)))
    (extern cos "snail.core.support" "snail:math/cos" (impl (Fn F64 -> F64)))
    (extern tan "snail.core.support" "snail:math/tan" (impl (Fn F64 -> F64)))
    (extern asin "snail.core.support" "snail:math/asin" (impl (Fn F64 -> F64)))
    (extern acos "snail.core.support" "snail:math/acos" (impl (Fn F64 -> F64)))
    (extern atan "snail.core.support" "snail:math/atan" (impl (Fn F64 -> F64)))
    (extern atan2 "snail.core.support" "snail:math/atan2" (impl (Fn F64 F64 -> F64)))
    (extern exp "snail.core.support" "snail:math/exp" (impl (Fn F64 -> F64)))
    (extern log "snail.core.support" "snail:math/log" (impl (Fn F64 -> F64)))
    (extern expt "snail.core.support" "snail:math/pow" (impl (Fn F64 F64 -> F64)))

    ))
