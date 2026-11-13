(import
 (snail core base)
 (snail core io)
 (snail shell process))

(define (main) (→ Unit) (! output-port process)
  ;; `exec` replaces the program with a command. One that cannot start leaves
  ;; the program running, with why; one that can takes over its process and
  ;; its output, and nothing after it runs.
  (write-line
   (● (exec (new Command (program "/nonexistent/program") (arguments (Nil)) (directory "."))) code))
  (write-line
   (● (exec (new Command
              (program "/bin/sh")
              (arguments (list "-c" "true"))
              (directory "/nonexistent/directory")))
      code))
  (write-line
   (● (exec (new Command (program "no-such-program-on-path") (arguments (Nil)) (directory ".")))
      code))
  (write-line "replacing the program")
  (exec (new Command
          (program "sh")
          (arguments (list "-c" "echo $0; pwd; echo replaced"))
          (directory "/")))
  (write-line "not reached")
  (unit))
