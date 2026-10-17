(import
 (lofi base)
 (lofi io))
(def port
     (open-output-file "main-trap.txt"))
(write-string "buffered before main trapped" port)
(unreachable)
