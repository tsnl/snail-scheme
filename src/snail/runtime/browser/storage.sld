;; The page's saved state, as host/browser/runtime.mjs provides it: loading
;; and storing are started and finished host operations, and a load is read
;; back a byte at a time. (snail shell page)'s `host-storage` is made
;; of these.
(define-library (snail runtime browser storage)
  (export
   read-setting
   write-setting
   start-load
   finish-load
   start-store
   finish-store
   byte)
  (import
   (snail core base))
  (begin
    (extern read-setting "snail.runtime.browser.storage" "read-setting" (Fn I32 Bytes → I32))
    (extern write-setting "snail.runtime.browser.storage" "write-setting" (Fn I32 Bytes → Unit))
    (extern start-load "snail.runtime.browser.storage" "start-load" (Fn I64 → Unit))
    (extern finish-load "snail.runtime.browser.storage" "finish-load" (Fn I64 → I32))
    (extern start-store "snail.runtime.browser.storage" "start-store" (Fn I64 Bytes → Unit))
    (extern finish-store "snail.runtime.browser.storage" "finish-store" (Fn I64 → I32))
    (extern byte "snail.runtime.browser.storage" "byte" (Fn I32 → U8))))
