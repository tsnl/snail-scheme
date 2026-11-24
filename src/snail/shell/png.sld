;; PNG files of RGBA pixels, and data URLs that hold them, so an image the
;; program drew can be shown by an `img` element. The image data is
;; stored, not compressed: zlib's stored blocks need no search, and the
;; images this writes, a portrait or a cell of a sheet, are small.
(define-library (snail shell png)
  (export
   rgba->png
   png-data-url)
  (import
   (snail core base)
   (snail shell base64))
  (begin

    ;; ---- Files ----

    ;; `pixels` holds `height` rows of `width` RGBA texels, top row first.

    (define (rgba->png (width I32) (height I32) (pixels Bytes)) (→ Bytes)
      (list->array
       (concatenate (list (list 137 80 78 71 13 10 26 10)
                          (chunk "IHDR"
                                 (append (word width) (append (word height) (list 8 6 0 0 0))))
                          (chunk "IDAT" (zlib (scanlines width height pixels)))
                          (chunk "IEND" (Nil))))))

    ;; Length, type, data, and the CRC of type and data.

    (define (chunk (type String) (data (List U8))) (→ (List U8))
      (let ((typed
             (append (map (lambda (char) (i32->u8 (char->i32 char))) (string->list type)) data)))
        (concatenate (list (word (i64->i32 (length data))) typed (word (crc32 typed))))))

    (define (word (value I32)) (→ (List U8))
      (map (lambda (shift) (i32->u8 (i32-and (i32-shift-right/logical value shift) 255)))
           (list 24 16 8 0)))

    ;; Each row after a filter byte of 0, none.

    (define (scanlines (width I32) (height I32) (pixels Bytes)) (→ (List U8))
      (let ((row (* 4 (i32->i64 width))))
        (concatenate (map (lambda (y)
                            (Cons (i32->u8 0)
                                  (map (lambda (x) (array-ref pixels (+ (* y row) x))) (iota row))))
                          (iota (i32->i64 height))))))

    ;; ---- Zlib ----

    ;; A header with no dictionary, stored blocks of at most 65535 bytes,
    ;; the last marked final, and the Adler-32 of the data.

    (define (zlib (data (List U8))) (→ (List U8))
      (append (list (i32->u8 120) (i32->u8 1)) (append (blocks data) (word (adler32 data)))))

    (define (blocks (data (List U8))) (→ (List U8))
      (let* ((size (min 65535 (length data))) (final? (= size (length data))))
        (append (Cons (i32->u8 (if final? 1 0))
                      (append (half (i64->i32 size)) (half (i32-xor (i64->i32 size) 65535))))
                (append (take data size) (if final? (Nil) (blocks (list-tail data size)))))))

    ;; Little-endian, as deflate writes a block's length.

    (define (half (value I32)) (→ (List U8))
      (list (i32->u8 (i32-and value 255))
            (i32->u8 (i32-and (i32-shift-right/logical value 8) 255))))

    (define (adler32 (data (List U8))) (→ I32)
      (let ((sums (fold-left (lambda (sums byte)
                               (let ((a
                                      (modulo (+ (● sums first) (i32->i64 (u8->i32 byte))) 65521)))
                                 (new Pair
                                   (first a)
                                   (second (modulo (+ (● sums second) a) 65521)))))
                             (new Pair (first 1) (second 0))
                             data)))
        (i64->i32 (+ (* (● sums second) 65536) (● sums first)))))

    ;; The CRC-32 of ISO 3309, a bit at a time.

    (define (crc32 (data (List U8))) (→ I32)
      (i32-xor (fold-left (lambda (crc byte)
                            (fold-left (lambda (crc _)
                                         (if (= (i32-and crc 1) 1)
                                             (i32-xor (i32-shift-right/logical crc 1) -306674912)
                                             (i32-shift-right/logical crc 1)))
                                       (i32-xor crc (u8->i32 byte))
                                       (iota 8)))
                          -1
                          data)
               -1))

    ;; ---- Data URLs ----

    (define (png-data-url (png Bytes)) (→ String) (data-url "image/png" png))))
