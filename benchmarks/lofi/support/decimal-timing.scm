;; ---- Only the untimed control driver is replaced; its worker and predicate remain ----

(set! run-r7rs-benchmark
  (lambda (name count thunk correct?)
    (let ((start (current-time 'time-monotonic)))
      (let loop ((index 0) (result #f))
        (if (< index count)
            (loop (+ index 1) (thunk))
            (begin
              (unless (correct? result)
                (error 'benchmark "complete result differs" result))
              (let* ((finish (current-time 'time-monotonic))
                     (seconds (+ (- (time-second finish) (time-second start))
                                 (/ (- (time-nanosecond finish) (time-nanosecond start))
                                    1000000000.0))))
                (write result)
                (newline)
                (display "+!CSVLINE!+chez,")
                (display name)
                (display ",")
                (display seconds)
                (newline))))))))

(run-benchmark)
