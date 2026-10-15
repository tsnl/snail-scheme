;; Packed storage stays in WasmGC. Library loops translate bytes and Unicode
;; scalars without exposing a native pointer or crossing a foreign boundary.
(define-library (snail bytes)
  (export Bytevector make-bytevector bytevector bytevector-length
          bytevector-u8-ref bytevector-u8-set! bytevector-eq?
          bytevector-copy bytevector-copy! bytevector-append
          utf8->string string->utf8)
  (import (snail strict)
          (rename (only (snail-scheme core)
                        make-bytevector bytevector-length bytevector-u8-ref
                        bytevector-u8-set! bytevector-eq? bytevector-copy!)
                  (make-bytevector make-filled-bytevector)
                  (bytevector-copy! copy-bytes!)))
  (begin

    ;; ---- Fresh mutable bytes and bounded ranges ----

    (define-overload make-bytevector (-> I64 I64 Bytevector) make-filled-bytevector)
    (define-overload make-bytevector (-> I64 Bytevector)
      (lambda (count) (make-filled-bytevector count 0)))
    (define (bytevector . bytes)
      (let ((result (make-bytevector (byte-count bytes))))
        (let loop ((remaining bytes) (index 0))
          (if (null? remaining) result
              (begin
                (bytevector-u8-set! result index (car remaining))
                (loop (cdr remaining) (+ index 1)))))))
    (define (byte-count bytes)
      (let loop ((remaining bytes) (count 0))
        (if (null? remaining) count
            (if (= count 4294967295) (unreachable)
                (loop (cdr remaining) (+ count 1))))))
    (define (check-range length start end)
      (when (or (< start 0) (or (< end start) (> end length))) (unreachable)))

    ;; Every copy allocates its own mutable owner, even for empty or readonly
    ;; input. The primitive checks both complete ranges before its first store.
    (define-overload bytevector-copy! (-> Bytevector I64 Bytevector I64 I64 Unit) copy-bytes!)
    (define-overload bytevector-copy! (-> Bytevector I64 Bytevector I64 Unit)
      (lambda (target at source start)
        (copy-bytes! target at source start (bytevector-length source))))
    (define-overload bytevector-copy! (-> Bytevector I64 Bytevector Unit)
      (lambda (target at source) (copy-bytes! target at source 0 (bytevector-length source))))
    (define-overload bytevector-copy (-> Bytevector I64 I64 Bytevector)
      (lambda (source start end)
        (check-range (bytevector-length source) start end)
        (let ((result (make-bytevector (- end start))))
          (copy-bytes! result 0 source start end)
          result)))
    (define-overload bytevector-copy (-> Bytevector I64 Bytevector)
      (lambda (source start) (bytevector-copy source start (bytevector-length source))))
    (define-overload bytevector-copy (-> Bytevector Bytevector)
      (lambda (source) (bytevector-copy source 0 (bytevector-length source))))
    (define (bytevector-append . sources)
      (let ((result (make-bytevector (appended-length sources))))
        (let loop ((remaining sources) (at 0))
          (if (null? remaining) result
              (let ((length (bytevector-length (car remaining))))
                (copy-bytes! result at (car remaining) 0 length)
                (loop (cdr remaining) (+ at length)))))))
    (define (appended-length sources)
      ;; Check every prefix; the next addition is at most twice U32_MAX.
      (let loop ((remaining sources) (count 0))
        (if (> count 4294967295) (unreachable)
            (if (null? remaining) count
                (loop (cdr remaining) (+ count (bytevector-length (car remaining))))))))

    ;; ---- Strict UTF-8 decoding ----

    ;; No callbacks or mutation intervene between validation/counting and fill.
    ;; Helpers return scalars; decoding one character allocates no product value.
    ;; Both passes inspect only the selected byte range, including empty slices.
    (define (leading-width byte)
      (if (< byte 128) 1
          (if (and (>= byte 194) (< byte 224)) 2
              (if (and (>= byte 224) (< byte 240)) 3
                  (if (and (>= byte 240) (< byte 245)) 4 (unreachable))))))
    (define (leading-prefix width)
      (if (= width 1) 0 (if (= width 2) 192 (if (= width 3) 224 240))))
    (define (minimum-scalar width)
      (if (= width 1) 0 (if (= width 2) 128 (if (= width 3) 2048 65536))))
    (define (utf8-width source index end)
      (let ((width (leading-width (bytevector-u8-ref source index))))
        (if (> width (- end index)) (unreachable) width)))
    (define (continuation-payload source index)
      (let ((byte (bytevector-u8-ref source index)))
        (if (or (< byte 128) (> byte 191)) (unreachable) (- byte 128))))
    (define (utf8-character source index width)
      (let loop ((offset 1) (scalar (- (bytevector-u8-ref source index) (leading-prefix width))))
        (if (= offset width)
            (if (< scalar (minimum-scalar width)) (unreachable) (integer->char scalar))
            (loop (+ offset 1) (+ (* scalar 64) (continuation-payload source (+ index offset)))))))
    (define (decoded-length source start end)
      (let loop ((index start) (count 0))
        (if (= index end) count
            (let ((width (utf8-width source index end)))
              (utf8-character source index width)
              (loop (+ index width) (+ count 1))))))
    (define (decode-into! target source start end)
      (let loop ((index start) (at 0))
        (unless (= index end)
          (let ((width (utf8-width source index end)))
            (string-set! target at (utf8-character source index width))
            (loop (+ index width) (+ at 1))))))
    (define-overload utf8->string (-> Bytevector I64 I64 String)
      (lambda (source start end)
        (check-range (bytevector-length source) start end)
        (let ((result (make-string (decoded-length source start end))))
          (decode-into! result source start end)
          result)))
    (define-overload utf8->string (-> Bytevector I64 String)
      (lambda (source start) (utf8->string source start (bytevector-length source))))
    (define-overload utf8->string (-> Bytevector String)
      (lambda (source) (utf8->string source 0 (bytevector-length source))))

    ;; ---- UTF-8 encoding from Unicode scalars ----

    ;; String indices count scalars. Count bytes before allocating the exact
    ;; result; all additions are bounded before the next character is visited.
    (define (scalar-width scalar)
      (if (< scalar 128) 1 (if (< scalar 2048) 2 (if (< scalar 65536) 3 4))))
    (define (encoded-length source start end)
      (let loop ((index start) (count 0))
        (if (> count 4294967295) (unreachable)
            (if (= index end) count
                (loop (+ index 1) (+ count (scalar-width (char->integer (string-ref source index)))))))))
    (define (encode-character! target at scalar width)
      (let loop ((remaining width) (payload scalar))
        (if (= remaining 1)
            (bytevector-u8-set! target at (+ (leading-prefix width) payload))
            (begin
              (bytevector-u8-set! target (+ at (- remaining 1)) (+ 128 (remainder payload 64)))
              (loop (- remaining 1) (quotient payload 64))))))
    (define (encode-into! target source start end)
      (let loop ((index start) (at 0))
        (unless (= index end)
          (let* ((scalar (char->integer (string-ref source index))) (width (scalar-width scalar)))
            (encode-character! target at scalar width)
            (loop (+ index 1) (+ at width))))))
    (define-overload string->utf8 (-> String I64 I64 Bytevector)
      (lambda (source start end)
        (check-range (string-length source) start end)
        (let ((result (make-bytevector (encoded-length source start end))))
          (encode-into! result source start end)
          result)))
    (define-overload string->utf8 (-> String I64 Bytevector)
      (lambda (source start) (string->utf8 source start (string-length source))))
    (define-overload string->utf8 (-> String Bytevector)
      (lambda (source) (string->utf8 source 0 (string-length source))))))
