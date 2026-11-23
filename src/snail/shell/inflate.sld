;; DEFLATE streams, as RFC 1951 defines them, decompressed: the format a
;; zip archive's members, gzip files and PNG images keep their bytes in.
;; A stream is a run of blocks, each one stored as it is or coded with two
;; Huffman codes, one for literal bytes, the block's end and the lengths
;; of copies, the other for how far back a copy starts. A fixed block uses
;; the codes the standard gives; a dynamic one sends its own first.
;;
;; `inflate` decodes the stream at a byte of its input into exactly the
;; number of bytes it must make, as a zip archive's directory gives it. The
;; input is a stream of bits, each byte's lowest first, and a bit's place
;; in it is threaded through every step, so decoding allocates nothing but
;; its output and each block's codes. The output is written front to back
;; by the loops that own it. A stream that breaks the format, or makes
;; more or fewer bytes than it should, answers why.
(define-library (snail shell inflate)
  (export
   inflate)
  (import
   (snail core base))
  (begin

    ;; ---- Bits ----

    ;; `count` bits, at most 25, from bit `at` of the input, the first the
    ;; value's lowest. Past the input's end every bit is 0: the decoder
    ;; checks where it ended.

    (define (bits (input Bytes) (at I64) (count I64)) (→ I64)
      (i64-and
       (i64-shift-right/logical (window input (i64-shift-right/logical at 3)) (i64-and at 7))
       (- (i64-shift-left 1 count) 1)))

    ;; The four bytes from byte `index` on, as one number, the first lowest.

    (define (window (input Bytes) (index I64)) (→ I64)
      (i64-or (i64-or (input-byte input index) (i64-shift-left (input-byte input (+ index 1)) 8))
              (i64-or (i64-shift-left (input-byte input (+ index 2)) 16)
                      (i64-shift-left (input-byte input (+ index 3)) 24))))

    (define (input-byte (input Bytes) (index I64)) (→ I64)
      (if (< index (array-length input)) (i32->i64 (u8->i32 (array-ref input index))) 0))

    ;; ---- Failures ----

    ;; A stream that breaks the format stops the decoding. Nothing resumes
    ;; a failure, so failing saves no frames; `inflate` turns it into its
    ;; Result.
    (define corrupt (→ (Prompt String Never)) (make-prompt))

    (define (fail (why String)) (→ A) (∀ (A))
      (absurd (suspend corrupt why)))

    ;; ---- Codes ----

    ;; A Huffman code, made from the length of each symbol's code, which is
    ;; all a block sends: the codes of one length are consecutive numbers,
    ;; in the order of their symbols, and each length's come after the
    ;; shorter ones', so the lengths say every code. A code arrives first
    ;; bit first. `fast` gives, for each value of the next `fast-bits` bits,
    ;; the symbol whose code they begin with and the code's length, as
    ;; symbol × 16 + length, for every code no longer than that; a longer
    ;; code's entries are 0, and it is read a bit at a time from `counts`,
    ;; how many codes each length has, and `symbols`, the symbols in the
    ;; order of their codes.
    (record Code
      ((fast (Array I64))
       (counts (Array I64))
       (symbols (Array I64))))

    (define fast-bits (→ I64) 10)

    ;; The code whose symbols have `lengths`, a length of 0 being no code.
    ;; Lengths that ask for more codes than there are fail; fewer are
    ;; allowed, as a block with a single distance sends.

    (define (make-code (lengths (Array I64))) (→ Code)
      (let ((counts (length-counts lengths)))
        (when (oversubscribed? counts)
          (fail "a block's code lengths ask for more codes than there are"))
        (new Code
          (fast (fast-table lengths counts))
          (counts counts)
          (symbols (code-order lengths counts)))))

    (define (length-counts (lengths (Array I64))) (→ (Array I64))
      (let ((counts (make-array 16 0)))
        (array-for-each (lambda (length)
                          (when (> length 0)
                            (array-set! counts length (+ (array-ref counts length) 1))))
                        lengths)
        counts))

    ;; Of the 2^L codes of length L, those that do not begin with a shorter
    ;; code are left for length L.

    (define (oversubscribed? (counts (Array I64))) (→ Bool)
      (let loop ((length 1) (left 2))
        (let ((left (- left (array-ref counts length))))
          (cond ((< left 0) #t)
                ((= length 15) #f)
                (else (loop (+ length 1) (* left 2)))))))

    ;; The symbols by the length of their codes, then by symbol.

    (define (code-order (lengths (Array I64)) (counts (Array I64))) (→ (Array I64))
      (let ((next (make-array 16 0))
            (symbols (make-array (array-fold (lambda (sum count) (+ sum count)) 0 counts) 0)))
        (let loop ((length 1))
          (when (< length 15)
            (array-set! next (+ length 1) (+ (array-ref next length) (array-ref counts length)))
            (loop (+ length 1))))
        (each-coded lengths
                    (lambda (symbol length)
                      (array-set! symbols (array-ref next length) symbol)
                      (array-set! next length (+ (array-ref next length) 1))))
        symbols))

    ;; Calls `visit` with each symbol that has a code and the code's
    ;; length, in the order of the symbols.

    (define (each-coded (lengths (Array I64)) (visit (Fn I64 I64 → Unit))) (→ Unit)
      (let loop ((symbol 0))
        (when (< symbol (array-length lengths))
          (when (> (array-ref lengths symbol) 0) (visit symbol (array-ref lengths symbol)))
          (loop (+ symbol 1)))))

    ;; Each length's first code: one past the last code of the length
    ;; before it, doubled.

    (define (first-codes (counts (Array I64))) (→ (Array I64))
      (let ((firsts (make-array 16 0)))
        (let loop ((length 1) (code 0))
          (when (< length 16)
            (let ((code (* (+ code (array-ref counts (- length 1))) 2)))
              (array-set! firsts length code)
              (loop (+ length 1) code))))
        firsts))

    ;; A code reaches the table first bit first, the lowest of the next
    ;; bits, so its entries are at the code's bits reversed, with every
    ;; value of the bits that follow it.

    (define (fast-table (lengths (Array I64)) (counts (Array I64))) (→ (Array I64))
      (let ((fast (make-array (i64-shift-left 1 fast-bits) 0)) (next (first-codes counts)))
        (each-coded lengths
                    (lambda (symbol length)
                      (let ((code (array-ref next length)))
                        (array-set! next length (+ code 1))
                        (when (<= length fast-bits)
                          (let loop ((index (reversed code length)))
                            (when (< index (array-length fast))
                              (array-set! fast index (+ (* symbol 16) length))
                              (loop (+ index (i64-shift-left 1 length)))))))))
        fast))

    (define (reversed (code I64) (length I64)) (→ I64)
      (let loop ((code code) (length length) (result 0))
        (if (= length 0)
            result
            (loop (i64-shift-right/logical code 1)
                  (- length 1)
                  (i64-or (* result 2) (i64-and code 1))))))

    ;; The symbol whose code begins at bit `at`, and the code's length, as
    ;; symbol × 16 + length.

    (define (decode (code Code) (input Bytes) (at I64)) (→ I64)
      (let ((entry (array-ref (● code fast) (bits input at fast-bits))))
        (if (> entry 0) entry (decode-slowly code input at))))

    ;; A code longer than the table's, a bit at a time: the codes of each
    ;; length run on from that length's first, so a value fewer than the
    ;; length's count past its first is one of its codes.

    (define (decode-slowly (code Code) (input Bytes) (at I64)) (→ I64)
      (let loop ((length 1) (value (bits input at 1)) (first 0) (index 0))
        (let ((count (array-ref (● code counts) length)))
          (cond ((< (- value first) count)
                 (+ (* (array-ref (● code symbols) (+ index (- value first))) 16) length))
                ((= length 15) (fail "a block holds a code its Huffman code does not have"))
                (else (loop (+ length 1)
                            (i64-or (* value 2) (bits input (+ at length) 1))
                            (* (+ first count) 2)
                            (+ index count)))))))

    ;; The fixed block's codes: literal and length symbols 0 to 143 in 8
    ;; bits, 144 to 255 in 9, 256 to 279 in 7 and 280 to 287 in 8; every
    ;; distance in 5.

    (define fixed-literals (→ Code)
      (make-code (array-generate 288
                                 (lambda (symbol)
                                   (cond ((< symbol 144) 8)
                                         ((< symbol 256) 9)
                                         ((< symbol 280) 7)
                                         (else 8))))))

    (define fixed-distances (→ Code)
      (make-code (make-array 30 5)))

    ;; ---- Copies ----

    ;; Length symbols 257 to 285 and distance symbols 0 to 29: how many
    ;; bits follow each, to add to the least it says. Each symbol's least is
    ;; one past the most the symbol before it says, from 3 for lengths and
    ;; 1 for distances, but for length 258, which has a symbol of its own.

    (define length-extras (→ (ConstantArray I64))
      (constant-array I64 (0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)))

    (define distance-extras (→ (ConstantArray I64))
      (constant-array I64 (0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

    (define length-bases (→ (Array I64))
      (array-set (least-amounts 3 length-extras) 28 258))

    (define distance-bases (→ (Array I64))
      (least-amounts 1 distance-extras))

    (define (least-amounts (first I64) (extras (ConstantArray I64))) (→ (Array I64))
      (let ((least (make-array (constant-array-length extras) first)))
        (let loop ((k 1))
          (when (< k (array-length least))
            (array-set! least
                        k
                        (+ (array-ref least (- k 1))
                           (i64-shift-left 1 (constant-array-ref extras (- k 1)))))
            (loop (+ k 1))))
        least))

    ;; The length or distance that symbol `index` begins at bit `at`, whose
    ;; extra bits follow it.

    (define (copy-amount (bases (Array I64)) (extras (ConstantArray I64))
                         (input Bytes)
                         (at I64)
                         (index I64))
      (→ I64)
      (+ (array-ref bases index) (bits input at (constant-array-ref extras index))))

    ;; `length` bytes from `distance` back. A copy that overlaps what it
    ;; writes repeats it, so it goes a byte at a time; one that does not is
    ;; one move.

    (define (copy! (output Bytes) (written I64) (distance I64) (length I64)) (→ Unit)
      (when (> distance written) (fail "a copy reaches back before the stream's start"))
      (when (> (+ written length) (array-length output)) (too-long))
      (if (>= distance length)
          (array-copy! output written output (- written distance) length)
          (let loop ((k 0))
            (when (< k length)
              (array-set! output (+ written k) (array-ref output (+ (- written distance) k)))
              (loop (+ k 1))))))

    (define (too-long) (→ A) (∀ (A))
      (fail "the stream makes more bytes than it should"))

    ;; ---- Blocks ----

    ;; Where a block ends: the bit after it, and how many bytes of the
    ;; output are written.
    (record Place
      ((at I64)
       (written I64)))

    ;; A coded block's symbols up to its end: a literal is a byte, 256 is
    ;; the end, and 257 to 285 are lengths, each followed by a distance;
    ;; together they copy what was written before. Bits past the input's
    ;; end read as 0, so each symbol, and each copy, is checked to have
    ;; ended within it before it is used.

    (define (symbols! (input Bytes) (output Bytes) (literals Code) (distances Code) (place Place))
      (→ Place)
      (let loop ((at (● place at)) (written (● place written)))
        (let* ((entry (decode literals input at))
               (symbol (i64-shift-right/logical entry 4))
               (at (within input (+ at (i64-and entry 15)))))
          (cond ((< symbol 256)
                 (when (>= written (array-length output)) (too-long))
                 (array-set! output written (i32->u8 (i64->i32 symbol)))
                 (loop at (+ written 1)))
                ((= symbol 256) (new Place (at at) (written written)))
                ((> symbol 285) (fail "a block holds a length symbol of no length"))
                (else
                 (let* ((index (- symbol 257))
                        (length (copy-amount length-bases length-extras input at index))
                        (at (+ at (constant-array-ref length-extras index)))
                        (entry (decode distances input at))
                        (code (i64-shift-right/logical entry 4))
                        (at (+ at (i64-and entry 15)))
                        (distance (copy-amount distance-bases distance-extras input at code))
                        (at (within input (+ at (constant-array-ref distance-extras code)))))
                   (copy! output written distance length)
                   (loop at (+ written length))))))))

    (define (within (input Bytes) (at I64)) (→ I64)
      (if (> at (* (array-length input) 8)) (fail "the stream ends inside a block") at))

    ;; A stored block starts at the next byte: its length in two bytes,
    ;; their complement, then that many bytes as they are.

    (define (stored! (input Bytes) (output Bytes) (place Place)) (→ Place)
      (let* ((from (+ (quotient (+ (● place at) 7) 8) 4))
             (length (bits input (* (- from 4) 8) 16))
             (written (● place written)))
        (unless (= (i64-xor length (bits input (* (- from 2) 8) 16)) 65535)
          (fail "a stored block's length and its complement disagree"))
        (when (> (+ from length) (array-length input)) (fail "the stream ends inside a block"))
        (when (> (+ written length) (array-length output)) (too-long))
        (array-copy! output written input from length)
        (new Place (at (* (+ from length) 8)) (written (+ written length)))))

    ;; A dynamic block sends its codes before its symbols: how many literal
    ;; and length codes (257 to 286) and distance codes (1 to 30) it has,
    ;; and how many lengths of the code lengths' own code (4 to 19), three
    ;; bits each in a fixed order; then every literal's and distance's
    ;; code length, coded by that code.

    (define (dynamic! (input Bytes) (output Bytes) (place Place)) (→ Place)
      (let* ((at (● place at))
             (literals (+ (bits input at 5) 257))
             (distances (+ (bits input (+ at 5) 5) 1))
             (sent (+ (bits input (+ at 10) 4) 4)))
        (when (or (> literals 286) (> distances 30)) (fail "a block has more codes than symbols"))
        (let* ((read (code-lengths input
                                   (length-code input (+ at 14) sent)
                                   (+ literals distances)
                                   (+ at (+ 14 (* 3 sent)))))
               (lengths (● read lengths)))
          (when (= (array-ref lengths 256) 0) (fail "a block's code has no end"))
          (symbols! input
                    output
                    (make-code (subarray lengths 0 literals))
                    (make-code (subarray lengths literals (+ literals distances)))
                    (new Place (at (● read at)) (written (● place written)))))))

    (define length-order (→ (ConstantArray I64))
      (constant-array I64 (16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)))

    (define (length-code (input Bytes) (at I64) (sent I64)) (→ Code)
      (let ((lengths (make-array 19 0)))
        (let loop ((k 0))
          (when (< k sent)
            (array-set! lengths (constant-array-ref length-order k) (bits input (+ at (* 3 k)) 3))
            (loop (+ k 1))))
        (make-code lengths)))

    ;; The lengths a dynamic block sends, and the bit after them. Symbols
    ;; 0 to 15 are lengths; 16 repeats the last length 3 to 6 times, 17
    ;; gives 3 to 10 zeros and 18 gives 11 to 138, as their extra bits say.
    (record Lengths
      ((lengths (Array I64))
       (at I64)))

    (define (code-lengths (input Bytes) (code Code) (count I64) (at I64)) (→ Lengths)
      (let ((lengths (make-array count 0)))
        (let loop ((k 0) (at at))
          (if (>= k count)
              (new Lengths (lengths lengths) (at at))
              (let* ((entry (decode code input at))
                     (symbol (i64-shift-right/logical entry 4))
                     (at (+ at (i64-and entry 15))))
                (if (< symbol 16)
                    (begin (array-set! lengths k symbol) (loop (+ k 1) at))
                    (let* ((extra (cond ((= symbol 16) 2) ((= symbol 17) 3) (else 7)))
                           (times (+ (cond ((= symbol 18) 11) (else 3)) (bits input at extra))))
                      (when (> (+ k times) count)
                        (fail "a block's code lengths run past its codes"))
                      (when (and (= symbol 16) (= k 0))
                        (fail "a block repeats a length before any"))
                      (fill! lengths k times (if (= symbol 16) (array-ref lengths (- k 1)) 0))
                      (loop (+ k times) (+ at extra)))))))))

    (define (fill! (lengths (Array I64)) (from I64) (times I64) (length I64)) (→ Unit)
      (let loop ((k 0))
        (when (< k times)
          (array-set! lengths (+ from k) length)
          (loop (+ k 1)))))

    ;; ---- Streams ----

    ;; Type 0 is stored, 1 coded by the fixed codes, 2 by codes the block
    ;; sends; 3 is no type.

    (define (block! (input Bytes) (output Bytes) (type I64) (place Place)) (→ Place)
      (cond ((= type 0) (stored! input output place))
            ((= type 1) (symbols! input output fixed-literals fixed-distances place))
            ((= type 2) (dynamic! input output place))
            (else (fail "a block of no type"))))

    ;; Each block begins with a bit that says whether it is the last, and
    ;; two that give its type.

    (define (inflated (input Bytes) (start I64) (size I64)) (→ Bytes)
      (let ((output (make-array size (i32->u8 0))))
        (let loop ((place (new Place (at (* start 8)) (written 0))))
          (let* ((at (● place at))
                 (next (block! input
                               output
                               (bits input (+ at 1) 2)
                               (new Place (at (+ at 3)) (written (● place written))))))
            (if (= (bits input at 1) 0)
                (loop next)
                (begin
                  (unless (= (● next written) size)
                    (fail "the stream makes fewer bytes than it should"))
                  output))))))

    ;; The `size` bytes the stream at byte `start` of `input` makes.

    (define (inflate (input Bytes) (start I64) (size I64)) (→ (Result Bytes String))
      (with-prompt corrupt
                   (lambda () (Ok (inflated input start size)))
                   (lambda (why resume) (Err why))))

    ))
