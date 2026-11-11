;; The page's document, as host/browser/ui.mjs provides it: nodes and
;; listeners are I32 handles. A string crosses as UTF-8 Bytes, the call's
;; last argument. A name and its value cross as one, the name ended by a
;; NUL, which no attribute or property name holds. A string coming back
;; crosses a scalar at a time: the call answers how many, and
;; `reply-scalar` reads each, until the next call that answers a string.
;; (snail shell dom page) implements the `dom` effect over these.
(define-library (snail runtime browser dom)
  (export
   root
   refresh-page
   create-element
   create-text
   set-attribute
   set-text
   set-string-property
   set-number-property
   set-flag-property
   string-property
   number-property
   reply-scalar
   insert
   remove
   listen
   listen-chord
   unlisten
   focus
   confirm
   installation-status
   start-install
   finish-install
   fullscreen
   start-fullscreen
   finish-fullscreen
   element-by-id
   select-range
   selection-start
   selection-end
   insert-text
   measure
   measured
   wake
   event-number
   event-text)
  (import
   (snail core base))
  (begin
    (extern root "snail.runtime.browser.dom" "root" (impl (Fn -> I32)))
    (extern create-element "snail.runtime.browser.dom" "create-element" (impl (Fn Bytes -> I32)))
    (extern create-text "snail.runtime.browser.dom" "create-text" (impl (Fn Bytes -> I32)))
    (extern set-attribute "snail.runtime.browser.dom" "set-attribute" (impl (Fn I32 Bytes -> Unit)))
    (extern set-text "snail.runtime.browser.dom" "set-text" (impl (Fn I32 Bytes -> Unit)))
    (extern set-string-property
            "snail.runtime.browser.dom"
            "set-string-property"
            (impl (Fn I32 Bytes -> Unit)))
    (extern set-number-property
            "snail.runtime.browser.dom"
            "set-number-property"
            (impl (Fn I32 F64 Bytes -> Unit)))
    (extern set-flag-property
            "snail.runtime.browser.dom"
            "set-flag-property"
            (impl (Fn I32 I32 Bytes -> Unit)))
    (extern string-property
            "snail.runtime.browser.dom"
            "string-property"
            (impl (Fn I32 Bytes -> I32)))
    (extern number-property
            "snail.runtime.browser.dom"
            "number-property"
            (impl (Fn I32 Bytes -> F64)))
    (extern reply-scalar "snail.runtime.browser.dom" "reply-scalar" (impl (Fn I32 -> I32)))
    (extern insert "snail.runtime.browser.dom" "insert" (impl (Fn I32 I32 I32 -> Unit)))
    (extern remove "snail.runtime.browser.dom" "remove" (impl (Fn I32 -> Unit)))
    (extern listen "snail.runtime.browser.dom" "listen" (impl (Fn I32 I32 I32 Bytes -> I32)))
    (extern listen-chord
            "snail.runtime.browser.dom"
            "listen-chord"
            (impl (Fn I32 I32 Bytes -> Unit)))
    (extern unlisten "snail.runtime.browser.dom" "unlisten" (impl (Fn I32 -> Unit)))
    (extern focus "snail.runtime.browser.dom" "focus" (impl (Fn I32 -> Unit)))
    (extern installation-status
            "snail.runtime.browser.dom"
            "installation-status"
            (impl (Fn -> I32)))
    (extern start-install "snail.runtime.browser.dom" "start-install" (impl (Fn I64 -> Unit)))
    (extern finish-install "snail.runtime.browser.dom" "finish-install" (impl (Fn I64 -> I32)))
    (extern fullscreen "snail.runtime.browser.dom" "fullscreen" (impl (Fn -> I32)))
    (extern start-fullscreen
            "snail.runtime.browser.dom"
            "start-fullscreen"
            (impl (Fn I64 I32 -> Unit)))
    (extern finish-fullscreen
            "snail.runtime.browser.dom"
            "finish-fullscreen"
            (impl (Fn I64 -> I32)))
    (extern refresh-page "snail.runtime.browser.dom" "refresh-page" (impl (Fn -> Unit)))
    (extern confirm "snail.runtime.browser.dom" "confirm" (impl (Fn Bytes -> I32)))
    (extern element-by-id "snail.runtime.browser.dom" "element-by-id" (impl (Fn Bytes -> I32)))
    (extern select-range "snail.runtime.browser.dom" "select-range" (impl (Fn I32 I32 I32 -> Unit)))
    (extern selection-start "snail.runtime.browser.dom" "selection-start" (impl (Fn I32 -> I32)))
    (extern selection-end "snail.runtime.browser.dom" "selection-end" (impl (Fn I32 -> I32)))
    (extern insert-text
            "snail.runtime.browser.dom"
            "insert-text"
            (impl (Fn I32 I32 I32 Bytes -> I32)))
    (extern measure "snail.runtime.browser.dom" "measure" (impl (Fn I32 -> Unit)))
    (extern measured "snail.runtime.browser.dom" "measured" (impl (Fn I32 -> F64)))
    (extern wake "snail.runtime.browser.dom" "wake" (impl (Fn -> Unit)))
    (extern event-number "snail.runtime.browser.dom" "event-number" (impl (Fn I32 -> F64)))
    (extern event-text "snail.runtime.browser.dom" "event-text" (impl (Fn I32 -> I32)))))
