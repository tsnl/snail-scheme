(import
 (snail core base)
 (except (snail core io) write)
 (snail shell task)
 (snail shell socket)
 (snail shell http)
 (snail shell http exchange))

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
  (match result ((Ok value) value) ((Err error) (panic (● error code)))))

(define (ascii (text String)) (→ Bytes)
  (array-generate (string-length text)
                  (lambda (index) (i32->u8 (char->i32 (string-ref text index))))))

(define (text (bytes Bytes)) (→ String)
  (string-generate (array-length bytes)
                   (lambda (index) (i32->char (u8->i32 (array-ref bytes index))))))

(define (write-all (tcp Tcp) (connection Connection) (bytes Bytes)) (→ Unit)
  (let loop ((offset 0))
    (when (< offset (array-length bytes))
      (let ((count (require (tcp::write connection (subarray bytes offset (array-length bytes))))))
        (unless (> count 0) (panic "write did not progress"))
        (loop (+ offset (i32->i64 count)))))))

(define (read-all (tcp Tcp) (connection Connection)) (→ Bytes)
  (let loop ((chunks (ann (Nil) (List Bytes))))
    (match (require (tcp::read connection 65536))
      ((None) (array-concatenate (reverse chunks)))
      ((Some bytes) (loop (Cons bytes chunks))))))

(define (echo (request Request)) (→ (Result Response String))
  (sleep 1)
  (Ok (new Response
        (status 200)
        (headers (list (new Header (name "Content-Type") (value "text/plain"))))
        (body (● request body)))))

(define (main (tcp Tcp) (out OutputPort)) (→ Unit)
  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  (dispatch
   (lambda ()
     (let* ((listener (require (tcp::listen (require (endpoint "127.0.0.1" 0)))))
            (client
             (require (tcp::connect (require (endpoint "127.0.0.1" (● listener port))))))
            (server (require (tcp::accept listener))))
       (require (tcp::close-listener listener))
       (dispatch
        (lambda ()
          (match (serve-one tcp server 2000 echo)
            ((Ok _) (unit))
            ((Err _) (panic "HTTP server exchange failed")))))
       (write-all tcp client
                  (ascii
                   "POST /echo HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\nbody"))
       (write-all tcp client (make-array 131073 (i32->u8 88)))
       (let ((response (read-all tcp client)))
         (require (tcp::finish-connection client 2000))
         (unless (string=? (text response)
                           "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 4\r\ncontent-type: text/plain\r\n\r\nbody")
           (panic "incomplete HTTP response")))
       (write-line out
                   "HTTP exchange: real sockets, suspended handler, unread input and graceful finish"))))
  (unit))
