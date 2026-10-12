(define-library (scheme time)
  (export current-second current-jiffy jiffies-per-second)
  (import (only (snail-scheme core) current-second current-jiffy jiffies-per-second)))
