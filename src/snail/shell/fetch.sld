;; Requests to a server and the streams of events it sends, as an effect,
;; so an interface's commands can ask and a test can answer for the
;; server. The browser host binds it to the page's `fetch` and
;; `EventSource` ((snail shell fetch page)).
(define-library (snail shell fetch)
  (export
   Header
   Reply
   Stream
   StreamEvent
   Fetch
   request
   fetch-bytes
   fetch-all-bytes
   page-address
   stream-open
   stream-next
   stream-close)
  (import
   (snail core base)
   (only (snail shell task) tasks))
  (begin

    ;; ---- Requests ----

    (record Header
      ((name String)
       (value String)))

    ;; A server's reply, whatever its status, and its body as text.
    (record Reply
      ((status I32)
       (body String)))

    ;; The events a server sends at one URL, as the host receives them.
    (record Stream
      ((id I32)))

    ;; An event a stream heard: its kind, the name the server gave it, or
    ;; "message" when it gave none, and its data.
    (record StreamEvent
      ((kind String)
       (data String)))

    ;; ---- The effect ----

    ;; `request method url headers body` answers the server's reply, or
    ;; why there was none, such as a failed connection. `stream-open url
    ;; kinds` hears the events of the kinds named, and buffers them from
    ;; when it is opened; `stream-next` waits for the next, and answers none
    ;; once the stream is closed, by `stream-close` or for good by the
    ;; server. A dropped connection is not the end: the host connects
    ;; again, as `EventSource` does, and a stream that names the kind
    ;; "error" hears one, with no data, each time. One
    ;; task at a time waits on a stream, so a program reading events keeps
    ;; one command waiting on it, and issues the next from the update that
    ;; handles the event. `fetch-all-bytes urls` answers the body of a GET
    ;; of each URL as bytes, such as a scene's buffers and images, or why
    ;; there was none, a status other than OK among the reasons; the
    ;; requests are made together, and the answers are in the URLs' order.
    ;; `page-address` is the URL
    ;; of the page the program runs in, which relative URLs resolve
    ;; against and whose query can choose what it shows.
    (record Fetch
      ((request (Fn String String (List Header) String → (Result Reply String) ! mut tasks))
       (fetch-all-bytes (Fn (List String) → (List (Result Bytes String)) ! mut tasks))
       (page-address (Fn → String ! mut))
       (stream-open (Fn String (List String) → Stream ! mut))
       (stream-next (Fn Stream → (Option StreamEvent) ! mut tasks))
       (stream-close (Fn Stream → Unit ! mut))))

    (define (request (fetch Fetch)
                     (method String)
                     (url String)
                     (headers (List Header))
                     (body String))
      (→ (Result Reply String))
      (! mut tasks)
      ((● fetch request) method url headers body))

    (define (fetch-all-bytes (fetch Fetch) (urls (List String)))
      (→ (List (Result Bytes String)))
      (! mut tasks)
      ((● fetch fetch-all-bytes) urls))

    (define (page-address (fetch Fetch)) (→ String) (! mut)
      ((● fetch page-address)))

    (define (stream-open (fetch Fetch) (url String) (kinds (List String))) (→ Stream) (! mut)
      ((● fetch stream-open) url kinds))

    (define (stream-next (fetch Fetch) (stream Stream)) (→ (Option StreamEvent)) (! mut tasks)
      ((● fetch stream-next) stream))

    (define (stream-close (fetch Fetch) (stream Stream)) (→ Unit) (! mut)
      ((● fetch stream-close) stream))

    (define (fetch-bytes (fetch Fetch) (url String)) (→ (Result Bytes String)) (! mut tasks)
      (list-ref (fetch-all-bytes fetch (list url)) 0))))
