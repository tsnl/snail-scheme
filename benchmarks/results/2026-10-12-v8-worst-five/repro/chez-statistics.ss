(import (chezscheme))

;; ---- Allocation and collection statistics for an existing program ----

(define (seconds duration)
  (+ (time-second duration) (/ (time-nanosecond duration) 1000000000.0)))

(define arguments (command-line))
(define before (statistics))
(parameterize ((current-input-port (open-input-file (caddr arguments))))
  (load (cadr arguments)))
(define delta (sstats-difference (statistics) before))
(printf "+!CHEZ-STATS!+{\"allocated_bytes\":~s,\"gc_count\":~s,\"cpu_seconds\":~s,\"real_seconds\":~s,\"gc_cpu_seconds\":~s,\"gc_real_seconds\":~s}\n"
        (sstats-bytes delta) (sstats-gc-count delta)
        (seconds (sstats-cpu delta)) (seconds (sstats-real delta))
        (seconds (sstats-gc-cpu delta)) (seconds (sstats-gc-real delta)))
