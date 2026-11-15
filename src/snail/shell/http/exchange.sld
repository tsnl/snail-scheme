;; One complete request/response exchange over the concrete TCP effect.
;; `serve-one` is the whole exchange with one handler. A server that decides
;; between reading and answering calls its halves, `read-request` and
;; `respond`, itself; a failure either returns leaves the connection open,
;; and the caller closes it, as `serve-one` does. `respond` needs only the
;; request's method, so a server can answer a request it could not read.
(define-library (snail shell http exchange)
  (export
   Request
   Response
   ExchangeError ProtocolFailure TransportFailure TruncatedHead TruncatedBody ApplicationFailure
   read-request respond serve-one)
  (import
   (snail core base)
   (snail shell http)
   (snail shell socket)
   (only (snail shell task) tasks))
  (begin

    ;; ---- Exchange values ----

    (record Request
      ((head RequestHead)
       (body Bytes)))

    (record Response
      ((status I32)
       (headers (List Header))
       (body Bytes)))

    (enum (ExchangeError E)
      (ProtocolFailure ((error HttpError)))
      (TransportFailure ((error SocketError)))
      (TruncatedHead)
      (TruncatedBody
       ((expected I64)
        (received I64)))
      (ApplicationFailure ((error E))))

    ;; The codec has established framing; prefix contains only bytes after
    ;; the head. They can include the body and surplus pipelined input.
    (record RequestPrefix
      ((head RequestHead)
       (prefix Bytes)))

    ;; ---- Bounded request input ----

    ;; A successful chunk is nonempty and fits the requested bound. EOF stays
    ;; separate so the head and body readers report their own truncation facts.

    (define (read-chunk (connection Connection) (maximum I64))
      (→ (Result (Option Bytes) (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (match (read connection (i64->i32 maximum))
        ((Err error) (Err (TransportFailure error)))
        ((Ok (None)) (Ok (None)))
        ((Ok (Some bytes))
         (if (and (> (vector-length bytes) 0) (<= (vector-length bytes) maximum))
             (Ok (Some bytes))
             (Err (TransportFailure (new SocketError (code "EIO"))))))))

    ;; Only locate CRLFCRLF here. The codec owns all HTTP syntax validation.
    ;; State is the number of matching delimiter bytes, from zero through four.

    (define (delimiter-step (state I32) (byte U8)) (→ I32)
      (let ((code (u8->i32 byte)))
        (cond ((= code 13) (if (= state 2) 3 1))
              ((= code 10) (cond ((= state 1) 2) ((= state 3) 4) (else 0)))
              (else 0))))

    (define (scan-head (bytes Bytes) (state I32)) (→ (Pair I64 I32))
      (let loop ((index 0) (state state))
        (if (or (= state 4) (= index (vector-length bytes)))
            (new Pair (first index) (second state))
            (loop (+ index 1) (delimiter-step state (vector-ref bytes index))))))

    (define (parsed-prefix (reversed (List Bytes)) (prefix Bytes))
      (→ (Result RequestPrefix (ExchangeError E)))
      (∀ (E))
      (match (parse-request-head (vector-concatenate (reverse reversed)))
        ((Err error) (Err (ProtocolFailure error)))
        ((Ok value)
         (match value
           ((Some parsed) (Ok (new RequestPrefix (head (● parsed request)) (prefix prefix))))
           ((None) (panic "HTTP delimiter did not complete the head"))))))

    (define (read-head (connection Connection))
      (→ (Result RequestPrefix (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (let loop ((chunks (ann (Nil) (List Bytes))) (total 0) (state (ann 0 I32)))
        (if (= total (head-limit))
            (Err (ProtocolFailure (HeadTooLarge)))
            (match (read-chunk connection (- (head-limit) total))
              ((Err error) (Err error))
              ((Ok (None)) (Err (TruncatedHead)))
              ((Ok (Some bytes))
               (let* ((count (vector-length bytes))
                      (scanned (scan-head bytes state))
                      (end (● scanned first)))
                 (if (= (● scanned second) 4)
                     (parsed-prefix (Cons (subvector bytes 0 end) chunks)
                                    (subvector bytes end count))
                     (loop (Cons bytes chunks) (+ total count) (● scanned second)))))))))

    (define (read-body (connection Connection) (prefix RequestPrefix))
      (→ (Result Request (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (let* ((head (● prefix head)) (expected (● head body-length))
             (initial (● prefix prefix)) (count (min expected (vector-length initial))))
        (let loop ((chunks (list (subvector initial 0 count))) (received count))
          (if (= received expected)
              (Ok (new Request (head head) (body (vector-concatenate (reverse chunks)))))
              (match (read-chunk connection (min 65536 (- expected received)))
                ((Err error) (Err error))
                ((Ok (None)) (Err (TruncatedBody expected received)))
                ((Ok (Some bytes))
                 (loop (Cons bytes chunks) (+ received (vector-length bytes)))))))))

    (define (read-request (connection Connection))
      (→ (Result Request (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (match (read-head connection)
        ((Err error) (Err error))
        ((Ok prefix) (read-body connection prefix))))

    ;; ---- Complete response output ----

    (define (write-bytes (connection Connection) (bytes Bytes))
      (→ (Result Unit (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      ;; Slice sizes follow actual progress: at most 65536 + twice the sent
      ;; bytes are copied, even when a replacement handler accepts tiny writes.
      (let loop ((offset 0) (limit 65536))
        (if (= offset (vector-length bytes))
            (Ok (unit))
            (let ((end (min (vector-length bytes) (+ offset limit))))
              (match (write connection (subvector bytes offset end))
                ((Err error) (Err (TransportFailure error)))
                ((Ok written)
                 (let ((count (i32->i64 written)))
                   (if (or (<= count 0) (> count (- end offset)))
                       (Err (TransportFailure (new SocketError (code "EIO"))))
                       (loop (+ offset count) (min 65536 (* 2 count)))))))))))

    (define (write-response (connection Connection) (grace I32) (parts ResponseParts))
      (→ (Result Unit (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (match (write-bytes connection (● parts head))
        ((Err error) (Err error))
        ((Ok _)
         (match (write-bytes connection (● parts body))
           ((Err error) (Err error))
           ((Ok _)
            (match (finish-connection connection grace)
              ((Err error) (Err (TransportFailure error)))
              ((Ok _) (Ok (unit)))))))))

    ;; Nothing is written unless the whole response encodes. After the
    ;; head and body, the connection finishes within `grace` milliseconds.
    ;; `method` is the request's, or None for a request that could not be
    ;; read, which is answered as a GET is: only HEAD and CONNECT change
    ;; how a response is framed.

    (define (respond (connection Connection)
                     (grace I32)
                     (method (Option String))
                     (response Response))
      (→ (Result Unit (ExchangeError E)))
      (! tcp tasks)
      (∀ (E))
      (match (encode-response (match method ((Some name) name) ((None) "GET"))
                              (● response status)
                              (● response headers)
                              (● response body))
        ((Err error) (Err (ProtocolFailure error)))
        ((Ok parts) (write-response connection grace parts))))

    (define (exchange (connection Connection)
                      (grace I32)
                      (handler (Fn Request → (Result Response E) ! e)))
      (→ (Result Unit (ExchangeError E)))
      (! tcp tasks e)
      (∀ (E e))
      (match (read-request connection)
        ((Err error) (Err error))
        ((Ok request)
         (match (handler request)
           ((Err error) (Err (ApplicationFailure error)))
           ((Ok response)
            (respond connection
                     grace
                     (Some (● (● request head) method))
                     response))))))

    ;; Exclusive use is a calling convention the checker does not enforce.
    ;; Returned failures close here. A trap in an unrelated handler effect
    ;; cannot unwind through this code; runtime shutdown closes the remaining
    ;; native resources. Aborting active native I/O closes its socket.

    (define (serve-one (connection Connection)
                       (grace I32)
                       (handler (Fn Request → (Result Response E) ! e)))
      (→ (Result Unit (ExchangeError E)))
      (! tcp tasks e)
      (∀ (E e))
      (let ((result (exchange connection grace handler)))
        (match result
          ((Err _) (close-connection connection) result)
          ((Ok _) result))))))
