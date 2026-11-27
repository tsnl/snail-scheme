;; Read Radiance RGBE headers and bound every run before allocating or decoding pixels.
(define-library (snail shell graphics environment)
  (export Hdr read-hdr)
  (import
   (snail core base))
  (begin
    ;; A file: its size, its bytes, and where each row starts, as
    ;; little-endian words.
    (record Hdr
      ((width I64)
       (height I64)
       (bytes Bytes)
       (rows Bytes)))

    ;; The header is lines up to an empty one, then the size as
    ;; `-Y height +X width`, rows top down; each row is run-length
    ;; encoded, starting 2, 2 and its width.
    (define (read-hdr (bytes Bytes)) (→ (Result Hdr String))
      (match (blank-line bytes 0)
        ((None) (Err "no end to the header"))
        ((Some at)
         (match (size-line bytes at)
           ((None) (Err "the size is not -Y height +X width"))
           ((Some (Pair size data))
            (let ((width (● size second)) (height (● size first)))
              (if (or (< width 8) (> width 32767) (< height 1))
                  (Err "rows this wide are not run-length encoded")
                  (match (row-starts bytes data width height)
                    ((Some rows)
                     (Ok (new Hdr (width width) (height height) (bytes bytes) (rows rows))))
                    ((None) (Err "a row is not run-length encoded"))))))))))

    (define (byte-at (bytes Bytes) (index I64)) (→ I64)
      (if (< index (array-length bytes)) (i32->i64 (u8->i32 (array-ref bytes index))) -1))

    ;; Just past the first "\n\n".
    (define (blank-line (bytes Bytes) (from I64)) (→ (Option I64))
      (cond ((>= (+ from 1) (array-length bytes)) (None))
            ((and (= (byte-at bytes from) 10) (= (byte-at bytes (+ from 1)) 10)) (Some (+ from 2)))
            (else (blank-line bytes (+ from 1)))))

    ;; The height and width, and where the pixels start.
    (define (size-line (bytes Bytes) (at I64)) (→ (Option (Pair (Pair I64 I64) I64)))
      (match (after-text bytes at "-Y ")
        ((Some at)
         (let ((height (digits bytes at 0)))
           (match (after-text bytes (● height second) " +X ")
             ((Some at)
              (let ((width (digits bytes at 0)))
                (if (= (byte-at bytes (● width second)) 10)
                    (Some (new Pair
                            (first (new Pair (first (● height first)) (second (● width first))))
                            (second (+ 1 (● width second)))))
                    (None))))
             ((None) (None)))))
        ((None) (None))))

    (define (after-text (bytes Bytes) (at I64) (text String)) (→ (Option I64))
      (let ((chars (string->array text)))
        (if (fold-left (lambda (same index)
                         (and same
                              (= (byte-at bytes (+ at index))
                                 (char->integer (array-ref chars index)))))
                       #t
                       (iota (array-length chars)))
            (Some (+ at (array-length chars)))
            (None))))

    ;; The number written at `at`, and where it ends.
    (define (digits (bytes Bytes) (at I64) (value I64)) (→ (Pair I64 I64))
      (let ((byte (byte-at bytes at)))
        (if (and (>= byte 48) (<= byte 57))
            (digits bytes (+ at 1) (+ (* value 10) (- byte 48)))
            (new Pair (first value) (second at)))))

    ;; Each row's start, found by stepping over its runs: four channels,
    ;; each `width` pixels of runs.
    (define (row-starts (bytes Bytes) (data I64) (width I64) (height I64)) (→ (Option Bytes))
      (let walk ((row 0) (at data) (starts (Nil)))
        (cond ((= row height) (Some (words (list->array (reverse starts)))))
              ((not (row-begins? bytes at width)) (None))
              (else (let ((end (channels-end bytes (+ at 4) width 4)))
                      (if (< end 0) (None) (walk (+ row 1) end (Cons at starts))))))))

    ;; Little-endian words.
    (define (words (values (Array I64))) (→ Bytes)
      (array-generate (* 4 (array-length values))
                      (lambda ((index I64)) (→ U8)
                        (i32->u8
                         (i64->i32 (remainder (quotient (array-ref values (quotient index 4))
                                                        (expt-256 (remainder index 4)))
                                              256))))))

    (define (row-begins? (bytes Bytes) (at I64) (width I64)) (→ Bool)
      (and (= (byte-at bytes at) 2)
           (= (byte-at bytes (+ at 1)) 2)
           (= (+ (* 256 (byte-at bytes (+ at 2))) (byte-at bytes (+ at 3))) width)))

    (define (channels-end (bytes Bytes) (at I64) (width I64) (left I64)) (→ I64)
      (if (or (= left 0) (< at 0))
          at
          (channels-end bytes (runs-end bytes at width) width (- left 1))))

    ;; Past the runs of one channel: a count over 128 repeats one byte, a
    ;; count up to 128 is that many bytes.
    (define (runs-end (bytes Bytes) (at I64) (left I64)) (→ I64)
      (if (= left 0) at
          (let* ((count (byte-at bytes at)) (repeat (> count 128))
                 (n (if repeat (- count 128) count)) (next (+ at (+ 1 (if repeat 1 n)))))
            (if (or (<= n 0) (> n left) (> next (array-length bytes))) -1
                (runs-end bytes next (- left n))))))

    (define (expt-256 (k I64)) (→ I64) (if (= k 0) 1 (* 256 (expt-256 (- k 1)))))
    ))
