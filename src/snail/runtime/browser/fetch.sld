;; The page's requests and event streams, as host/browser/ui.mjs provides
;; them: a request is staged a part at a time and then started, and its reply
;; is read back a scalar at a time. (snail shell fetch page) implements the
;; `fetch` effect over these.
(define-library (snail runtime browser fetch)
  (export
   request-method
   request-url
   request-header
   request-body
   start-request
   finish-request
   stream-open
   stream-start
   stream-finish
   stream-close
   reply-count
   reply-scalar)
  (import
   (snail core base))
  (begin
    (extern request-method "snail.runtime.browser.fetch" "request-method" (Fn Bytes → Unit))
    (extern request-url "snail.runtime.browser.fetch" "request-url" (Fn Bytes → Unit))
    (extern request-header "snail.runtime.browser.fetch" "request-header" (Fn Bytes → Unit))
    (extern request-body "snail.runtime.browser.fetch" "request-body" (Fn Bytes → Unit))
    (extern start-request "snail.runtime.browser.fetch" "start-request" (Fn I64 → Unit))
    (extern finish-request "snail.runtime.browser.fetch" "finish-request" (Fn I64 → I32))
    (extern stream-open "snail.runtime.browser.fetch" "stream-open" (Fn Bytes → I32))
    (extern stream-start "snail.runtime.browser.fetch" "stream-start" (Fn I64 I32 → Unit))
    (extern stream-finish "snail.runtime.browser.fetch" "stream-finish" (Fn I64 → I32))
    (extern stream-close "snail.runtime.browser.fetch" "stream-close" (Fn I32 → Unit))
    (extern reply-count "snail.runtime.browser.fetch" "reply-count" (Fn → I32))
    (extern reply-scalar "snail.runtime.browser.fetch" "reply-scalar" (Fn I32 → I32))))
