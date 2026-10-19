(import
 (scheme base)
 (scheme file)
 (scheme process-context)
 (lofi compiler source-driver)
 (lofi compiler frontend)
 (lofi compiler bootstrap)
 (lofi compiler primitives)
 (lofi host chromium-trace))

(define root (cadr (command-line)))
(define output (car (cddr (command-line))))
(with-chromium-trace-to
 (string-append output "/build.trace.json")
 (lambda ()
   (call-with-values
       (lambda ()
         (collect-source-file (string-append root "/tests/lofi-compiler-service/program.sld")
                              (list (string-append root "/src"))
                              (list (cons '(lofi primitive) (make-primitive-library primitive-names))) #f))
     (lambda (key libraries)
       (let ((artifact (compile libraries (make-entry key 'main))))
         (call-with-port (open-binary-output-file (string-append output "/program.wasm"))
           (lambda (port) (write-bytevector (artifact-bytes artifact) port))))))))
