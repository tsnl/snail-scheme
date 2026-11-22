;; SHA-256 digests. The first five are the FIPS 180-2 examples; the expected
;; output was produced once by Node's crypto.createHash('sha256') with
;; digest('hex') for the same bytes, and the five agree with the published
;; values. The lengths around 55, 56 and 64 bytes cross the padding's block
;; boundaries. The last digest frames a file as the project service's
;; generation digest does: its name and length as JSON, then its bytes.
(import
 (snail core base)
 (snail core io)
 (snail shell utf8)
 (snail shell json)
 (snail shell compiler sha256))

(define (digest (out OutputPort) (bytes Bytes)) (→ Unit) (! mut)
  (write-line out (string-append (show (array-length bytes)) " " (bytes->hex (sha256 bytes)))))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)
  (digest out (string->utf8 ""))
  (digest out (string->utf8 "abc"))
  (digest out (string->utf8 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
  (digest out
   (string->utf8
    "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))
  (digest out (make-array 1000000 (i32->u8 97)))
  (for-each (lambda (length) (digest out (make-array length (i32->u8 120))))
            (list 1 55 56 57 63 64 65 119 120 128))
  (digest out (array-generate 256 (lambda (index) (i32->u8 (i64->i32 index)))))
  (digest out (string->utf8 "λ € 😀"))
  (let ((image (read-bytes fs "tests/programs/data/pixel.png")))
    (digest out image)
    (let ((frame (string->utf8 (json->string (JsonArray (list (JsonString "pixel.png")
                                                              (JsonInteger
                                                               (array-length image))))))))
      (write-line out (bytes->hex (sha256 (array-append frame image))))))
  (write-line out (bytes->hex #u8(0 1 15 16 127 128 254 255)))
  (unit))
