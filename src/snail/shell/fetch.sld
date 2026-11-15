;; Requests to a server and the streams of events it sends, as an effect,
;; so an interface's commands can ask and a test can answer for the
;; server. The browser host binds it to the page's `Fetch` and
;; `EventSource` ((snail shell fetch page)).
(define-library (snail shell fetch)
  (export
   Header
   Reply
   Stream
   Stream-event
   Fetch
   request
   stream-open
   stream-next
   stream-close)
  (import
   (snail core base)
   (only (snail shell task) Tasks))
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
    (record Stream-event
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
    ;; handles the event.
    (effect Fetch
      ((request (Fn String String (List Header) String → (Result Reply String) ! Tasks))
       (stream-open (Fn String (List String) → Stream))
       (stream-next (Fn Stream → (Option Stream-event) ! Tasks))
       (stream-close (Fn Stream → Unit))))))
