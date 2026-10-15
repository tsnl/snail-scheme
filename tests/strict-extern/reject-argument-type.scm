(import (snail strict))
(define-extern foreign "probe" "id" (-> I32 I32))
(foreign #t)
