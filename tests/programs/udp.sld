(import
 (snail core base)
 (snail core io)
 (only (snail shell task) dispatch-local)
 (snail shell socket))

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

;; A program waits on sockets from a task, which the scheduler runs once
;; main returns.
(dispatch-local
 (once (lambda ()
         (let* ((first (require (bind (Endpoint "127.0.0.1" 0))))
                (second (require (bind (Endpoint "127.0.0.1" 0))))
                (peer (Endpoint "127.0.0.1" (UdpSocket-port second)))
                (listener (require (listen (Endpoint "127.0.0.1" 0)))))
           ;; Owner-local handle numbers can coincide. Their token types cannot.
           (match (close-udp (UdpSocket (Listener-token listener) 0))
             ((Err error) (write-line (SocketError-code error)))
             ((Ok _) (panic "TCP token used as UDP")))
           (require (close-listener listener))
           (display (require (send first peer #u8())))
           (newline)
           (display (vector-length (Datagram-bytes (require (receive second 0)))))
           (newline)
           (display (require (send first peer #u8(0 255 128 1))))
           (newline)
           (let ((packet (require (receive second 4))))
             (display (vector->list (Datagram-bytes packet)))
             (newline)
             (display (and (string=? (Endpoint-address (Datagram-peer packet)) "127.0.0.1")
                           (= (Endpoint-port (Datagram-peer packet)) (UdpSocket-port first))))
             (newline))
           (require (send first peer #u8(1 2)))
           (match (receive second 1)
             ((Err error) (write-line (SocketError-code error)))
             ((Ok _) (panic "oversized UDP receive succeeded")))
           (require (send first peer #u8(3)))
           (display (vector->list (Datagram-bytes (require (receive second 1)))))
           (newline)
           (require (close-udp first))
           (require (close-udp first))
           (require (close-udp second)))

         ;; Runtime shutdown also closes delivered datagram sockets left open.
         (require (bind (Endpoint "127.0.0.1" 0)))
         (unit))))
