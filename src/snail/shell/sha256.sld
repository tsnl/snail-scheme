;; SHA-256, as FIPS 180-4 defines it, over a whole byte vector, and digests
;; as the lowercase hex Node's `digest('hex')` writes. The words are I32:
;; `+` on I32 is Wasm's i32.add, which wraps modulo 2^32 as the standard's
;; addition does, and every right shift is the logical one, so a word with
;; its high bit set behaves as the unsigned word it stands for.
(define-library (snail shell sha256)
  (export
   sha256
   bytes->hex)
  (import
   (snail core base))
  (begin

    ;; ---- Constants ----

    (: hex-value (-> Char I32))
    (define (hex-value char)
      (let ((code (char->i32 char)))
        (if (<= code 57) (- code 48) (- code 87))))

    ;; Words written as the standard prints them: eight lowercase hex
    ;; digits each, one space after every word.
    (: hex-words (-> String (Vector I32)))
    (define (hex-words text)
      (vector-generate (quotient (string-length text) 9)
                       (lambda (word)
                         (fold-left (lambda (value digit)
                                      (i32-or (i32-shift-left value 4)
                                              (hex-value (string-ref text (+ (* word 9) digit)))))
                                    0 (iota 8)))))

    ;; §5.3.3: the first 32 bits of the fractional parts of the square
    ;; roots of the first eight primes.
    (: initial-state (Vector I32))
    (define initial-state
      (hex-words "6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19 "))

    ;; §4.2.2: the first 32 bits of the fractional parts of the cube roots
    ;; of the first 64 primes.
    (: round-constants (Vector I32))
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
    (: rotate (-> I32 I32 I32))
    (define (rotate word count)
      (i32-or (i32-shift-right/logical word count) (i32-shift-left word (- 32 count))))

    (: big-sigma0 (-> I32 I32))
    (define (big-sigma0 word)
      (i32-xor (i32-xor (rotate word 2) (rotate word 13)) (rotate word 22)))

    (: big-sigma1 (-> I32 I32))
    (define (big-sigma1 word)
      (i32-xor (i32-xor (rotate word 6) (rotate word 11)) (rotate word 25)))

    (: small-sigma0 (-> I32 I32))
    (define (small-sigma0 word)
      (i32-xor (i32-xor (rotate word 7) (rotate word 18)) (i32-shift-right/logical word 3)))

    (: small-sigma1 (-> I32 I32))
    (define (small-sigma1 word)
      (i32-xor (i32-xor (rotate word 17) (rotate word 19)) (i32-shift-right/logical word 10)))

    ;; Each bit of `x` chooses between the bits of `y` and `z`.
    (: choose (-> I32 I32 I32 I32))
    (define (choose x y z)
      (i32-xor (i32-and x y) (i32-and (i32-xor x -1) z)))

    ;; Each bit is the majority of three.
    (: majority (-> I32 I32 I32 I32))
    (define (majority x y z)
      (i32-xor (i32-xor (i32-and x y) (i32-and x z)) (i32-and y z)))

    ;; ---- Padding ----

    ;; §5.1.1: the message, one 1 bit, zeros, and the message's length in
    ;; bits as a 64-bit big-endian integer, filling whole 64-byte blocks.
    (: pad (-> Bytes Bytes))
    (define (pad message)
      (let* ((length (vector-length message))
             (total (* 64 (quotient (+ length 72) 64)))
             (bits (* 8 length)))
        (vector-generate total
                         (lambda (index)
                           (cond ((< index length) (vector-ref message index))
                                 ((= index length) (i32->u8 128))
                                 ((< index (- total 8)) (i32->u8 0))
                                 (else (i32->u8 (i64->i32 (i64-shift-right/logical bits
                                                                                   (* 8
                                                                                      (- (- total 1)
                                                                                         index)))))))))))

    ;; ---- Compression ----

    (: block-word (-> Bytes I64 I64 I32))
    (define (block-word bytes block word)
      (fold-left (lambda (value index)
                   (i32-or (i32-shift-left value 8)
                           (u8->i32 (vector-ref bytes (+ (* 64 block) (+ (* 4 word) index))))))
                 0 (iota 4)))

    ;; §6.2.2 step 1: the block's sixteen words, then 48 more, each from
    ;; four earlier ones. The array is local to this call.
    (: schedule (-> Bytes I64 (Vector I32)))
    (define (schedule bytes block)
      (let ((words (make-array 64 (ann 0 I32))))
        (do ((t 0 (+ t 1))) ((= t 64) (array->vector words))
          (array-set! words t (if (< t 16)
                                  (block-word bytes block t)
                                  (+ (+ (small-sigma1 (array-ref words (- t 2)))
                                        (array-ref words (- t 7)))
                                     (+ (small-sigma0 (array-ref words (- t 15)))
                                        (array-ref words (- t 16)))))))))

    ;; §6.2.2 steps 2 to 4: 64 rounds over eight working words, which are
    ;; then added to the state.
    (: compress (-> (Vector I32) (Vector I32) (Vector I32)))
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
                                 (+ (vector-ref state index) (vector-ref working index)))))
            (let ((t1 (+ (+ (+ h (big-sigma1 e)) (choose e f g))
                         (+ (vector-ref round-constants t) (vector-ref words t))))
                  (t2 (+ (big-sigma0 a) (majority a b c))))
              (rounds (+ t 1) (+ t1 t2) a b c (+ d t1) e f g)))))

    ;; ---- Digests ----

    ;; The final state's eight words, big-endian.
    (: sha256 (-> Bytes Bytes))
    (define (sha256 message)
      (let* ((padded (pad message))
             (state (fold-left (lambda (state block) (compress state (schedule padded block)))
                               initial-state (iota (quotient (vector-length padded) 64)))))
        (vector-generate 32
                         (lambda (index)
                           (i32->u8 (i32-shift-right/logical (vector-ref state (quotient index 4))
                                                             (i64->i32
                                                              (* 8 (- 3 (remainder index 4))))))))))

    (: bytes->hex (-> Bytes String))
    (define (bytes->hex bytes)
      (string-generate (* 2 (vector-length bytes))
                       (lambda (index)
                         (let ((byte (u8->i32 (vector-ref bytes (quotient index 2)))))
                           (string-ref "0123456789abcdef"
                                       (i32->i64 (if (= (remainder index 2) 0)
                                                     (i32-shift-right/logical byte 4)
                                                     (i32-and byte 15))))))))

    ))
