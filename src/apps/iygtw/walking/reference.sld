(define-library (apps iygtw walking reference)
  (export Stride read-stride reference-pose)
  (import
   (snail core base)
   (snail shell math)
   (snail shell little-endian)
   (snail shell resource))
  (begin
    ;; Six joint pitches, pelvis pitch and height, then shoulder/elbow pairs.
    ;; Angles are radians, lengths are metres, and phase 1 wraps to phase 0.
    (record Stride
      ((frames I64)
       (duration F64)
       (length F64)
       (samples (Array F64))))
    (define (read-stride (resources Resources)) (→ Stride)
      (let* ((b (read-resource resources (link-file "stride.bin")))
             (n (if (>= (array-length b) 12) (u16 b 4) (panic "truncated walking reference")))
             (duration (* 0.000001 (i64->f64 (u32 b 6))))
             (length (* 0.001 (i64->f64 (u16 b 10)))))
        (unless (and (= (u32 b 0) 827018327) (> n 1) (> duration 0.0) (> length 0.0)
                     (= (array-length b) (+ 12 (* 24 n))))
          (panic "invalid walking reference"))
        (new Stride (frames n) (duration duration) (length length)
             (samples
              (array-generate (* n 12) (lambda (i) (* 0.001 (i64->f64 (i16 b (+ 12 (* 2 i)))))))))))
    (define (reference-pose (clip Stride) (phase F64)) (→ (Array F64))
      (let* ((time (* (- phase (floor phase)) (i64->f64 (● clip frames))))
             (i (f64->i64 time)) (j (modulo (+ i 1) (● clip frames))) (t (- time (i64->f64 i))))
        (array-generate 12 (lambda (k)
                             (let ((a (array-ref (● clip samples) (+ (* i 12) k)))
                                   (b (array-ref (● clip samples) (+ (* j 12) k))))
                               (+ a (* t (- b a))))))))))
