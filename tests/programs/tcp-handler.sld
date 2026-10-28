(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell socket))

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

;; Mutable test state travels in operation arguments, not the reusable
;; handler's captures. A dispatched task inherits this handler across waits.
(handle tcp
    ((listen
      (lambda (endpoint) (Ok (Listener (type-convert endpoint Any) (Endpoint-port endpoint)))))
     (connect (lambda (_) (Ok (Connection (type-convert (ref #u8()) Any)))))
     (accept (lambda (_) (Ok (Connection (type-convert (ref #u8()) Any)))))
     (read (lambda (connection _)
             (Ok (Some (ref-get (type-convert (Connection-token connection) (Ref Bytes)))))))
     (write (lambda (connection bytes)
              (sleep 1)
              (ref-set! (type-convert (Connection-token connection) (Ref Bytes)) bytes)
              (Ok (i64->i32 (vector-length bytes)))))
     (close-listener (lambda (_) (Ok (unit))))
     (finish-connection (lambda (connection grace)
                          (sleep 1)
                          (display grace)
                          (newline)
                          (ref-set! (type-convert (Connection-token connection) (Ref Bytes)) #u8())
                          (Ok (unit))))
     (close-connection (lambda (_) (Ok (unit)))))
  (let ((connection (require (connect (Endpoint "test" 0)))))
    (dispatch-local
     (once (lambda ()
             (require (write connection #u8(7 8)))
             (match (require (read connection 2))
               ((Some bytes) (display (vector->list bytes)))
               ((None) (panic "unexpected EOF")))
             (newline)
             (require (finish-connection connection 250)))))))
(write-line "main returns")
