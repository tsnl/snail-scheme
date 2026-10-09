;; Explicit runtime extensions used by host-heavy and collector benchmarks.
(define-library (snail-scheme runtime)
  (export string-contains collect-garbage gc-statistics)
  (import (only (snail-scheme core) string-contains collect-garbage gc-statistics)))
