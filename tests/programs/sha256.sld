;; SHA-256 digests. The first five are the FIPS 180-2 examples; the expected
;; output was produced once by Node's crypto.createHash('sha256') with
;; digest('hex') for the same bytes, and the five agree with the published
;; values. The lengths around 55, 56 and 64 bytes cross the padding's block
;; boundaries. The last digest frames a file as the project service's
;; generation digest does: its name and length as JSON, then its bytes.
(import
 (snail-core base)
 (snail-core io)
 (snail-core utf8)
 (snail-core json)
 (snail-core sha256))

(: digest (-> Bytes Unit ! console))
(define (digest bytes)
  (write-line (string-append (show (vector-length bytes)) " " (bytes->hex (sha256 bytes)))))

(digest (string->utf8 ""))
(digest (string->utf8 "abc"))
(digest (string->utf8 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
(digest (string->utf8 "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))
(digest (make-vector 1000000 (i32->u8 97)))
(for-each (lambda (length) (digest (make-vector length (i32->u8 120)))) (list 1 55 56 57 63 64 65 119 120 128))
(digest (vector-generate 256 (lambda (index) (i32->u8 (i64->i32 index)))))
(digest (string->utf8 "λ € 😀"))

(let ((image (read-bytes "tests/programs/data/pixel.png")))
  (digest image)
  (let ((frame (string->utf8 (json->string (JsonArray (list (JsonString "pixel.png") (JsonInteger (vector-length image))))))))
    (write-line (bytes->hex (sha256 (vector-append frame image))))))
(write-line (bytes->hex #u8(0 1 15 16 127 128 254 255)))
