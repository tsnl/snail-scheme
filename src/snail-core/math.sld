;; Elementary functions on F64, computed by the runtime.
(define-library (snail-core math)
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
   (snail-core base))
  (begin

    (define pi 3.141592653589793)

    (extern sin "snail.library" "snail:math/sin" (-> F64 F64))
    (extern cos "snail.library" "snail:math/cos" (-> F64 F64))
    (extern tan "snail.library" "snail:math/tan" (-> F64 F64))
    (extern asin "snail.library" "snail:math/asin" (-> F64 F64))
    (extern acos "snail.library" "snail:math/acos" (-> F64 F64))
    (extern atan "snail.library" "snail:math/atan" (-> F64 F64))
    (extern atan2 "snail.library" "snail:math/atan2" (-> F64 F64 F64))
    (extern exp "snail.library" "snail:math/exp" (-> F64 F64))
    (extern log "snail.library" "snail:math/log" (-> F64 F64))
    (extern expt "snail.library" "snail:math/pow" (-> F64 F64 F64))

    ))
