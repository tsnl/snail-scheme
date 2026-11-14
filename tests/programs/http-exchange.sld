(import
 (snail core base)
 (only (snail core forms) host)
 (except (snail core io) write)
 (snail shell task)
 (snail shell socket)
 (snail shell http)
 (snail shell http exchange))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

(define (assert (condition Bool))
  (→ Unit)
  (unless condition (panic "HTTP exchange assertion failed")))

(define (ascii (text String)) (→ Bytes)
  (vector-generate (string-length text)
                   (lambda (index) (i32->u8 (char->i32 (string-ref text index))))))

(define (text (bytes Bytes)) (→ String)
  (string-generate (vector-length bytes)
                   (lambda (index) (i32->char (u8->i32 (vector-ref bytes index))))))

(record Stream
  ((input Bytes)
   (cursor I64)
   (output (List Bytes))
   (offered I64)
   (ended I32)
   (read-size I64)
   (write-size I64)
   (fault String)))

(define (stream (input Bytes) (read-size I64) (write-size I64) (fault String)) (→ Stream)
  (new Stream
    (input input)
    (cursor 0)
    (output (Nil))
    (offered 0)
    (ended 0)
    (read-size read-size)
    (write-size write-size)
    (fault fault)))

(define (token (connection Connection)) (→ Stream) (fixture-convert (● connection token) Stream))

(define (read-stream (connection Connection) (maximum I32))
  (→ (Result (Option Bytes) SocketError))
  (! mut)
  (let* ((state (token connection)) (start (● state cursor))
         (end (min (vector-length (● state input))
                   (+ start (min (i32->i64 maximum) (● state read-size))))))
    (cond ((string=? (● state fault) "read") (Err (new SocketError (code "TEST_READ"))))
          ((string=? (● state fault) "oversize-read")
           (Ok (Some (make-vector (+ (i32->i64 maximum) 1) (i32->u8 0)))))
          ((= start (vector-length (● state input))) (Ok (None)))
          (else (set! (● state cursor) end)
                (Ok (Some (subvector (● state input) start end)))))))

(define (write-stream (connection Connection) (bytes Bytes)) (→ (Result I32 SocketError)) (! mut)
  (let* ((state (token connection)) (count (min (vector-length bytes) (● state write-size))))
    (cond ((string=? (● state fault) "write") (Err (new SocketError (code "TEST_WRITE"))))
          ((string=? (● state fault) "oversize-write")
           (Ok (i64->i32 (+ (vector-length bytes) 1))))
          ((string=? (● state fault) "negative-write") (Ok -1))
          (else
           (set! (● state offered)
                 (+ (● state offered) (vector-length bytes)))
           (set! (● state output)
                 (Cons (subvector bytes 0 count) (● state output)))
           (Ok (i64->i32 count))))))

(define (finish-stream (connection Connection) (grace I32)) (→ (Result Unit SocketError)) (! mut)
  (let ((state (token connection)))
    (assert (= grace 250))
    (if (string=? (● state fault) "finish")
        (Err (new SocketError (code "TEST_FINISH")))
        (begin (set! (● state ended) 1) (Ok (unit))))))

(define (close-stream (connection Connection)) (→ (Result Unit SocketError)) (! mut)
  (set! (● (token connection) ended) 2)
  (Err (new SocketError (code "TEST_CLOSE"))))

(define (run (state Stream) (handler (Fn Request → (Result Response String) ! e)))
  (→ (Result Unit (ExchangeError String)))
  (! tcp tasks e)
  (∀ (e))
  (serve-one (new Connection (token (Any state))) 250 handler))

(define (echo (request Request)) (→ (Result Response String)) (! tasks)
  (sleep 1)
  (Ok (new Response (status 200) (headers (Nil)) (body (● request body)))))

(define (output (state Stream))
  (→ String)
  (text (vector-concatenate (reverse (● state output)))))

