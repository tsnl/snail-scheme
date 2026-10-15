(import (scheme base) (scheme write) (scheme file))

;; Exercise the WASI file services used by ordinary programs and library lookup.
(unless (and (file-exists? "Cargo.toml")
             (not (file-exists? "build/native-tests/no-such-library.sld")))
  (error "native file status differs"))
(call-with-output-file "build/native-tests/resource-check.txt"
  (lambda (port) (display "native λ\n" port)))
(call-with-input-file "build/native-tests/resource-check.txt"
  (lambda (port)
    (unless (equal? (read-string 9 port) "native λ\n")
      (error "native file contents differ"))))

;; Finalizers release Rust payloads after the outermost Wasm call returns.
;; Allocating while Host is borrowed must queue cleanup without reentering Rust.
(let loop ((count 1000))
  (when (> count 0)
    (let ((port (open-output-string)))
      (write (make-vector 16 count) port))
    (loop (- count 1))))
(display "native resource checks passed\n")
