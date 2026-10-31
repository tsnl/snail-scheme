;; The page's input and boot report, as host/browser/runtime.mjs provides
;; them. (snail shell page)'s `events` effect defaults to these; waiting for
;; an event is a started and finished host operation.
(define-library (snail runtime browser events)
  (export
   start-wait
   finish-wait
   poll
   field
   seed
   width
   height
   boot)
  (import
   (snail core base))
  (begin
    (extern start-wait "snail.runtime.browser.events" "start-wait" (-> I64 Unit))
    (extern finish-wait "snail.runtime.browser.events" "finish-wait" (-> I64 Unit))
    (extern poll "snail.runtime.browser.events" "poll" (-> I32))
    (extern field "snail.runtime.browser.events" "field" (-> I32 I32))
    (extern seed "snail.runtime.browser.events" "seed" (-> I32))
    (extern width "snail.runtime.browser.events" "width" (-> I32))
    (extern height "snail.runtime.browser.events" "height" (-> I32))
    (extern boot "snail.runtime.browser.events" "boot" (-> I32 Unit))))
