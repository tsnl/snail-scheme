(import (lofi base))
;; The historical fixture now authors both members explicitly. The separate
;; macro-overload-extension case checks expansion across an imported family.
(define-overload select (-> I64 I64) (lambda (value) value))
(define-overload select (-> Bool I64) (lambda (value) (if value (ann 42 I64) (ann 0 I64))))
(select #t)
