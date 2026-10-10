;; Bootstrap from the checkout, then rebuild using the resulting executable:
;;   chibi-scheme -I src build.scm
;;   build/snail-scheme build.scm
;; An optional argument selects the complete output filename.
(import (scheme base) (scheme file) (scheme write) (scheme process-context)
        (snail-scheme build) (snail-scheme build-host) (snail-scheme native))

(define arguments (cdr (command-line)))
(if (> (length arguments) 1) (error "usage: build.scm [OUTPUT]"))
(define output (if (null? arguments) "build/snail-scheme" (car arguments)))
(define root (absolute-path "."))
(define source (string-append root "/main.scm"))

;; Installation data belongs to this build, alongside its compiler intermediates.
(define (write-installation directory)
  (create-directory* (string-append directory "/snail-scheme"))
  (call-with-output-file (string-append directory "/snail-scheme/installation.sld")
    (lambda (port)
      (write `(define-library (snail-scheme installation)
                (export installation-root) (import (scheme base))
                (begin (define installation-root ,root))) port))))

(call-with-build-output output (list source (native-runtime-path root))
                        (lambda (directory artifact)
                          (write-installation directory)
                          (compile-native root source directory artifact 'main (list directory))))
