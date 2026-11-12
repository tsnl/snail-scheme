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
   (except (snail core primitive)
           string-append
           make-array
           array-length
           array-ref
           array-set!
           array->vector
           vector->array
           array-copy!
           vector-copy!))
  (begin

    ;; ---- Classes ----

    (typeclass (Serialize T)
      (: encode (Fn T Encoder → Unit ! mut)))

    (typeclass (Deserialize T)
      (: decode (Fn Decoder → T ! mut)))

    ;; ---- Byte streams ----

    ;; The encoder doubles its array as it fills; the decoder reads forward.
    (struct Encoder
      ((bytes (Array U8))
       (size I64)))

    (struct Decoder
      ((bytes Bytes)
       (position I64)))

    (define (encode-byte (encoder Encoder) (byte U8)) (→ Unit) (! mut)
      (let ((bytes (● encoder bytes)) (size (● encoder size)))
        (when (= size (array-length bytes))
          (let ((larger (make-array (* 2 size) (ann 0 U8))))
            (array-copy! larger 0 bytes 0 size)
            (set! (● encoder bytes) larger)))
        (array-set! (● encoder bytes) size byte)
        (set! (● encoder size) (+ size 1))))

    (define (decode-byte (decoder Decoder)) (→ U8) (! mut)
      (let ((position (● decoder position)))
        (when (>= position (vector-length (● decoder bytes)))
          (panic "wire data ended early"))
        (set! (● decoder position) (+ position 1))
        (vector-ref (● decoder bytes) position)))

    ;; The encoder and its buffer are local to this call.

    (define (serialize (value T)) (→ Bytes) (∀ T) (⊨ (Serialize T) (Copy T) (Drop (!) T))
      (unsafe-total
       (lambda ()
         (let ((encoder (Encoder (make-array 64 (ann 0 U8)) 0)))
           (encode value encoder)
           (subvector (array->vector (● encoder bytes))
                      0
                      (● encoder size))))))

    ;; Panics if the bytes were not written for this type. The decoder's
    ;; position is local to this call.

    (define (deserialize (bytes Bytes)) (→ T) (∀ T) (⊨ (Deserialize T))
      (unsafe-total
       (lambda ()
         (let* ((decoder (Decoder bytes 0)) (value (decode decoder)))
           (unless (= (● decoder position) (vector-length bytes))
             (panic "wire data has trailing bytes"))
           value))))

    ;; ---- Variable-length integers ----

    ;; Seven bits per byte, least significant first; signed values are
    ;; zigzag-encoded so small magnitudes stay short.

    (define (encode-unsigned (encoder Encoder) (value I64)) (→ Unit) (! mut)
      (let ((low (i64->i32 (i64-and value 127))) (rest (i64-shift-right/logical value 7)))
        (if (= rest 0)
            (encode-byte encoder (i32->u8 low))
            (begin (encode-byte encoder (i32->u8 (i32-or low 128)))
                   (encode-unsigned encoder rest)))))

    (define (decode-unsigned (decoder Decoder)) (→ I64) (! mut)
      (let loop ((shift 0) (value 0))
        (let ((byte (i32->i64 (u8->i32 (decode-byte decoder)))))
          (let ((value (i64-or value (i64-shift-left (i64-and byte 127) shift))))
            (if (= (i64-and byte 128) 0) value (loop (+ shift 7) value))))))

    (define (encode-signed (encoder Encoder) (value I64)) (→ Unit) (! mut)
      (encode-unsigned encoder (i64-xor (i64-shift-left value 1) (i64-shift-right value 63))))

    (define (decode-signed (decoder Decoder)) (→ I64) (! mut)
      (let ((value (decode-unsigned decoder)))
        (i64-xor (i64-shift-right/logical value 1) (negate (i64-and value 1)))))

    ;; ---- Case identities ----

    (define (encode-case-id (encoder Encoder) (id I32)) (→ Unit) (! mut)
      (encode-signed encoder (i32->i64 id)))

    (define (decode-case-id (decoder Decoder)) (→ I32) (! mut)
      (i64->i32 (decode-signed decoder)))

    (define (expect-case-id (decoder Decoder) (id I32)) (→ Unit) (! mut)
      (unless (= (decode-case-id decoder) id)
        (panic "wire data has a different schema")))

    (define (case-id=? (a I32) (b I32)) (→ Bool)
      (= a b))

    ;; ---- Scalars, text and collections ----

    (instance (Serialize I64)
      (define encode (lambda (value encoder) (encode-signed encoder value))))

    (instance (Deserialize I64)
      (define decode (lambda (decoder) (decode-signed decoder))))

    (instance (Serialize I32)
      (define encode (lambda (value encoder) (encode-signed encoder (i32->i64 value)))))

    (instance (Deserialize I32)
      (define decode (lambda (decoder) (i64->i32 (decode-signed decoder)))))

    (instance (Serialize U8)
      (define encode (lambda (value encoder) (encode-byte encoder value))))

    (instance (Deserialize U8)
      (define decode (lambda (decoder) (decode-byte decoder))))

    (instance (Serialize Bool)
      (define encode (lambda (value encoder) (encode-byte encoder (if value 1 0)))))

    (instance (Deserialize Bool)
      (define decode (lambda (decoder) (= (decode-byte decoder) 1))))

    (instance (Serialize Char)
      (define encode (lambda (value encoder) (encode-unsigned encoder (char->integer value)))))

    (instance (Deserialize Char)
      (define decode (lambda (decoder) (integer->char (decode-unsigned decoder)))))

    (instance (Serialize Unit)
      (define encode (lambda (value encoder) (unit))))

    (instance (Deserialize Unit)
      (define decode (lambda (decoder) (unit))))

    (instance (Serialize F64)
      (define encode (lambda (value encoder) (encode-signed encoder (f64->bits value)))))

    (instance (Deserialize F64)
      (define decode (lambda (decoder) (bits->f64 (decode-signed decoder)))))

    (instance (Serialize F32)
      (define encode (lambda (value encoder) (encode-signed encoder (i32->i64 (f32->bits value))))))

    (instance (Deserialize F32)
      (define decode (lambda (decoder) (bits->f32 (i64->i32 (decode-signed decoder))))))

    (instance (Serialize String)
      (define encode
        (lambda (value encoder) (encode-unsigned encoder (string-length value))
                (let loop ((index 0))
                  (when (< index (string-length value))
                    (encode-unsigned encoder (char->integer (string-ref value index)))
                    (loop (+ index 1)))))))

    (instance (Deserialize String)
      (define decode
        (lambda (decoder) (let ((count (decode-unsigned decoder)))
                            (vector->string (decode-elements decoder
                                                             count
                                                             (lambda (decoder)
                                                               (integer->char
                                                                (decode-unsigned decoder)))))))))

    (instance (Serialize (Vector T))
      (⊨ (Serialize T) (Copy T) (Drop (!) T))
      (define encode
        (lambda (value encoder) (encode-unsigned encoder (vector-length value))
                (vector-for-each (lambda (item) (encode item encoder)) value))))

    (instance (Deserialize (Vector T))
      (⊨ (Deserialize T) (Copy T) (Drop (!) T))
      (define decode
        (lambda (decoder) (decode-elements decoder (decode-unsigned decoder) decode))))

    (instance (Serialize (List T))
      (⊨ (Serialize T) (Copy T) (Drop (!) T))
      (define encode
        (lambda (value encoder) (encode-unsigned encoder (length value))
                (for-each (lambda (item) (encode item encoder)) value))))

    (instance (Deserialize (List T))
      (⊨ (Deserialize T) (Copy T) (Drop (!) T))
      (define decode
        (lambda (decoder)
          (vector->list (decode-elements decoder (decode-unsigned decoder) decode)))))

    ;; The elements are decoded in index order, as `vector-generate` asks
    ;; for them; no array is needed, whose elements would have to be unboxed.

    (define (decode-elements (decoder Decoder)
                             (count I64)
                             (decode-one (Fn Decoder → T ! mut)))
      (→ (Vector T))
      (! mut)
      (∀ T)
      (⊨ (Copy T) (Drop (!) T))
      (vector-generate count (lambda (index) (decode-one decoder))))

    (instance (Serialize (Option T))
      (⊨ (Serialize T))
      (define encode
        (lambda (value encoder) (match value
                                  ((None) (encode-byte encoder 0))
                                  ((Some item) (encode-byte encoder 1) (encode item encoder))))))

    (instance (Deserialize (Option T))
      (⊨ (Deserialize T))
      (define decode
        (lambda (decoder) (if (= (decode-byte decoder) 0) (None) (Some (decode decoder))))))

    ))
