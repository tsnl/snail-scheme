;; Timed builds leave these counters off. A separate run measures the part
;; of a workload spent tracing and sweeping, as well as the largest pause.
(define-library (bench heap)
  (export with-heap-profile)
  (import
   (snail core base)
   (snail core io))
  (begin
    (extern enable! "snail.core.support" "snail:gc/profile" (Fn I32 → Unit))
    (extern collections "snail.core.support" "snail:gc/collections" (Fn → I32))
    (extern objects "snail.core.support" "snail:gc/profile-allocations" (Fn → I64))
    (extern bytes "snail.core.support" "snail:gc/profile-bytes" (Fn → I64))
    (extern pauses "snail.core.support" "snail:gc/pause-ns" (Fn → I64))
    (extern longest "snail.core.support" "snail:gc/longest-pause-ns" (Fn → I64))
    (extern now "snail.core.support" "snail:clock/monotonic" (Fn → I64))

    (define (with-heap-profile (out OutputPort) (work (Fn → Unit))) (→ Unit)
      (enable! (i64->i32 1))
      (let ((before (collections)) (start (now)))
        (work)
        (let* ((elapsed (- (now) start)) (count (- (i32->i64 (collections)) (i32->i64 before)))
               (total (pauses)) (worst (longest)) (allocated (objects)) (size (bytes)))
          (enable! (i64->i32 0))
          (write-line out
                      (string-join (map i64->string (list elapsed total worst count allocated size))
                                   " ")))))))
