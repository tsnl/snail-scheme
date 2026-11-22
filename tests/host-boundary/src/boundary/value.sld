(define-library (boundary value)
  (export
   Payload
   later)
  (import
   (snail core base)
   (snail core io))
  (begin

    (record Payload
      ((number I32)
       (bytes Bytes)))

    (define (buffer (count I32)) (→ (Array U8))
      (make-array (i32->i64 count) (i32->u8 0)))

    ;; The host calls this to fill the buffer it was handed, and a library's
    ;; exposure is handed nothing by a target, so it makes its own `Mut`.
    (define (put! (target (Array U8)) (index I32) (byte I32)) (→ Unit)
      (array-set! (unsafe-mut) target (i32->i64 index) (i32->u8 byte)))

    (define (finish (number I32) (bytes (Array U8))) (→ (Result Payload String))
      (if (< number 0)
          (Err "rejected")
          (Ok (new Payload (number number) (bytes (array-copy bytes))))))

    ;; A function that needs a capability of the target's, which the program
    ;; exposes: its wrapper, which asks the target for it, is the program's.
    (define (later (clock Clock) (base I64)) (→ I64)
      (if (>= (monotonic-nanoseconds clock) 0) (+ base 1) base))

    (expose buffer "payload-buffer")
    (expose put! "payload-put")
    (expose finish "payload-finish")))
