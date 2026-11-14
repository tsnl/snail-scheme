(import
 (only (snail core forms) host)
 (snail core base)
 (except (snail core io) write)
 (snail shell task)
 (snail shell socket)
 (snail shell http)
 (snail shell http exchange))

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
  (match result ((Ok value) value) ((Err error) (panic (● error code)))))

(define (ascii (text String)) (→ Bytes)
  (vector-generate (string-length text)
                   (lambda (index) (i32->u8 (char->i32 (string-ref text index))))))

(define (text (bytes Bytes)) (→ String)
  (string-generate (vector-length bytes)
                   (lambda (index) (i32->char (u8->i32 (vector-ref bytes index))))))

(define (write-all (connection Connection) (bytes Bytes)) (→ Unit) (! tcp tasks)
  (let loop ((offset 0))
    (when (< offset (vector-length bytes))
      (let ((count (require (write connection (subvector bytes offset (vector-length bytes))))))
        (unless (> count 0) (panic "write did not progress"))
        (loop (+ offset (i32->i64 count)))))))

(define (read-all (connection Connection)) (→ Bytes) (! tcp tasks)
  (let loop ((chunks (ann (Nil) (List Bytes))))
    (match (require (read connection 65536))
      ((None) (vector-concatenate (reverse chunks)))
      ((Some bytes) (loop (Cons bytes chunks))))))

(define (echo (request Request)) (→ (Result Response String)) (! tasks)
  (sleep 1)
  (Ok (new Response
        (status 200)
        (headers (list (new Header (name "Content-Type") (value "text/plain"))))
        (body (● request body)))))

(define (main) (→ Unit) (! host mut output-port tcp tasks)
  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  (dispatch-local
   (lambda ()
     (let* ((listener (require (listen (require (endpoint "127.0.0.1" 0)))))
            (client
             (require (connect (require (endpoint "127.0.0.1" (● listener port))))))
            (server (require (accept listener))))
       (require (close-listener listener))
       (dispatch-local
        (lambda ()
          (match (serve-one server 2000 echo)
            ((Ok _) (unit))
            ((Err _) (panic "HTTP server exchange failed")))))
       (write-all client
                  (ascii
                   "POST /echo HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nbody"))
       (write-all client (make-vector 131073 (i32->u8 88)))
       (let ((response (read-all client)))
         (require (finish-connection client 2000))
         (unless (string=? (text response)
                           "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 4\r\ncontent-type: text/plain\r\n\r\nbody")
           (panic "incomplete HTTP response")))
       (write-line
        "HTTP exchange: real sockets, suspended handler, unread input and graceful finish"))))
  (unit))
