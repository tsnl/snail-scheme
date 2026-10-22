(define-library (ping)
  (export
   Ping
   Ping-text
   Pong
   Pong-text)
  (import
   (lofi base)
   (lofi wire))
  (begin
    (struct Ping
      ((text String))
      (deriving Serialize Deserialize))

    (struct Pong
      ((text String))
      (deriving Serialize Deserialize))))
