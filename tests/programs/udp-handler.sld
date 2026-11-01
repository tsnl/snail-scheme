(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell socket))

;; A mismatch here is a broken test-host invariant. Guest conversions that
;; are expected to fail use dyn-tc handlers in the dedicated fixtures.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (try-convert value target)
       ((Ok checked) checked)
       ((Err _) (panic "fixture payload has the wrong type"))))))


(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

;; A program waits on sockets from a task, which the scheduler runs once
;; main returns.
(dispatch-local
 (once (lambda ()
         (handle udp
             ((bind (lambda (endpoint)
                      (Ok (UdpSocket (type-convert (ref (Datagram endpoint #u8())) Any)
                                     (Endpoint-port endpoint)))))
              (send (lambda (socket peer bytes)
                      (sleep 1)
                      (ref-set! (fixture-convert (UdpSocket-token socket) (Ref Datagram))
                                (Datagram peer bytes))
                      (Ok (i64->i32 (vector-length bytes)))))
              (receive (lambda (socket _)
                         (Ok (ref-get (fixture-convert (UdpSocket-token socket) (Ref Datagram))))))
              (close-udp (lambda (_) (Ok (unit)))))
           (let ((socket (require (bind (require (endpoint "192.0.2.1" 7))))))
             (dispatch-local
              (once (lambda ()
                      (require (send socket (require (endpoint "192.0.2.2" 8)) #u8(9 10)))
                      (let ((packet (require (receive socket 2))))
                        (write-line (Endpoint-address (Datagram-peer packet)))
                        (display (vector->list (Datagram-bytes packet)))
                        (newline))))))))))
(write-line "main returns")
