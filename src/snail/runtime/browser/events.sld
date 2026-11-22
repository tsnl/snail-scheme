;; The page's input and boot report, as host/browser/runtime.mjs provides
;; them. (snail shell page)'s `host-events` is made of these;
;; waiting for an event is a started and finished host operation.
(define-library (snail runtime browser events)
  (export
   start-wait
   finish-wait
   poll
   field
   seed
   width
   height
   boot
   ready)
  (import
   (snail core base))
  (begin
    (extern start-wait "snail.runtime.browser.events" "start-wait" (Fn I64 → Unit))
    (extern finish-wait "snail.runtime.browser.events" "finish-wait" (Fn I64 → Unit))
    (extern poll "snail.runtime.browser.events" "poll" (Fn → I32))
    (extern field "snail.runtime.browser.events" "field" (Fn I32 → I32))
    (extern seed "snail.runtime.browser.events" "seed" (Fn → I32))
    (extern width "snail.runtime.browser.events" "width" (Fn → I32))
    (extern height "snail.runtime.browser.events" "height" (Fn → I32))
    (extern boot "snail.runtime.browser.events" "boot" (Fn I32 → Unit))
    (extern ready "snail.runtime.browser.events" "ready" (Fn → Unit))))
