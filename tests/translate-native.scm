;; Integration harness for custom native hosts; normal builds use (snail-scheme native).
(import (scheme base) (scheme process-context) (snail-scheme compiler) (snail-scheme llvm)
        (snail-scheme wasm-optimize) (snail-scheme chromium-trace)
        (only (chibi pathname) path-directory))
(define args (cdr (command-line)))
(define foreign
  (map (lambda (name) (cons name "snail.rust"))
       '(rust-triple rust-remember rust-recalled rust-call rust-forget rust-root-stress)))
(with-chromium-trace-to (string-append (car (cddr args)) ".trace.json")
                        (lambda ()
                          (let ((datum (source-file->wasm (car args) (cadr args) foreign '() #f)))
                            (wasm->llvm-file (prepare-native-wasm datum (path-directory (car (cddr args))))
                                             (car (cddr args))))))
