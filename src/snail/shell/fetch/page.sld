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
   (prefix (snail runtime browser fetch) host-)
   (snail shell utf8)
   (snail shell task)
   (snail shell fetch))
  (begin

    ;; ---- Handling ----

    (define (with-page-fetch (work (Fn → T ! fetch e))) (→ T) (! e) (∀ (T e))
      (handle fetch
          ((request page-request)
           (stream-open (lambda (url kinds)
                          (new Stream
                            (id (host-stream-open (string->utf8 (string-join (Cons url kinds)
                                                                             (make-string 1
                                                                                          #\null))))))))
           (stream-next page-stream-next)
           (stream-close (lambda (stream) (host-stream-close (● stream id)))))
        (work)))

    ;; A request crosses in parts, each a string as UTF-8 Bytes, and starts
    ;; once they are all there: its method, its URL, each header as its
    ;; name and value with a NUL between, and its body. Nothing else runs
    ;; between the parts and the start. The reply's status comes back from
    ;; the wait, -1 when there was no reply, and its body, or why there was
    ;; none, a scalar at a time.

    (define (page-request (method String) (url String) (headers (List Header)) (body String))
      (→ (Result Reply String))
      (! tasks)
      (host-request-method (string->utf8 method))
      (host-request-url (string->utf8 url))
      (for-each (lambda (header)
                  (host-request-header (string->utf8 (string-append (● header name)
                                                                    (make-string 1 #\null)
                                                                    (● header value)))))
                headers)
      (host-request-body (string->utf8 body))
      (let ((status (through-host host-start-request host-finish-request)))
        (if (< status 0) (Err (host-reply)) (Ok (new Reply (status status) (body (host-reply)))))))

    ;; A stream opens with its URL and the kinds it hears as one string, a
    ;; NUL between each. The wait answers -1 once the stream is closed, and
    ;; otherwise leaves the next event's kind and data, a NUL between them.

    (define (page-stream-next (stream Stream)) (→ (Option StreamEvent)) (! tasks)
      (let ((count (through-host (lambda (ticket) (host-stream-start ticket (● stream id)))
                                 host-stream-finish)))
        (if (< count 0) (None) (Some (stream-event (host-reply))))))

    (define (stream-event (text String)) (→ StreamEvent)
      (match (string-index text #\null)
        ((Some end)
         (new StreamEvent
           (kind (substring text 0 end))
           (data (substring text (+ end 1) (string-length text)))))
        ((None) (panic "internal error: a stream's event has no kind"))))

    ;; ---- The browser host ----

    ;; The text the last finished wait left.

    (define (host-reply) (→ String)
      (string-generate (i32->i64 (host-reply-count))
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))))
