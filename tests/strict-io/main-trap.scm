(import (snail strict) (snail io))
(define port (open-output-file "main-trap.txt"))
(write-string "buffered before main trapped" port)
(unreachable)
