(import (scheme base) (scheme file) (scheme process-context)
        (snail-lofi source-driver) (snail-lofi frontend) (snail-lofi compiler)
        (snail-scheme reader) (snail-scheme syntax-parser)
        (snail-scheme strict-primitives) (wasm-native chromium-trace))

(define root (cadr (command-line)))
(define output (car (cddr (command-line))))
(with-chromium-trace-to
 (string-append output "/build.trace.json")
 (lambda ()
   (let ((rebuild (parse-library (car (reader->syntax-list (file->reader
                                                            (string-append root "/tests/lofi-builder/rebuild.lofi")))))))
     (call-with-values
         (lambda ()
           (collect-source-file (string-append root "/tests/lofi-parsed-library/program.lofi")
                                (list (string-append root "/lib"))
                                (list (cons '(lofi primitive) (make-primitive-library primitive-names))
                                      (cons '(builder rebuild) rebuild)) #f))
       (lambda (key libraries)
         (let ((artifact (compile libraries (make-entry key 'main))))
           (call-with-port (open-binary-output-file (string-append output "/program.wasm"))
             (lambda (port) (write-bytevector (artifact-bytes artifact) port)))))))))
