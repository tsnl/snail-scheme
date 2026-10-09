(define-library (scheme time)
  (export current-jiffy jiffies-per-second)
  (import (only (snail-scheme core) current-jiffy jiffies-per-second)))
