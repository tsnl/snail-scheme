;; The page's saved state, as host/browser/runtime.mjs provides it: loading
;; and storing are started and finished host operations, and a load is read
;; back a byte at a time. (snail shell page)'s `storage` effect defaults to
;; these.
(define-library (snail runtime browser storage)
  (export
   start-load
   finish-load
   start-store
   finish-store
   byte)
  (import
   (snail core base))
  (begin
    (extern start-load "snail.runtime.browser.storage" "start-load" (-> I64 Unit))
    (extern finish-load "snail.runtime.browser.storage" "finish-load" (-> I64 I32))
    (extern start-store "snail.runtime.browser.storage" "start-store" (-> I64 Bytes Unit))
    (extern finish-store "snail.runtime.browser.storage" "finish-store" (-> I64 Unit))
    (extern byte "snail.runtime.browser.storage" "byte" (-> I32 U8))))
