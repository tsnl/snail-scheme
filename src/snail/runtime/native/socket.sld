;; Node's TCP and UDP sockets, as host/native/socket-imports.mjs provides
;; them. Everything crosses as a number: an endpoint as its address, whose
;; four octets are the I32's unsigned bits, most significant first, and
;; its port; a listener, connection or UDP socket as the host's handle,
;; which is never 0. An operation that waits is started by `start-NAME`,
;; which reads its arguments at once, and answered by `finish` with its
;; ticket ((snail shell task)'s `through-host`); a close answers at once.
;;
;; An answer is -1 for a failure, and otherwise the operation's own number.
;; The host holds what else an answer carries until it answers again, so
;; the shell reads it first: a number by `held-number`, and byte strings by
;; `held-length` and `held-byte`, each by its position. A failure's first
;; byte string is its error code, such as "ECONNREFUSED".
;;
;;   operation          answer                number     byte strings
;;   listen, bind       the handle            its port
;;   connect, accept    the handle
;;   read               1, or 0 at the end               the bytes
;;   write, send        the count written
;;   receive            0                     its port   its address's text,
;;                                                       the bytes
;;   finish, close      0
(define-library (snail runtime native socket)
  (export
   start-listen
   start-connect
   start-accept
   start-read
   start-write
   start-finish-connection
   start-bind
   start-send
   start-receive
   finish
   close-tcp
   close-udp
   held-number
   held-length
   held-byte)
  (import
   (snail core base))
  (begin
    (extern start-listen "snail.runtime.native.socket" "start-listen" (-> I64 I32 I32 I32 Unit))
    (extern start-connect "snail.runtime.native.socket" "start-connect" (-> I64 I32 I32 Unit))
    (extern start-accept "snail.runtime.native.socket" "start-accept" (-> I64 I32 Unit))
    (extern start-read "snail.runtime.native.socket" "start-read" (-> I64 I32 I32 Unit))
    (extern start-write "snail.runtime.native.socket" "start-write" (-> I64 I32 Bytes Unit))
    (extern start-finish-connection
            "snail.runtime.native.socket"
            "start-finish-connection"
            (-> I64 I32 I32 Unit))
    (extern start-bind "snail.runtime.native.socket" "start-bind" (-> I64 I32 I32 I32 Unit))
    (extern start-send "snail.runtime.native.socket" "start-send" (-> I64 I32 I32 I32 Bytes Unit))
    (extern start-receive "snail.runtime.native.socket" "start-receive" (-> I64 I32 I32 Unit))
    (extern finish "snail.runtime.native.socket" "finish" (-> I64 I32))
    (extern close-tcp "snail.runtime.native.socket" "close-tcp" (-> I32 I32))
    (extern close-udp "snail.runtime.native.socket" "close-udp" (-> I32 I32))
    (extern held-number "snail.runtime.native.socket" "held-number" (-> I32))
    (extern held-length "snail.runtime.native.socket" "held-length" (-> I32 I32))
    (extern held-byte "snail.runtime.native.socket" "held-byte" (-> I32 I32 I32))))
