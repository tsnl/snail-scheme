;; Integration harness for custom native hosts; normal builds use (snail-scheme native).
(import (scheme base) (scheme process-context) (snail-scheme compiler) (snail-scheme llvm) (snail-scheme chromium-trace))
(define args (cdr (command-line)))
(define foreign
  (map (lambda (name) (cons name "snail.rust"))
       '(rust-triple rust-remember rust-recalled rust-call rust-forget rust-root-stress)))
(with-chromium-trace-to (string-append (car (cddr args)) ".trace.json")
                        (lambda () (wasm->llvm-file (source-file->wasm (car args) (cadr args) foreign '() #f) (car (cddr args)))))
