(import (scheme base)
        (rename (snail-scheme extensions) (+ foreign-plus)))

;; The native extension deliberately exports a name also used by scheme/base.
;; Binding identities must preserve both implementations through direct lowering.
(+ (foreign-plus 1 2) 3)
