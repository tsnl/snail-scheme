(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell socket)
 (snail shell http)
 (snail shell http exchange))

;; A mismatch here is a broken test-host invariant. Guest conversions that
;; are expected to fail use dyn-tc handlers in the dedicated fixtures.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (try-convert value target)
       ((Ok checked) checked)
       ((Err _) (panic "fixture payload has the wrong type"))))))


(: assert (-> Bool Unit))
(define (assert condition) (unless condition (panic "HTTP exchange assertion failed")))

(: ascii (-> String Bytes))
(define (ascii text)
  (vector-generate (string-length text)
                   (lambda (index) (i32->u8 (char->i32 (string-ref text index))))))

(: text (-> Bytes String))
(define (text bytes)
  (string-generate (vector-length bytes)
                   (lambda (index) (i32->char (u8->i32 (vector-ref bytes index))))))

(struct Stream
  ((input Bytes)
   (cursor (Ref I64))
   (output (Ref (List Bytes)))
   (offered (Ref I64))
   (ended (Ref I32))
   (read-size I64)
   (write-size I64)
   (fault String)))

(: stream (-> Bytes I64 I64 String Stream))
(define (stream input read-size write-size fault)
  (Stream input (ref 0) (ref (ann (Nil) (List Bytes))) (ref 0) (ref 0) read-size write-size fault))

(: token (-> Connection Stream))
(define (token connection) (fixture-convert (Connection-token connection) Stream))

(: read-stream (-> Connection I32 (Result (Option Bytes) SocketError) ! mut))
(define (read-stream connection maximum)
  (let* ((state (token connection)) (start (ref-get (Stream-cursor state)))
         (end (min (vector-length (Stream-input state))
                   (+ start (min (i32->i64 maximum) (Stream-read-size state))))))
    (cond ((string=? (Stream-fault state) "read") (Err (SocketError "TEST_READ")))
          ((string=? (Stream-fault state) "oversize-read")
           (Ok (Some (make-vector (+ (i32->i64 maximum) 1) (i32->u8 0)))))
          ((= start (vector-length (Stream-input state))) (Ok (None)))
          (else (ref-set! (Stream-cursor state) end)
                (Ok (Some (subvector (Stream-input state) start end)))))))

(: write-stream (-> Connection Bytes (Result I32 SocketError) ! mut))
(define (write-stream connection bytes)
  (let* ((state (token connection)) (count (min (vector-length bytes) (Stream-write-size state))))
    (cond ((string=? (Stream-fault state) "write") (Err (SocketError "TEST_WRITE")))
          ((string=? (Stream-fault state) "oversize-write")
           (Ok (i64->i32 (+ (vector-length bytes) 1))))
          ((string=? (Stream-fault state) "negative-write") (Ok -1))
          (else
           (ref-set! (Stream-offered state)
                     (+ (ref-get (Stream-offered state)) (vector-length bytes)))
           (ref-set! (Stream-output state)
                     (Cons (subvector bytes 0 count) (ref-get (Stream-output state))))
           (Ok (i64->i32 count))))))

(: finish-stream (-> Connection I32 (Result Unit SocketError) ! mut))
(define (finish-stream connection grace)
  (let ((state (token connection)))
    (assert (= grace 250))
    (if (string=? (Stream-fault state) "finish")
        (Err (SocketError "TEST_FINISH"))
        (begin (ref-set! (Stream-ended state) 1) (Ok (unit))))))

(: close-stream (-> Connection (Result Unit SocketError) ! mut))
(define (close-stream connection)
  (ref-set! (Stream-ended (token connection)) 2)
  (Err (SocketError "TEST_CLOSE")))

(: run (All (e) (-> Stream (-> Request (Result Response String) ! e)
                    (Result Unit (ExchangeError String)) ! tcp tasks e)))
(define (run state handler)
  (serve-one (Connection (type-convert state Any)) 250 handler))

