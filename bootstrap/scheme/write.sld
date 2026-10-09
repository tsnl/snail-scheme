(define-library (scheme write)
  (export display write (rename write write-simple))
  (import (only (snail-scheme core) display write)))
