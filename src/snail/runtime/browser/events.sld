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
   boot
   ready
   checkpoint
   handover-only
   save-after)
  (import
   (snail core base))
  (begin
    (extern start-wait "snail.runtime.browser.events" "start-wait" (impl (Fn I64 -> Unit)))
    (extern finish-wait "snail.runtime.browser.events" "finish-wait" (impl (Fn I64 -> Unit)))
    (extern poll "snail.runtime.browser.events" "poll" (impl (Fn -> I32)))
    (extern field "snail.runtime.browser.events" "field" (impl (Fn I32 -> I32)))
    (extern seed "snail.runtime.browser.events" "seed" (impl (Fn -> I32)))
    (extern width "snail.runtime.browser.events" "width" (impl (Fn -> I32)))
    (extern height "snail.runtime.browser.events" "height" (impl (Fn -> I32)))
    (extern boot "snail.runtime.browser.events" "boot" (impl (Fn I32 -> Unit)))
    (extern ready "snail.runtime.browser.events" "ready" (impl (Fn -> Unit)))
    (extern checkpoint "snail.runtime.browser.events" "checkpoint" (impl (Fn -> Unit)))
    (extern handover-only "snail.runtime.browser.events" "handover-only" (impl (Fn -> I32)))
    (extern save-after "snail.runtime.browser.events" "save-after" (impl (Fn I32 -> Unit)))))