(define (success? (result (Result Unit (ExchangeError String))))
  (→ Bool)
  (match result ((Ok _) #t) ((Err _) #f)))

(define (request) (→ Bytes)
  (ascii "POST /echo HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nbodyignored pipeline"))

(define (main) (→ Unit) (! host mut output-port tasks)

  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  (dispatch
   (lambda ()
     (handle tcp
         ((listen (lambda (_) (panic "unexpected listen")))
          (connect (lambda (_) (panic "unexpected connect")))
          (accept (lambda (_) (panic "unexpected accept")))
          (read read-stream)
          (write write-stream)
          (finish-connection finish-stream)
          (close-listener (lambda (_) (panic "unexpected listener close")))
          (close-connection close-stream))
       ;; Every read size splits the delimiter/body differently. Writes accept
       ;; short prefixes; all app state lives in this handler's opaque token.
       (let loop ((size 1))
         (when (<= size (vector-length (request)))
           (let ((state (stream (request) size 3 "")))
             (assert (success? (run state echo)))
             (assert (= (● state ended) 1))
             (assert (string=? (output state)
                               "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 4\r\n\r\nbody")))
           (loop (+ size 1))))
       (write-line "fragmented request and partial response")
       ;; serve-one's halves, with a decision between them: the request is read
       ;; before the server chooses how to answer it.
       (let* ((state (stream (request) 7 5 ""))
              (connection (new Connection (token (Any state)))))
         (match (ann (read-request connection) (Result Request (ExchangeError String)))
           ((Err _) (panic "read-request failed"))
           ((Ok received)
            (assert (string=? (● (● received head) target) "/echo"))
            (assert (= (● state ended) 0))
            (assert (success? (respond connection
                                       250
                                       (Some (● (● received head) method))
                                       (new Response (status 201)
                                            (headers
                                             (list (new Header (name "X-Body") (value "4"))))
                                            (body (● received body))))))
            (assert (= (● state ended) 1))
            (assert (string=? (output state)
                              "HTTP/1.1 201 \r\nConnection: close\r\nContent-Length: 4\r\nx-body: 4\r\n\r\nbody")))))
       ;; A failure from either half leaves the connection to the caller.
       (let ((state (stream (ascii "GET / HTTP/1.1\r\n") 100 100 "")))
         (assert (match (ann (read-request (new Connection (token (Any state))))
                             (Result Request (ExchangeError String)))
                   ((Err (TruncatedHead)) #t)
                   (_ #f)))
         (assert (= (● state ended) 0)))
       (let* ((state (stream (request) 100 100 ""))
              (connection (new Connection (token (Any state)))))
         (match (ann (read-request connection) (Result Request (ExchangeError String)))
           ((Err _) (panic "read-request failed"))
           ((Ok received)
            (assert (match (ann (respond connection
                                         250
                                         (Some (● (● received head) method))
                                         (new Response
                                           (status 99)
                                           (headers (Nil))
                                           (body #u8())))
                                (Result Unit (ExchangeError String)))
                      ((Err (ProtocolFailure _)) #t)
                      (_ #f)))
            (assert (= (● state ended) 0))
            (assert (string=? (output state) "")))))
       ;; A request that could not be read can still be answered.
       (let* ((state (stream (ascii "GET / HTTP/1.1\r\nHost: test\r\r\n\r\n") 100 100 ""))
              (connection (new Connection (token (Any state)))))
         (assert
          (match (ann (read-request connection) (Result Request (ExchangeError String)))
            ((Err (ProtocolFailure _)) #t)
            (_ #f)))
         (assert
          (success? (respond connection
                             250
                             (None)
                             (new Response
                               (status 400)
                               (headers (Nil))
                               (body (ascii "bad"))))))
         (assert (string=? (output state)
                           "HTTP/1.1 400 \r\nConnection: close\r\nContent-Length: 3\r\n\r\nbad")))
       (write-line "read-request and respond")
       (let ((state (stream (ascii "HEAD / HTTP/1.1\r\nHost: test\r\n\r\n") 100 100 "")))
         (assert (success? (run state
                                (lambda (_)
                                  (Ok (new Response
                                        (status 200)
                                        (headers (Nil))
                                        (body #u8(1 2 3))))))))
         (assert
          (string=? (output state)
                    "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n")))
       (write-line "HEAD suppression")
       (let* ((prefix "GET / HTTP/1.1\r\nHost: test\r\nX-Pad: ")
              (head (ascii (string-append prefix
                                          (make-string
                                           (- (- (head-limit) (string-length prefix)) 4)
                                           #\x)
                                          "\r\n\r\n")))
              (state (stream head 1 65536 "")))
         (assert (success? (run state echo)))
         (assert (= (● state cursor) (head-limit))))
       (for-each
        (lambda (input)
          (let ((state (stream input 1 65536 "")))
            (assert (match (run state echo) ((Err (ProtocolFailure _)) #t) (_ #f)))
            (assert (= (● state ended) 2))
            (assert (string=? (output state) ""))))
        (list (ascii "GET / HTTP/1.1\r\nHost: test\r\r\n\r\n")
              (make-vector (head-limit) (i32->u8 65))
              (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 8388609\r\n\r\n")
              (ascii
               "POST / HTTP/1.1\r\nHost: test\r\nTransfer-Encoding: chunked\r\n\r\n")))
       (write-line "bounded heads and declared bodies")
       (let* ((body (vector-generate 131073
                                     (lambda (index)
                                       (i32->u8 (i64->i32 (modulo index 251))))))
              (head
               (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 131073\r\n\r\n"))
              (state (stream (vector-append head body) 65536 113 "")))
         (assert (success? (run state echo)))
         (let ((bytes (vector-concatenate (reverse (● state output))))
               (offset
                (string-length
                 "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 131073\r\n\r\n")))
           (assert (= (vector-length bytes) (+ 131073 offset)))
           (let loop ((index 0))
             (when (< index 131073)
               (assert (= (vector-ref bytes (+ offset index)) (vector-ref body index)))
               (loop (+ index 1))))))
       (write-line "binary body across transfer bounds")
       (let ((state (stream (ascii "GET / HTTP/1.1\r\nHost: test\r\n\r\n") 100 1 "")))
         (assert
          (success?
           (run state
                (lambda (_)
                  (Ok (new Response
                        (status 200)
                        (headers (Nil))
                        (body (make-vector 10000 (i32->u8 7)))))))))
         (assert (<= (● state offered) (+ 131072 (* 2 10100)))))
       (write-line "tiny writes keep copying linear")
       (let ((state (stream (ascii "GET / HTTP/1.1\r\n") 100 100 "")))
         (assert (match (run state echo) ((Err (TruncatedHead)) #t) (_ #f)))
         (assert (= (● state ended) 2)))
       (let ((state
              (stream (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nxy")
                      1
                      100
                      "")))
         (assert (match (run state echo)
                   ((Err (TruncatedBody expected received))
                    (and (= expected 4) (= received 2)))
                   (_ #f)))
         (assert (= (● state ended) 2)))
       (write-line "truncated input closes")
       (let ((state (stream (request) 100 100 "")))
         (assert (match (run state (lambda (_) (Err "application")))
                   ((Err (ApplicationFailure error)) (string=? error "application"))
                   (_ #f)))
         (assert (= (● state ended) 2))
         (assert (string=? (output state) "")))
       (let ((state (stream (request) 100 100 "")))
         (assert
          (match (run state
                      (lambda (_)
                        (Ok (new Response
                              (status 200)
                              (headers
                               (list (new Header (name "Content-Length") (value "5"))))
                              (body #u8())))))
            ((Err (ProtocolFailure _)) #t) (_ #f)))
         (assert (= (● state ended) 2))
         (assert (string=? (output state) "")))
       (write-line "returned failures preserve primary error")
       (for-each
        (lambda (fault)
          (let ((state (stream (request) 100 100 fault)))
            (assert (match (run state echo) ((Err (TransportFailure _)) #t) (_ #f)))
            (assert (= (● state ended) 2))))
        (list "read" "write" "finish" "oversize-read" "oversize-write" "negative-write"))
       (for-each
        (lambda (sizes)
          (let ((state (stream (request) (● sizes first) (● sizes second) "")))
            (assert (match (run state echo)
                      ((Err (TransportFailure error)) (string=? (● error code) "EIO"))
                      (_ #f)))
            (assert (= (● state ended) 2))))
        (list (new Pair (first 0) (second 100)) (new Pair (first 100) (second 0))))
       (write-line "transport failures and no progress close"))))
  (unit))
