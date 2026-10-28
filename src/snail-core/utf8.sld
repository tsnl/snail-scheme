;; Text as UTF-8 bytes, and bytes as text only when they are UTF-8. Decoding
;; is strict, as a fatal `TextDecoder` is: the first ill-formed sequence fails
;; the whole decode, nothing is replaced, and a byte order mark stays text.
(define-library (snail-core utf8)
  (export
   Utf8Error
   Utf8Error-offset
   utf8->string
   string->utf8)
  (import
   (snail-core base))
  (begin

    ;; ---- Errors ----

    ;; The offset of the first byte of the first ill-formed sequence: its
    ;; lead, or the stray continuation or invalid byte that stands alone.
    (struct Utf8Error
      ((offset I64)))

    ;; ---- Decoding ----

    ;; What a lead byte says of its sequence: the sequence's length in
    ;; bytes, the range its second byte must fall in, and the bits the lead
    ;; contributes to the scalar.
    (struct Lead
      ((width I64)
       (low I32)
       (high I32)
       (bits I32)))

    ;; Table 3-7 of the Unicode Standard, the well-formed sequences. Each
    ;; continuation is 80..BF, except that the second byte's range narrows
    ;; after four leads: E0 and F0 would otherwise begin overlong forms, ED
    ;; a surrogate, and F4 a code beyond U+10FFFF. C0, C1 and F5..FF begin
    ;; nothing, and neither does a continuation.
    (: lead (-> I32 (Option Lead)))
    (define (lead byte)
      (cond ((< byte 128) (Some (Lead 1 0 0 byte)))
            ((< byte 194) (None))
            ((< byte 224) (Some (Lead 2 128 191 (i32-and byte 31))))
            ((= byte 224) (Some (Lead 3 160 191 0)))
            ((= byte 237) (Some (Lead 3 128 159 13)))
            ((< byte 240) (Some (Lead 3 128 191 (i32-and byte 15))))
            ((= byte 240) (Some (Lead 4 144 191 0)))
            ((< byte 244) (Some (Lead 4 128 191 (i32-and byte 7))))
            ((= byte 244) (Some (Lead 4 128 143 4)))
            (else (None))))

    ;; The byte at `index`, if the bytes reach that far and it is in the
    ;; range from `low` to `high`.
    (: continuation (-> Bytes I64 I32 I32 (Option I32)))
    (define (continuation bytes index low high)
      (if (< index (vector-length bytes))
          (let ((byte (u8->i32 (vector-ref bytes index))))
            (if (and (<= low byte) (<= byte high)) (Some byte) (None)))
          (None)))

    ;; The scalar whose sequence starts at `index`, and the index after it,
    ;; or None if the sequence is ill-formed or the bytes end inside it.
    ;; Each continuation adds its low six bits.
    (: sequence-at (-> Bytes I64 (Option (Pair Char I64))))
    (define (sequence-at bytes index)
      (match (lead (u8->i32 (vector-ref bytes index)))
        ((None) (None))
        ((Some lead)
         (let loop ((next 1) (code (Lead-bits lead)))
           (if (= next (Lead-width lead))
               (Some (Pair (i32->char code) (+ index next)))
               (match (continuation bytes (+ index next) (if (= next 1) (Lead-low lead) 128) (if (= next 1) (Lead-high lead) 191))
                 ((None) (None))
                 ((Some byte) (loop (+ next 1) (i32-or (i32-shift-left code 6) (i32-and byte 63))))))))))

    ;; A text has at most as many scalars as its bytes, so one array of
    ;; that length, local to this call, holds them all.
    (: utf8->string (-> Bytes (Result String Utf8Error)))
    (define (utf8->string bytes)
      (let ((chars (make-array (vector-length bytes) #\space)))
        (let loop ((index 0) (count 0))
          (if (= index (vector-length bytes))
              (Ok (vector->string (subvector (array->vector chars) 0 count)))
              (match (sequence-at bytes index)
                ((None) (Err (Utf8Error index)))
                ((Some decoded)
                 (array-set! chars count (Pair-first decoded))
                 (loop (Pair-second decoded) (+ count 1))))))))

    ;; ---- Encoding ----

    ;; A Char that is not a Unicode scalar, a surrogate or a code beyond
    ;; U+10FFFF, can come only from `i32->char`. It encodes as U+FFFD, as
    ;; `TextEncoder` encodes a lone surrogate, so the output is always UTF-8.
    (: scalar (-> Char I32))
    (define (scalar char)
      (let ((code (char->i32 char)))
        (if (or (< code 0) (> code 1114111) (and (>= code 55296) (<= code 57343))) 65533 code)))

    (: encoded-width (-> I32 I64))
    (define (encoded-width code)
      (cond ((< code 128) 1)
            ((< code 2048) 2)
            ((< code 65536) 3)
            (else 4)))

    ;; The high bits of a lead byte, which give its sequence's width:
    ;; 0xxxxxxx, 110xxxxx, 1110xxxx or 11110xxx.
    (: lead-marker (-> I64 I32))
    (define (lead-marker width)
      (case width
        ((1) 0)
        ((2) 192)
        ((3) 224)
        (else 240)))

    ;; Byte `position` of a scalar's encoding. The lead carries the scalar's
    ;; highest bits after its marker; each continuation, 10xxxxxx, carries
    ;; the next six.
    (: encoded-byte (-> I32 I64 I64 U8))
    (define (encoded-byte code width position)
      (let ((bits (i32-shift-right/logical code (i64->i32 (* 6 (- (- width 1) position))))))
        (i32->u8 (if (= position 0) (i32-or (lead-marker width) bits) (i32-or 128 (i32-and bits 63))))))

    ;; The scalars are measured first, so the bytes fill one array of the
    ;; exact length, local to this call.
    (: string->utf8 (-> String Bytes))
    (define (string->utf8 text)
      (let* ((codes (vector-map scalar (string->vector text)))
             (bytes (make-array (vector-fold (lambda (total code) (+ total (encoded-width code))) 0 codes) (ann 0 U8))))
        (let loop ((index 0) (offset 0))
          (if (= index (vector-length codes))
              (array->vector bytes)
              (let* ((code (vector-ref codes index)) (width (encoded-width code)))
                (do ((position 0 (+ position 1))) ((= position width))
                  (array-set! bytes (+ offset position) (encoded-byte code width position)))
                (loop (+ index 1) (+ offset width)))))))

    ))
