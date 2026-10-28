(define-library (boundary value)
  (export Payload Payload-number Payload-bytes)
  (import
   (snail core base))
  (begin

    (struct Payload
      ((number I32)
       (bytes Bytes)))

    (: buffer (-> I32 (Array U8) ! mut))
    (define (buffer count)
      (make-array (i32->i64 count) (i32->u8 0)))

    (: put! (-> (Array U8) I32 I32 Unit ! mut))
    (define (put! target index byte)
      (array-set! target (i32->i64 index) (i32->u8 byte)))

    (: finish (-> I32 (Array U8) (Result Payload String) ! mut))
    (define (finish number bytes)
      (if (< number 0)
          (Err "rejected")
          (Ok (Payload number (array->vector bytes)))))

    (expose buffer "payload-buffer")
    (expose put! "payload-put")
    (expose finish "payload-finish")))
