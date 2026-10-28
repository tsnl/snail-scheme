;; Native project builds retain the existing linker and its optimization policy.
(import
 (scheme base)
 (scheme process-context)
 (snail-core build))

(let ((arguments (cdr (command-line))))
  (unless (= (length arguments) 4)
    (error "usage: link ROOT INPUT.wat OUTPUT.wasm debug|release"))
  (exit (guard (failure (#t (report-failure "link" failure)))
          (link-wat-file (car arguments)
                         (cadr arguments)
                         (list-ref arguments 2)
                         (string=? (list-ref arguments 3) "release"))
          0)))
