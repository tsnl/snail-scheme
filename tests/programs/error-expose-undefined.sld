(import
 (snail core base))

;; A foreign function has no definition to export.
(extern host-time "snail.test" "time" (-> I64))
(expose host-time "time")
