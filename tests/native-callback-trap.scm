(import (scheme base) (scheme file) (scheme write) (snail-scheme extensions))
(define port (open-output-file "callback.txt"))
(display "buffered before callback failure" port)
(rust-call (lambda (value) (error "native callback failure")) 0)
