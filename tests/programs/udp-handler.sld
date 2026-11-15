(import
 (snail core base)
 (only (snail core forms) host)
 (rename (snail core io) (write write-value))
 (snail shell task)
 (snail shell socket))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(record PendingPacket
  ((packet Datagram)))

(define (main) (→ Unit) (! host mut output-port tasks)

  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  (dispatch
   (lambda ()
     (handle udp
         ((bind (lambda (endpoint)
                  (Ok
                   (new UdpSocket
                     (token (Any (new PendingPacket
                                   (packet (new Datagram (peer endpoint) (bytes #u8()))))))
                     (port (Endpoint-port endpoint))))))
          (send (lambda (socket peer bytes)
                  (sleep 1)
                  (set! (● (fixture-convert (● socket token) PendingPacket) packet)
                        (new Datagram (peer peer) (bytes bytes)))
                  (Ok (i64->i32 (vector-length bytes)))))
          (receive (lambda (socket _)
                     (Ok (● (fixture-convert (● socket token) PendingPacket) packet))))
          (close-udp (lambda (_) (Ok (unit)))))
       (let ((socket (require (bind (require (endpoint "192.0.2.1" 7))))))
         (dispatch
          (lambda ()
            (require (send socket (require (endpoint "192.0.2.2" 8)) #u8(9 10)))
            (let ((packet (require (receive socket 2))))
              (write-line (Endpoint-address (● packet peer)))
              (write-value (vector->list (● packet bytes)))
              (newline))))))))
  (write-line "main returns")
  (unit))
