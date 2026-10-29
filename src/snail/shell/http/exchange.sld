;; One complete request/response exchange over the concrete TCP effect.
;; `serve-one` is the whole exchange with one handler. A server that decides
;; between reading and answering calls its halves, `read-request` and
;; `respond`, itself; a failure either returns leaves the connection open,
;; and the caller closes it, as `serve-one` does.
(define-library (snail shell http exchange)
  (export
   Request Request-head Request-body
   Response Response-status Response-headers Response-body
   ExchangeError ProtocolFailure TransportFailure TruncatedHead TruncatedBody ApplicationFailure
   read-request respond serve-one)
  (import
   (snail core base)
   (snail shell http)
   (snail shell socket)
   (only (snail shell task) tasks))
  (begin

    ;; ---- Exchange values ----

    (struct Request
      ((head RequestHead)
       (body Bytes)))

    (struct Response
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
    (struct RequestPrefix
      ((head RequestHead)
       (prefix Bytes)))

    ;; ---- Bounded request input ----

    ;; A successful chunk is nonempty and fits the requested bound. EOF stays
    ;; separate so the head and body readers report their own truncation facts.
    (: read-chunk
       (All (E) (-> Connection I64 (Result (Option Bytes) (ExchangeError E)) ! tcp tasks)))
    (define (read-chunk connection maximum)
      (match (read connection (i64->i32 maximum))
        ((Err error) (Err (TransportFailure error)))
        ((Ok (None)) (Ok (None)))
        ((Ok (Some bytes))
         (if (and (> (vector-length bytes) 0) (<= (vector-length bytes) maximum))
             (Ok (Some bytes))
             (Err (TransportFailure (SocketError "EIO")))))))

    ;; Only locate CRLFCRLF here. The codec owns all HTTP syntax validation.
    ;; State is the number of matching delimiter bytes, from zero through four.
    (: delimiter-step (-> I32 U8 I32))
    (define (delimiter-step state byte)
      (let ((code (u8->i32 byte)))
        (cond ((= code 13) (if (= state 2) 3 1))
              ((= code 10) (cond ((= state 1) 2) ((= state 3) 4) (else 0)))
              (else 0))))

    (: scan-head (-> Bytes I32 (Pair I64 I32)))
    (define (scan-head bytes state)
      (let loop ((index 0) (state state))
        (if (or (= state 4) (= index (vector-length bytes)))
            (Pair index state)
            (loop (+ index 1) (delimiter-step state (vector-ref bytes index))))))

    (: parsed-prefix (All (E) (-> (List Bytes) Bytes (Result RequestPrefix (ExchangeError E)))))
    (define (parsed-prefix reversed prefix)
      (match (parse-request-head (vector-concatenate (reverse reversed)))
        ((Err error) (Err (ProtocolFailure error)))
        ((Ok value)
         (match value
           ((Some parsed) (Ok (RequestPrefix (ParsedHead-request parsed) prefix)))
           ((None) (panic "HTTP delimiter did not complete the head"))))))

    (: read-head (All (E) (-> Connection (Result RequestPrefix (ExchangeError E)) ! tcp tasks)))
    (define (read-head connection)
      (let loop ((chunks (ann (Nil) (List Bytes))) (total 0) (state (ann 0 I32)))
        (if (= total head-limit)
            (Err (ProtocolFailure (HeadTooLarge)))
            (match (read-chunk connection (- head-limit total))
              ((Err error) (Err error))
              ((Ok (None)) (Err (TruncatedHead)))
              ((Ok (Some bytes))
               (let* ((count (vector-length bytes))
                      (scanned (scan-head bytes state))
                      (end (Pair-first scanned)))
                 (if (= (Pair-second scanned) 4)
                     (parsed-prefix (Cons (subvector bytes 0 end) chunks)
                                    (subvector bytes end count))
                     (loop (Cons bytes chunks) (+ total count) (Pair-second scanned)))))))))

    (: read-body
       (All (E) (-> Connection RequestPrefix (Result Request (ExchangeError E)) ! tcp tasks)))
    (define (read-body connection prefix)
      (let* ((head (RequestPrefix-head prefix)) (expected (RequestHead-body-length head))
             (initial (RequestPrefix-prefix prefix)) (count (min expected (vector-length initial))))
        (let loop ((chunks (list (subvector initial 0 count))) (received count))
          (if (= received expected)
              (Ok (Request head (vector-concatenate (reverse chunks))))
              (match (read-chunk connection (min 65536 (- expected received)))
                ((Err error) (Err error))
                ((Ok (None)) (Err (TruncatedBody expected received)))
                ((Ok (Some bytes))
                 (loop (Cons bytes chunks) (+ received (vector-length bytes)))))))))

    (: read-request (All (E) (-> Connection (Result Request (ExchangeError E)) ! tcp tasks)))
    (define (read-request connection)
      (match (read-head connection)
        ((Err error) (Err error))
        ((Ok prefix) (read-body connection prefix))))

    ;; ---- Complete response output ----

    (: write-bytes (All (E) (-> Connection Bytes (Result Unit (ExchangeError E)) ! tcp tasks)))
    (define (write-bytes connection bytes)
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
                       (Err (TransportFailure (SocketError "EIO")))
                       (loop (+ offset count) (min 65536 (* 2 count)))))))))))

    (: write-response
       (All (E) (-> Connection I32 ResponseParts (Result Unit (ExchangeError E)) ! tcp tasks)))
    (define (write-response connection grace parts)
      (match (write-bytes connection (ResponseParts-head parts))
        ((Err error) (Err error))
        ((Ok _)
         (match (write-bytes connection (ResponseParts-body parts))
           ((Err error) (Err error))
           ((Ok _)
            (match (finish-connection connection grace)
              ((Err error) (Err (TransportFailure error)))
              ((Ok _) (Ok (unit)))))))))

    ;; Nothing is written unless the whole response encodes. After the
    ;; head and body, the connection finishes within `grace` milliseconds.
    (: respond
       (All (E) (-> Connection I32 Request Response (Result Unit (ExchangeError E)) ! tcp tasks)))
    (define (respond connection grace request response)
      (match (encode-response (RequestHead-method (Request-head request)) (Response-status response)
                              (Response-headers response) (Response-body response))
        ((Err error) (Err (ProtocolFailure error)))
        ((Ok parts) (write-response connection grace parts))))

    (: exchange (All (E e) (-> Connection I32 (-> Request (Result Response E) ! e)
                               (Result Unit (ExchangeError E)) ! tcp tasks e)))
    (define (exchange connection grace handler)
      (match (read-request connection)
        ((Err error) (Err error))
        ((Ok request)
         (match (handler request)
           ((Err error) (Err (ApplicationFailure error)))
           ((Ok response) (respond connection grace request response))))))

    ;; Exclusive use is a calling convention, not a linear socket guarantee.
    ;; Returned failures close here. Traps and cancellation in an unrelated
    ;; handler effect cannot unwind through this code; runtime shutdown owns
    ;; their remaining native resources. Active native I/O cancels its socket.
    (: serve-one
       (All (E e) (requires (Copy E)) (-> Connection I32 (-> Request (Result Response E) ! e)
                                          (Result Unit (ExchangeError E)) ! tcp tasks e)))
    (define (serve-one connection grace handler)
      (let ((result (exchange connection grace handler)))
        (match result
          ((Err _) (close-connection connection) result)
          ((Ok _) result))))))
