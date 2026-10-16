(import (scheme base) (scheme file) (scheme process-context)
        (snail-sfir source-driver) (snail-sfir frontend) (snail-sfir compiler)
        (snail-scheme strict-primitives) (wasm-native chromium-trace))

(define root (cadr (command-line)))
(define output (car (cddr (command-line))))
(with-chromium-trace-to
 (string-append output "/build.trace.json")
 (lambda ()
   (call-with-values
       (lambda ()
         (collect-source-file (string-append root "/tests/sfir-compiler-service/program.sfir")
                              (list (string-append root "/lib"))
                              (list (cons '(sfir primitive) (make-primitive-library primitive-names))) #f))
     (lambda (key libraries)
       (let ((artifact (compile libraries (make-entry key 'main))))
         (call-with-port (open-binary-output-file (string-append output "/program.wasm"))
           (lambda (port) (write-bytevector (artifact-bytes artifact) port))))))))
