;; Wire values: types that implement Serialize and Deserialize. A record or
;; enum value is written as its case's TypeId followed by its fields, so a
;; reader detects data written for a different schema. `deriving` makes
;; both instances from a declaration, through the macros defined here.
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
   derive-serialize
   derive-deserialize)
  (import
   (only (snail core forms) case-id)
   (snail core base)
   (except (snail core primitive) string-append))
  (begin

    ;; ---- Classes ----

    (typeclass (Serialize T)
      (declare (encode (value T) (encoder Encoder)) (→ Unit)))

    (typeclass (Deserialize T)
      (declare (decode (decoder Decoder)) (→ T)))

    ;; ---- Byte streams ----

    ;; The encoder collects bytes in reverse; the decoder reads forward. Each
    ;; is one call's own state, and keeps the `Mut` that call made it with,
    ;; so an instance's `encode` and `decode` take none.
    (record Encoder
      ((mut Mut)
       (bytes (List U8))))

    (record Decoder
      ((mut Mut)
       (bytes Bytes)
       (position I64)))

    (define (encode-byte (encoder Encoder) (byte U8)) (→ Unit)
      (set! (● encoder mut) (● encoder bytes) (Cons byte (● encoder bytes))))

    (define (decode-byte (decoder Decoder)) (→ U8)
      (let ((position (● decoder position)))
        (when (>= position (array-length (● decoder bytes)))
          (panic "wire data ended early"))
        (set! (● decoder mut) (● decoder position) (+ position 1))
        (array-ref (● decoder bytes) position)))

    ;; The encoder and its buffer are local to this call.

    (define (serialize (value T)) (→ Bytes) (∀ (T)) (⊨ (Serialize T))
      (let ((encoder (new Encoder (mut (unsafe-mut)) (bytes (Nil)))))
        (encode value encoder)
        (list->array (reverse (● encoder bytes)))))

    ;; Panics if the bytes were not written for this type. The decoder's
    ;; position is local to this call.

    (define (deserialize (bytes Bytes)) (→ T) (∀ (T)) (⊨ (Deserialize T))
      (let* ((decoder (new Decoder (mut (unsafe-mut)) (bytes bytes) (position 0)))
             (value (decode decoder)))
        (unless (= (● decoder position) (array-length bytes))
          (panic "wire data has trailing bytes"))
        value))

    ;; ---- Variable-length integers ----

    ;; Seven bits per byte, least significant first; signed values are
    ;; zigzag-encoded so small magnitudes stay short.

    (define (encode-unsigned (encoder Encoder) (value I64)) (→ Unit)
      (let ((low (i64->i32 (i64-and value 127))) (rest (i64-shift-right/logical value 7)))
        (if (= rest 0)
            (encode-byte encoder (i32->u8 low))
            (begin (encode-byte encoder (i32->u8 (i32-or low 128)))
                   (encode-unsigned encoder rest)))))

    (define (decode-unsigned (decoder Decoder)) (→ I64)
      (let loop ((shift 0) (value 0))
        (let ((byte (i32->i64 (u8->i32 (decode-byte decoder)))))
          (let ((value (i64-or value (i64-shift-left (i64-and byte 127) shift))))
            (if (= (i64-and byte 128) 0) value (loop (+ shift 7) value))))))

    (define (encode-signed (encoder Encoder) (value I64)) (→ Unit)
      (encode-unsigned encoder (i64-xor (i64-shift-left value 1) (i64-shift-right value 63))))

    (define (decode-signed (decoder Decoder)) (→ I64)
      (let ((value (decode-unsigned decoder)))
        (i64-xor (i64-shift-right/logical value 1) (negate (i64-and value 1)))))

    ;; ---- Case identities ----

    (define (encode-case-id (encoder Encoder) (id I32)) (→ Unit)
      (encode-signed encoder (i32->i64 id)))

    (define (decode-case-id (decoder Decoder)) (→ I32)
      (i64->i32 (decode-signed decoder)))

    (define (expect-case-id (decoder Decoder) (id I32)) (→ Unit)
      (unless (= (decode-case-id decoder) id)
        (panic "wire data has a different schema")))

    ;; ---- Derived instances ----

    ;; `(deriving Serialize Deserialize)` on a record or an enum is a use of
    ;; these macros, in the form the expander's "Deriving" section
    ;; describes. A value is its case's TypeId, then its fields in order.

    (define-syntax derive-serialize
      (syntax-rules ()
        ((_ kind (name param ...) (case text (field label label-text type) ...) ...)
         (instance (Serialize (name param ...))
           (⊨ (Serialize param) ...)
           (define encode
             (lambda (value encoder)
               (match value
                 ((case field ...)
                  (encode-case-id encoder (case-id case))
                  (encode field encoder) ...
                  (unit)) ...)))))))

    ;; A record is one case, built by label. For an enum, the TypeId read
    ;; selects the case; an unknown one is another schema.

    (define-syntax derive-deserialize
      (syntax-rules (record enum)
        ((_ record (name param ...) (case text (field label label-text type) ...))
         (instance (Deserialize (name param ...))
           (⊨ (Deserialize param) ...)
           (define decode
             (lambda (decoder)
               (expect-case-id decoder (case-id case))
               (let* ((field (decode decoder)) ...)
                 (new name (label field) ...))))))
        ((_ enum (name param ...) (case text (field label label-text type) ...) ...)
         (instance (Deserialize (name param ...))
           (⊨ (Deserialize param) ...)
           (define decode
             (lambda (decoder)
               (let ((id (decode-case-id decoder)))
                 (cond
                  ((= id (case-id case)) (let* ((field (decode decoder)) ...) (case field ...)))
                  ...
                  (else (panic "wire data has a different schema"))))))))))

    ;; ---- Scalars, text and collections ----

    (instance (Serialize I64)
      (define (encode (value I64) (encoder Encoder)) (→ Unit)
        (encode-signed encoder value)))

    (instance (Deserialize I64)
      (define (decode (decoder Decoder)) (→ I64)
        (decode-signed decoder)))

    (instance (Serialize I32)
      (define (encode (value I32) (encoder Encoder)) (→ Unit)
        (encode-signed encoder (i32->i64 value))))

    (instance (Deserialize I32)
      (define (decode (decoder Decoder)) (→ I32)
        (i64->i32 (decode-signed decoder))))

    (instance (Serialize U8)
      (define (encode (value U8) (encoder Encoder)) (→ Unit)
        (encode-byte encoder value)))

    (instance (Deserialize U8)
      (define (decode (decoder Decoder)) (→ U8)
        (decode-byte decoder)))

    (instance (Serialize Bool)
      (define (encode (value Bool) (encoder Encoder)) (→ Unit)
        (encode-byte encoder (if value 1 0))))

    (instance (Deserialize Bool)
      (define (decode (decoder Decoder)) (→ Bool)
        (= (decode-byte decoder) 1)))

    (instance (Serialize Char)
      (define (encode (value Char) (encoder Encoder)) (→ Unit)
        (encode-unsigned encoder (char->integer value))))

    (instance (Deserialize Char)
      (define (decode (decoder Decoder)) (→ Char)
        (integer->char (decode-unsigned decoder))))

    (instance (Serialize Unit)
      (define (encode (value Unit) (encoder Encoder)) (→ Unit)
        (unit)))

    (instance (Deserialize Unit)
      (define (decode (decoder Decoder)) (→ Unit)
        (unit)))

    (instance (Serialize F64)
      (define (encode (value F64) (encoder Encoder)) (→ Unit)
        (encode-signed encoder (f64->bits value))))

    (instance (Deserialize F64)
      (define (decode (decoder Decoder)) (→ F64)
        (bits->f64 (decode-signed decoder))))

    (instance (Serialize F32)
      (define (encode (value F32) (encoder Encoder)) (→ Unit)
        (encode-signed encoder (i32->i64 (f32->bits value)))))

    (instance (Deserialize F32)
      (define (decode (decoder Decoder)) (→ F32)
        (bits->f32 (i64->i32 (decode-signed decoder)))))

    (instance (Serialize String)
      (define (encode (value String) (encoder Encoder)) (→ Unit)
        (encode-unsigned encoder (string-length value))
        (let loop ((index 0))
          (when (< index (string-length value))
            (encode-unsigned encoder (char->integer (string-ref value index)))
            (loop (+ index 1))))))

    (instance (Deserialize String)
      (define (decode (decoder Decoder)) (→ String)
        (let ((count (decode-unsigned decoder)))
          (array->string (decode-elements decoder
                                          count
                                          (lambda (decoder)
                                            (integer->char
                                             (decode-unsigned decoder))))))))

    (instance (Serialize (Array T))
      (⊨ (Serialize T))
      (define (encode (value (Array T)) (encoder Encoder)) (→ Unit)
        (encode-unsigned encoder (array-length value))
        (array-for-each (lambda (item) (encode item encoder)) value)))

    (instance (Deserialize (Array T))
      (⊨ (Deserialize T))
      (define (decode (decoder Decoder)) (→ (Array T))
        (decode-elements decoder (decode-unsigned decoder) decode)))

    (instance (Serialize (List T))
      (⊨ (Serialize T))
      (define (encode (value (List T)) (encoder Encoder)) (→ Unit)
        (encode-unsigned encoder (length value))
        (for-each (lambda (item) (encode item encoder)) value)))

    (instance (Deserialize (List T))
      (⊨ (Deserialize T))
      (define (decode (decoder Decoder)) (→ (List T))

        (array->list (decode-elements decoder (decode-unsigned decoder) decode))))

    ;; The elements are decoded in index order, as `array-generate` asks
    ;; for them; no array is needed, whose elements would have to be unboxed.

    (define (decode-elements (decoder Decoder)
                             (count I64)
                             (decode-one (Fn Decoder → T)))
      (→ (Array T))
      (∀ (T))
      (array-generate count (lambda (index) (decode-one decoder))))

    (instance (Serialize (Option T))
      (⊨ (Serialize T))
      (define (encode (value (Option T)) (encoder Encoder)) (→ Unit)
        (match value
          ((None) (encode-byte encoder 0))
          ((Some item) (encode-byte encoder 1) (encode item encoder)))))

    (instance (Deserialize (Option T))
      (⊨ (Deserialize T))
      (define (decode (decoder Decoder)) (→ (Option T))
        (if (= (decode-byte decoder) 0) (None) (Some (decode decoder)))))

    ))
