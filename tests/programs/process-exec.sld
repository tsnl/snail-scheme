(import
 (snail core base)
 (snail core io)
 (snail shell process))

(define (main (processes Processes) (out OutputPort)) (→ Unit)
  ;; `exec` replaces the program with a command. One that cannot start leaves
  ;; the program running, with why; one that can takes over its process and
  ;; its output, and nothing after it runs.
  (write-line out
              (● (processes::exec
                  (new Command
                    (program "/nonexistent/program")
                    (arguments (Nil))
                    (directory ".")))
                 code))
  (write-line out
              (● (processes::exec (new Command
                                    (program "/bin/sh")
                                    (arguments (list "-c" "true"))
                                    (directory "/nonexistent/directory")))
                 code))
  (write-line out
              (● (processes::exec
                  (new Command
                    (program "no-such-program-on-path")
                    (arguments (Nil))
                    (directory ".")))
                 code))
  (write-line out "replacing the program")
  (processes::exec (new Command
                     (program "sh")
                     (arguments (list "-c" "echo $0; pwd; echo replaced"))
                     (directory "/")))
  (write-line out "not reached")
  (unit))
