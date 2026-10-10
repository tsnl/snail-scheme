(import (scheme base) (scheme write))

;; Finalizers release Rust payloads after the outermost Wasm call returns.
;; Allocating while Host is borrowed must queue cleanup without reentering Rust.
(let loop ((count 1000))
  (when (> count 0)
    (let ((port (open-output-string)))
      (write (make-vector 16 count) port))
    (loop (- count 1))))
(display "native resource checks passed\n")
