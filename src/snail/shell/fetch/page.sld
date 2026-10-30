;; The page's `fetch` and `EventSource` for the `fetch` effect:
;; `with-page-fetch` binds each operation to the browser host
;; (host/browser/fetch.mjs). A request or a stream's next event waits by
;; ticket in the task that asked, so a command's request never holds up
;; the interface.
(define-library (snail shell fetch page)
  (export
   with-page-fetch)
  (import
   (snail core base)
   (snail shell utf8)
   (snail shell task)
   (snail shell fetch))
  (begin

    ;; ---- Handling ----

    (: with-page-fetch (All (T e) (-> (-> T ! fetch e) T ! e)))
    (define (with-page-fetch work)
      (handle fetch
          ((request page-request)
           (stream-open (lambda (url kinds)
                          (Stream (host-stream-open (string->utf8 (string-join (Cons url kinds)
                                                                               (make-string 1
                                                                                            #\null)))))))
           (stream-next page-stream-next)
           (stream-close (lambda (stream) (host-stream-close (Stream-id stream)))))
        (work)))

    ;; A request crosses in parts, each a string as UTF-8 Bytes, and starts
    ;; once they are all there: its method, its URL, each header as its
    ;; name and value with a NUL between, and its body. Nothing else runs
    ;; between the parts and the start. The reply's status comes back from
    ;; the wait, -1 when there was no reply, and its body, or why there was
    ;; none, a scalar at a time.
    (: page-request (-> String String (List Header) String (Result Reply String) ! tasks))
    (define (page-request method url headers body)
      (host-request-method (string->utf8 method))
      (host-request-url (string->utf8 url))
      (for-each (lambda (header)
                  (host-request-header (string->utf8 (string-append (Header-name header)
                                                                    (make-string 1 #\null)
                                                                    (Header-value header)))))
                headers)
      (host-request-body (string->utf8 body))
      (let ((status (through-host host-start-request host-finish-request)))
        (if (< status 0) (Err (host-reply)) (Ok (Reply status (host-reply))))))

    ;; A stream opens with its URL and the kinds it hears as one string, a
    ;; NUL between each. The wait answers -1 once the stream is closed, and
    ;; otherwise leaves the next event's kind and data, a NUL between them.
    (: page-stream-next (-> Stream (Option StreamEvent) ! tasks))
    (define (page-stream-next stream)
      (let ((count (through-host (lambda (ticket) (host-stream-start ticket (Stream-id stream)))
                                 host-stream-finish)))
        (if (< count 0) (None) (Some (stream-event (host-reply))))))

    (: stream-event (-> String StreamEvent))
    (define (stream-event text)
      (match (string-index text #\null)
        ((Some end)
         (StreamEvent (substring text 0 end) (substring text (+ end 1) (string-length text))))
        ((None) (panic "internal error: a stream's event has no kind"))))

    ;; ---- The browser host ----

    (extern host-request-method "snail.runtime.browser.fetch" "request-method" (-> Bytes Unit))
    (extern host-request-url "snail.runtime.browser.fetch" "request-url" (-> Bytes Unit))
    (extern host-request-header "snail.runtime.browser.fetch" "request-header" (-> Bytes Unit))
    (extern host-request-body "snail.runtime.browser.fetch" "request-body" (-> Bytes Unit))
    (extern host-start-request "snail.runtime.browser.fetch" "start-request" (-> I64 Unit))
    (extern host-finish-request "snail.runtime.browser.fetch" "finish-request" (-> I64 I32))
    (extern host-stream-open "snail.runtime.browser.fetch" "stream-open" (-> Bytes I32))
    (extern host-stream-start "snail.runtime.browser.fetch" "stream-start" (-> I64 I32 Unit))
    (extern host-stream-finish "snail.runtime.browser.fetch" "stream-finish" (-> I64 I32))
    (extern host-stream-close "snail.runtime.browser.fetch" "stream-close" (-> I32 Unit))
    (extern host-reply-count "snail.runtime.browser.fetch" "reply-count" (-> I32))
    (extern host-reply-scalar "snail.runtime.browser.fetch" "reply-scalar" (-> I32 I32))

    ;; The text the last finished wait left.
    (: host-reply (-> String))
    (define (host-reply)
      (string-generate (i32->i64 (host-reply-count))
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))))
