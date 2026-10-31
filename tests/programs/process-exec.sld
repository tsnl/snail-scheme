(import
 (snail core base)
 (snail core io)
 (snail shell process))

;; `exec` replaces the program with a command. One that cannot start leaves
;; the program running, with why; one that can takes over its process and
;; its output, and nothing after it runs.
(write-line (ProcessError-code (exec (Command "/nonexistent/program" (Nil) "."))))
(write-line
 (ProcessError-code (exec (Command "/bin/sh" (list "-c" "true") "/nonexistent/directory"))))
(write-line (ProcessError-code (exec (Command "no-such-program-on-path" (Nil) "."))))
(write-line "replacing the program")
(exec (Command "sh" (list "-c" "echo $0; pwd; echo replaced") "/"))
(write-line "not reached")
