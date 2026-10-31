;; SHA-256, as FIPS 180-4 defines it, over a whole byte vector, and digests
;; as the lowercase hex Node's `digest('hex')` writes. The compiler names a
;; file it links by this digest, so stage 0 computes it too, and both hosts
;; must agree on every word: a word is an I64 holding an unsigned 32-bit
;; value, and each sum and left shift is masked back to 32 bits, where Wasm's
;; i32 arithmetic would wrap and Chibi's integers would grow.
(define-library (snail shell compiler sha256)
  (export
   sha256
   bytes->hex)
  (import
   (snail core base))
  (begin

    ;; ---- Words ----

    (: word-mask I64)
    (define word-mask 4294967295)

    (: wrap (-> I64 I64))
    (define (wrap value)
      (i64-and value word-mask))

    ;; Words written as the standard prints them: eight lowercase hex
    ;; digits each, one space after every word.
    (: hex-words (-> String (Vector I64)))
    (define (hex-words text)
      (vector-generate (quotient (string-length text) 9)
                       (lambda (word)
                         (fold-left (lambda (value digit)
                                      (+ (* value 16)
                                         (hex-value (string-ref text (+ (* word 9) digit)))))
                                    0 (iota 8)))))

    (: hex-value (-> Char I64))
    (define (hex-value char)
      (let ((code (char->integer char)))
        (if (<= code 57) (- code 48) (- code 87))))

    ;; ---- Constants ----

    ;; §5.3.3: the first 32 bits of the fractional parts of the square
    ;; roots of the first eight primes.
    (: initial-state (Vector I64))
    (define initial-state
      (hex-words "6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19 "))

    ;; §4.2.2: the first 32 bits of the fractional parts of the cube roots
    ;; of the first 64 primes.
    (: round-constants (Vector I64))
    (define round-constants
      (hex-words
       (string-append "428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5 "
                      "d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174 "
                      "e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da "
                      "983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967 "
                      "27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85 "
                      "a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070 "
                      "19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3 "
                      "748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2 ")))

    ;; ---- Word functions ----

    ;; §4.1.2. `rotate` is ROTR; the sigmas mix a word's bits with
    ;; rotations and, for the schedule's small ones, a shift.
    (: rotate (-> I64 I64 I64))
    (define (rotate word count)
      (i64-or (i64-shift-right/logical word count) (wrap (i64-shift-left word (- 32 count)))))

    (: big-sigma0 (-> I64 I64))
    (define (big-sigma0 word)
      (i64-xor (i64-xor (rotate word 2) (rotate word 13)) (rotate word 22)))

    (: big-sigma1 (-> I64 I64))
    (define (big-sigma1 word)
      (i64-xor (i64-xor (rotate word 6) (rotate word 11)) (rotate word 25)))

    (: small-sigma0 (-> I64 I64))
    (define (small-sigma0 word)
      (i64-xor (i64-xor (rotate word 7) (rotate word 18)) (i64-shift-right/logical word 3)))

    (: small-sigma1 (-> I64 I64))
    (define (small-sigma1 word)
      (i64-xor (i64-xor (rotate word 17) (rotate word 19)) (i64-shift-right/logical word 10)))

    ;; Each bit of `x` chooses between the bits of `y` and `z`.
    (: choose (-> I64 I64 I64 I64))
    (define (choose x y z)
      (i64-xor (i64-and x y) (i64-and (i64-xor x word-mask) z)))

    ;; Each bit is the majority of three.
    (: majority (-> I64 I64 I64 I64))
    (define (majority x y z)
      (i64-xor (i64-xor (i64-and x y) (i64-and x z)) (i64-and y z)))

    ;; ---- Padding ----

    ;; §5.1.1: the message is followed by one 1 bit, zeros, and its length
    ;; in bits as a 64-bit big-endian integer, filling whole 64-byte
    ;; blocks. The blocks the message fills are read from it in place;
    ;; only the last one or two, which the padding reaches, are made.
    (: tail-blocks (-> Bytes Bytes))
    (define (tail-blocks message)
      (let* ((length (vector-length message))
             (start (* 64 (quotient length 64)))
             (total (if (< (- length start) 56) 64 128)))
        (vector-generate total
                         (lambda (index)
                           (cond ((< (+ start index) length) (vector-ref message (+ start index)))
                                 ((= (+ start index) length) (i32->u8 128))
                                 ((< index (- total 8)) (i32->u8 0))
                                 (else (length-byte length (- (- total 1) index))))))))

    ;; Byte `place` of the message's length in bits, counting from the
    ;; least significant.
    (: length-byte (-> I64 I64 U8))
    (define (length-byte length place)
      (i32->u8 (i64->i32 (i64-and (i64-shift-right/logical (* 8 length) (* 8 place)) 255))))

    ;; ---- Compression ----

    ;; Word `word` of the block that starts at byte `start`, big-endian.
    (: block-word (-> Bytes I64 I64 I64))
    (define (block-word bytes start word)
      (fold-left (lambda (value index)
                   (+ (* value 256)
                      (i32->i64 (u8->i32 (vector-ref bytes (+ start (+ (* 4 word) index)))))))
                 0 (iota 4)))

    ;; §6.2.2 step 1: the block's sixteen words, then 48 more, each from
    ;; four earlier ones. The array is local to this call.
    (: schedule (-> Bytes I64 (Vector I64)))
    (define (schedule bytes start)
      (let ((words (make-array 64 (ann 0 I64))))
        (do ((t 0 (+ t 1))) ((= t 64) (array->vector words))
          (array-set! words t (if (< t 16)
                                  (block-word bytes start t)
                                  (wrap (+ (+ (small-sigma1 (array-ref words (- t 2)))
                                              (array-ref words (- t 7)))
                                           (+ (small-sigma0 (array-ref words (- t 15)))
                                              (array-ref words (- t 16))))))))))

    ;; §6.2.2 steps 2 to 4: 64 rounds over eight working words, which are
    ;; then added to the state.
    (: compress (-> (Vector I64) (Vector I64) (Vector I64)))
    (define (compress state words)
      (let rounds ((t 0)
                   (a (vector-ref state 0))
                   (b (vector-ref state 1))
                   (c (vector-ref state 2))
                   (d (vector-ref state 3))
                   (e (vector-ref state 4))
                   (f (vector-ref state 5))
                   (g (vector-ref state 6))
                   (h (vector-ref state 7)))
        (if (= t 64)
            (let ((working (list->vector (list a b c d e f g h))))
              (vector-generate 8
                               (lambda (index)
                                 (wrap (+ (vector-ref state index) (vector-ref working index))))))
            (let ((t1 (+ (+ (+ h (big-sigma1 e)) (choose e f g))
                         (+ (vector-ref round-constants t) (vector-ref words t))))
                  (t2 (+ (big-sigma0 a) (majority a b c))))
              (rounds (+ t 1) (wrap (+ t1 t2)) a b c (wrap (+ d t1)) e f g)))))

    ;; The state after each 64-byte block of `bytes`, from `state`.
    (: compress-blocks (-> (Vector I64) Bytes I64 (Vector I64)))
    (define (compress-blocks state bytes blocks)
      (fold-left (lambda (state block) (compress state (schedule bytes (* 64 block))))
                 state (iota blocks)))

    ;; ---- Digests ----

    ;; The final state's eight words, big-endian.
    (: sha256 (-> Bytes Bytes))
    (define (sha256 message)
      (let* ((tail (tail-blocks message))
             (state (compress-blocks (compress-blocks initial-state
                                                      message
                                                      (quotient (vector-length message) 64))
                                     tail
                                     (quotient (vector-length tail) 64))))
        (vector-generate 32
                         (lambda (index)
                           (i32->u8 (i64->i32 (i64-and (i64-shift-right/logical
                                                        (vector-ref state (quotient index 4))
                                                        (* 8 (- 3 (remainder index 4))))
                                                       255)))))))

    (: bytes->hex (-> Bytes String))
    (define (bytes->hex bytes)
      (string-generate (* 2 (vector-length bytes))
                       (lambda (index)
                         (let ((byte (i32->i64 (u8->i32 (vector-ref bytes (quotient index 2))))))
                           (string-ref "0123456789abcdef"
                                       (if (= (remainder index 2) 0)
                                           (quotient byte 16)
                                           (remainder byte 16)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-sha256)
    (import
     (snail stage0 testing))
    (begin
      ;; The FIPS 180-2 examples, and lengths on either side of the
      ;; padding's block boundaries, where the length moves to a second
      ;; tail block or the message fills a block of its own.
      (define (test-sha256)
        (expect (hex "")
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        (expect (hex "abc")
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        (expect (hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        (expect (hex (make-string 55 #\x))
                "d5e285683cd4efc02d021a5c62014694958901005d6f71e89e0989fac77e4072")
        (expect (hex (make-string 56 #\x))
                "04c26261370ee7541549d16dee320c723e3fd14671e66a099afe0a377c16888e")
        (expect (hex (make-string 64 #\x))
                "7ce100971f64e7001e8fe5a51973ecdfe1ced42befe7ee8d5fd6219506b5393c"))

      (define (hex text)
        (bytes->hex
         (sha256 (list->vector (map (lambda (char) (i32->u8 (i64->i32 (char->integer char))))
                                    (string->list text))))))))))
