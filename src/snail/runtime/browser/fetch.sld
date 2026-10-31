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
    (extern request-method "snail.runtime.browser.fetch" "request-method" (-> Bytes Unit))
    (extern request-url "snail.runtime.browser.fetch" "request-url" (-> Bytes Unit))
    (extern request-header "snail.runtime.browser.fetch" "request-header" (-> Bytes Unit))
    (extern request-body "snail.runtime.browser.fetch" "request-body" (-> Bytes Unit))
    (extern start-request "snail.runtime.browser.fetch" "start-request" (-> I64 Unit))
    (extern finish-request "snail.runtime.browser.fetch" "finish-request" (-> I64 I32))
    (extern stream-open "snail.runtime.browser.fetch" "stream-open" (-> Bytes I32))
    (extern stream-start "snail.runtime.browser.fetch" "stream-start" (-> I64 I32 Unit))
    (extern stream-finish "snail.runtime.browser.fetch" "stream-finish" (-> I64 I32))
    (extern stream-close "snail.runtime.browser.fetch" "stream-close" (-> I32 Unit))
    (extern reply-count "snail.runtime.browser.fetch" "reply-count" (-> I32))
    (extern reply-scalar "snail.runtime.browser.fetch" "reply-scalar" (-> I32 I32))))