(: echo (-> Request (Result Response String) ! tasks))
(define (echo request)
  (sleep 1)
  (Ok (Response 200 (Nil) (Request-body request))))

(: output (-> Stream String ! mut))
(define (output state) (text (vector-concatenate (reverse (ref-get (Stream-output state))))))

(: success? (-> (Result Unit (ExchangeError String)) Bool))
(define (success? result) (match result ((Ok _) #t) ((Err _) #f)))

(: request Bytes)
(define request
  (ascii "POST /echo HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nbodyignored pipeline"))

;; A program waits on sockets from a task, which the scheduler runs once
;; main returns.
(dispatch-local
 (once (lambda ()
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
             (when (<= size (vector-length request))
               (let ((state (stream request size 3 "")))
                 (assert (success? (run state echo)))
                 (assert (= (ref-get (Stream-ended state)) 1))
                 (assert (string=? (output state)
                                   "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 4\r\n\r\nbody")))
               (loop (+ size 1))))
           (write-line "fragmented request and partial response")
           ;; serve-one's halves, with a decision between them: the request is read
           ;; before the server chooses how to answer it.
           (let* ((state (stream request 7 5 ""))
                  (connection (Connection (type-convert state Any))))
             (match (ann (read-request connection) (Result Request (ExchangeError String)))
               ((Err _) (panic "read-request failed"))
               ((Ok received)
                (assert (string=? (RequestHead-target (Request-head received)) "/echo"))
                (assert (= (ref-get (Stream-ended state)) 0))
                (assert (success? (respond connection
                                           250
                                           (Some (RequestHead-method (Request-head received)))
                                           (Response 201
                                                     (list (Header "X-Body" "4"))
                                                     (Request-body received)))))
                (assert (= (ref-get (Stream-ended state)) 1))
                (assert (string=? (output state)
                                  "HTTP/1.1 201 \r\nConnection: close\r\nContent-Length: 4\r\nx-body: 4\r\n\r\nbody")))))
           ;; A failure from either half leaves the connection to the caller.
           (let ((state (stream (ascii "GET / HTTP/1.1\r\n") 100 100 "")))
             (assert (match (ann (read-request (Connection (type-convert state Any)))
                                 (Result Request (ExchangeError String)))
                       ((Err (TruncatedHead)) #t)
                       (_ #f)))
             (assert (= (ref-get (Stream-ended state)) 0)))
           (let* ((state (stream request 100 100 ""))
                  (connection (Connection (type-convert state Any))))
             (match (ann (read-request connection) (Result Request (ExchangeError String)))
               ((Err _) (panic "read-request failed"))
               ((Ok received)
                (assert (match (ann (respond connection
                                             250
                                             (Some (RequestHead-method (Request-head received)))
                                             (Response 99 (Nil) #u8()))
                                    (Result Unit (ExchangeError String)))
                          ((Err (ProtocolFailure _)) #t)
                          (_ #f)))
                (assert (= (ref-get (Stream-ended state)) 0))
                (assert (string=? (output state) "")))))
           ;; A request that could not be read can still be answered.
           (let* ((state (stream (ascii "GET / HTTP/1.1\r\nHost: test\r\r\n\r\n") 100 100 ""))
                  (connection (Connection (type-convert state Any))))
             (assert (match (ann (read-request connection) (Result Request (ExchangeError String)))
                       ((Err (ProtocolFailure _)) #t)
                       (_ #f)))
             (assert (success? (respond connection 250 (None) (Response 400 (Nil) (ascii "bad")))))
             (assert (string=? (output state)
                               "HTTP/1.1 400 \r\nConnection: close\r\nContent-Length: 3\r\n\r\nbad")))
           (write-line "read-request and respond")
           (let ((state (stream (ascii "HEAD / HTTP/1.1\r\nHost: test\r\n\r\n") 100 100 "")))
             (assert (success? (run state (lambda (_) (Ok (Response 200 (Nil) #u8(1 2 3)))))))
             (assert
              (string=? (output state)
                        "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n")))
           (write-line "HEAD suppression")
           (let* ((prefix "GET / HTTP/1.1\r\nHost: test\r\nX-Pad: ")
                  (head (ascii (string-append prefix
                                              (make-string
                                               (- (- head-limit (string-length prefix)) 4)
                                               #\x)
                                              "\r\n\r\n")))
                  (state (stream head 1 65536 "")))
             (assert (success? (run state echo)))
             (assert (= (ref-get (Stream-cursor state)) head-limit)))
           (for-each
            (lambda (input)
              (let ((state (stream input 1 65536 "")))
                (assert (match (run state echo) ((Err (ProtocolFailure _)) #t) (_ #f)))
                (assert (= (ref-get (Stream-ended state)) 2))
                (assert (string=? (output state) ""))))
            (list (ascii "GET / HTTP/1.1\r\nHost: test\r\r\n\r\n")
                  (make-vector head-limit (i32->u8 65))
                  (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 8388609\r\n\r\n")
                  (ascii "POST / HTTP/1.1\r\nHost: test\r\nTransfer-Encoding: chunked\r\n\r\n")))
           (write-line "bounded heads and declared bodies")
           (let* ((body (vector-generate 131073
                                         (lambda (index) (i32->u8 (i64->i32 (modulo index 251))))))
                  (head (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 131073\r\n\r\n"))
                  (state (stream (vector-append head body) 65536 113 "")))
             (assert (success? (run state echo)))
             (let ((bytes (vector-concatenate (reverse (ref-get (Stream-output state)))))
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
               (run state (lambda (_) (Ok (Response 200 (Nil) (make-vector 10000 (i32->u8 7))))))))
             (assert (<= (ref-get (Stream-offered state)) (+ 131072 (* 2 10100)))))
           (write-line "tiny writes keep copying linear")
           (let ((state (stream (ascii "GET / HTTP/1.1\r\n") 100 100 "")))
             (assert (match (run state echo) ((Err (TruncatedHead)) #t) (_ #f)))
             (assert (= (ref-get (Stream-ended state)) 2)))
           (let ((state
                  (stream (ascii "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nxy")
                          1
                          100
                          "")))
             (assert (match (run state echo)
                       ((Err (TruncatedBody expected received)) (and (= expected 4) (= received 2)))
                       (_ #f)))
             (assert (= (ref-get (Stream-ended state)) 2)))
           (write-line "truncated input closes")
           (let ((state (stream request 100 100 "")))
             (assert (match (run state (lambda (_) (Err "application")))
                       ((Err (ApplicationFailure error)) (string=? error "application"))
                       (_ #f)))
             (assert (= (ref-get (Stream-ended state)) 2))
             (assert (string=? (output state) "")))
           (let ((state (stream request 100 100 "")))
             (assert
              (match (run state
                          (lambda (_)
                            (Ok (Response 200 (list (Header "Content-Length" "5")) #u8()))))
                ((Err (ProtocolFailure _)) #t) (_ #f)))
             (assert (= (ref-get (Stream-ended state)) 2))
             (assert (string=? (output state) "")))
           (write-line "returned failures preserve primary error")
           (for-each
            (lambda (fault)
              (let ((state (stream request 100 100 fault)))
                (assert (match (run state echo) ((Err (TransportFailure _)) #t) (_ #f)))
                (assert (= (ref-get (Stream-ended state)) 2))))
            (list "read" "write" "finish" "oversize-read" "oversize-write" "negative-write"))
           (for-each
            (lambda (sizes)
              (let ((state (stream request (Pair-first sizes) (Pair-second sizes) "")))
                (assert (match (run state echo)
                          ((Err (TransportFailure error)) (string=? (SocketError-code error) "EIO"))
                          (_ #f)))
                (assert (= (ref-get (Stream-ended state)) 2))))
            (list (Pair 0 100) (Pair 100 0)))
           (write-line "transport failures and no progress close")))))
