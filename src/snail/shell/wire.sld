;; Wire values: types that implement Serialize and Deserialize. A struct or
;; enum value is written as its case's TypeId followed by its fields, so a
;; reader detects data written for a different schema. `deriving` generates
;; both instances from a declaration.
(define-library (snail shell wire)
  (export
   Serialize
   encode
   Deserialize
   decode
   Encoder
   Decoder
   serialize
   deserialize
   encode-case-id
   expect-case-id
   decode-case-id
   case-id=?)
  (import
   (snail core base)
   (except (snail core primitive) string-append))
  (begin

    ;; ---- Classes ----

    (typeclass (Serialize T)
      (: encode (-> T Encoder Unit ! mut)))

    (typeclass (Deserialize T)
      (: decode (-> Decoder T ! mut)))

    ;; ---- Byte streams ----

    ;; The encoder doubles its array as it fills; the decoder reads forward.
    (struct Encoder
      ((bytes (Ref (Array U8)))
       (size (Ref I64))))

    (struct Decoder
      ((bytes Bytes)
       (position (Ref I64))))

    (: encode-byte (-> Encoder U8 Unit ! mut))
    (define (encode-byte encoder byte)
      (let ((bytes (ref-get (Encoder-bytes encoder))) (size (ref-get (Encoder-size encoder))))
        (when (= size (array-length bytes))
          (let ((larger (make-array (* 2 size) (ann 0 U8))))
            (array-copy! larger 0 bytes 0 size)
            (ref-set! (Encoder-bytes encoder) larger)))
        (array-set! (ref-get (Encoder-bytes encoder)) size byte)
        (ref-set! (Encoder-size encoder) (+ size 1))))

    (: decode-byte (-> Decoder U8 ! mut))
    (define (decode-byte decoder)
      (let ((position (ref-get (Decoder-position decoder))))
        (when (>= position (vector-length (Decoder-bytes decoder)))
          (panic "wire data ended early"))
        (ref-set! (Decoder-position decoder) (+ position 1))
        (vector-ref (Decoder-bytes decoder) position)))

    ;; The encoder and its buffer are local to this call.
    (: serialize (All (T) (requires (Serialize T) (Copy T)) (-> T Bytes)))
    (define (serialize value)
      (unsafe-total
       (lambda ()
         (let ((encoder (Encoder (ref (make-array 64 (ann 0 U8))) (ref 0))))
           (encode value encoder)
           (subvector (array->vector (ref-get (Encoder-bytes encoder)))
                      0
                      (ref-get (Encoder-size encoder)))))))

    ;; Panics if the bytes were not written for this type. The decoder's
    ;; position is local to this call.
    (: deserialize (All (T) (requires (Deserialize T)) (-> Bytes T)))
    (define (deserialize bytes)
      (unsafe-total
       (lambda ()
         (let* ((decoder (Decoder bytes (ref 0))) (value (decode decoder)))
           (unless (= (ref-get (Decoder-position decoder)) (vector-length bytes))
             (panic "wire data has trailing bytes"))
           value))))

    ;; ---- Variable-length integers ----

    ;; Seven bits per byte, least significant first; signed values are
    ;; zigzag-encoded so small magnitudes stay short.
    (: encode-unsigned (-> Encoder I64 Unit ! mut))
    (define (encode-unsigned encoder value)
      (let ((low (i64->i32 (i64-and value 127))) (rest (i64-shift-right/logical value 7)))
        (if (= rest 0)
            (encode-byte encoder (i32->u8 low))
            (begin (encode-byte encoder (i32->u8 (i32-or low 128)))
                   (encode-unsigned encoder rest)))))

    (: decode-unsigned (-> Decoder I64 ! mut))
    (define (decode-unsigned decoder)
      (let loop ((shift 0) (value 0))
        (let ((byte (i32->i64 (u8->i32 (decode-byte decoder)))))
          (let ((value (i64-or value (i64-shift-left (i64-and byte 127) shift))))
            (if (= (i64-and byte 128) 0) value (loop (+ shift 7) value))))))

    (: encode-signed (-> Encoder I64 Unit ! mut))
    (define (encode-signed encoder value)
      (encode-unsigned encoder (i64-xor (i64-shift-left value 1) (i64-shift-right value 63))))

    (: decode-signed (-> Decoder I64 ! mut))
    (define (decode-signed decoder)
      (let ((value (decode-unsigned decoder)))
        (i64-xor (i64-shift-right/logical value 1) (negate (i64-and value 1)))))

    ;; ---- Case identities ----

    (: encode-case-id (-> Encoder I32 Unit ! mut))
    (define (encode-case-id encoder id)
      (encode-signed encoder (i32->i64 id)))

    (: decode-case-id (-> Decoder I32 ! mut))
    (define (decode-case-id decoder)
      (i64->i32 (decode-signed decoder)))

    (: expect-case-id (-> Decoder I32 Unit ! mut))
    (define (expect-case-id decoder id)
      (unless (= (decode-case-id decoder) id)
        (panic "wire data has a different schema")))

    (: case-id=? (-> I32 I32 Bool))
    (define (case-id=? a b)
      (= a b))

    ;; ---- Scalars, text and collections ----

    (instance (Serialize I64)
      (define (encode value encoder) (encode-signed encoder value)))

    (instance (Deserialize I64)
      (define (decode decoder) (decode-signed decoder)))

    (instance (Serialize I32)
      (define (encode value encoder) (encode-signed encoder (i32->i64 value))))

    (instance (Deserialize I32)
      (define (decode decoder) (i64->i32 (decode-signed decoder))))

    (instance (Serialize U8)
      (define (encode value encoder) (encode-byte encoder value)))

    (instance (Deserialize U8)
      (define (decode decoder) (decode-byte decoder)))

    (instance (Serialize Bool)
      (define (encode value encoder) (encode-byte encoder (if value 1 0))))

    (instance (Deserialize Bool)
      (define (decode decoder) (= (decode-byte decoder) 1)))

    (instance (Serialize Char)
      (define (encode value encoder) (encode-unsigned encoder (char->integer value))))

    (instance (Deserialize Char)
      (define (decode decoder) (integer->char (decode-unsigned decoder))))

    (instance (Serialize Unit)
      (define (encode value encoder) (unit)))

    (instance (Deserialize Unit)
      (define (decode decoder) (unit)))

    (instance (Serialize F64)
      (define (encode value encoder) (encode-signed encoder (f64->bits value))))

    (instance (Deserialize F64)
      (define (decode decoder) (bits->f64 (decode-signed decoder))))

    (instance (Serialize F32)
      (define (encode value encoder) (encode-signed encoder (i32->i64 (f32->bits value)))))

    (instance (Deserialize F32)
      (define (decode decoder) (bits->f32 (i64->i32 (decode-signed decoder)))))

    (instance (Serialize String)
      (define (encode value encoder)
        (encode-unsigned encoder (string-length value))
        (let loop ((index 0))
          (when (< index (string-length value))
            (encode-unsigned encoder (char->integer (string-ref value index)))
            (loop (+ index 1))))))

    (instance (Deserialize String)
      (define (decode decoder)
        (let ((count (decode-unsigned decoder)))
          (vector->string (decode-elements decoder
                                           count
                                           (lambda (decoder)
                                             (integer->char (decode-unsigned decoder))))))))

    (instance (Serialize (Vector T))
      (requires (Serialize T) (Copy T))
      (define (encode value encoder)
        (encode-unsigned encoder (vector-length value))
        (vector-for-each (lambda (item) (encode item encoder)) value)))

    (instance (Deserialize (Vector T))
      (requires (Deserialize T) (Copy T))
      (define (decode decoder)
        (decode-elements decoder (decode-unsigned decoder) decode)))

    (instance (Serialize (List T))
      (requires (Serialize T) (Copy T))
      (define (encode value encoder)
        (encode-unsigned encoder (length value))
        (for-each (lambda (item) (encode item encoder)) value)))

    (instance (Deserialize (List T))
      (requires (Deserialize T) (Copy T))
      (define (decode decoder)
        (vector->list (decode-elements decoder (decode-unsigned decoder) decode))))

    (: decode-elements
       (All (T) (requires (Copy T)) (-> Decoder I64 (-> Decoder T ! mut) (Vector T) ! mut)))
    (define (decode-elements decoder count decode-one)
      (if (= count 0)
          (vector-generate 0 (lambda (index) (panic "no elements")))
          (let ((items (make-array count (decode-one decoder))))
            (let loop ((index 1))
              (when (< index count)
                (array-set! items index (decode-one decoder))
                (loop (+ index 1))))
            (array->vector items))))

    (instance (Serialize (Option T))
      (requires (Serialize T))
      (define (encode value encoder)
        (match value
          ((None) (encode-byte encoder 0))
          ((Some item) (encode-byte encoder 1) (encode item encoder)))))

    (instance (Deserialize (Option T))
      (requires (Deserialize T))
      (define (decode decoder)
        (if (= (decode-byte decoder) 0) (None) (Some (decode decoder)))))

    ))
