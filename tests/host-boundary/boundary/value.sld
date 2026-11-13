(define-library (boundary value)
  (export Payload)
  (import
   (snail core base))
  (begin

    (struct Payload
      ((number I32)
       (bytes Bytes)))

    (define (buffer (count I32)) (→ (Vector U8))
      (make-vector (i32->i64 count) (i32->u8 0)))

    (define (put! (target (Vector U8)) (index I32) (byte I32)) (→ Unit) (! mut)
      (vector-set! target (i32->i64 index) (i32->u8 byte)))

    (define (finish (number I32) (bytes (Vector U8))) (→ (Result Payload String))
      (if (< number 0)
          (Err "rejected")
          (Ok (Payload number (vector-copy bytes)))))

    (expose buffer "payload-buffer")
    (expose put! "payload-put")
    (expose finish "payload-finish")))
