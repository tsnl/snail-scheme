;; Components and arithmetic live in WasmGC; polar operations use Rust math.
(define-library (scheme complex)
  (export make-rectangular make-polar real-part imag-part magnitude angle)
  (import (only (snail-scheme core)
                make-rectangular make-polar real-part imag-part magnitude angle)))
