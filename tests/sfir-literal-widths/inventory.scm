;; Record checked numeric representations in source locations for migration
;; audits. This helper neither rewrites source nor participates in compilation.
(import (scheme base) (scheme file) (scheme write) (scheme process-context)
        (snail-sfir source-driver) (snail-scheme strict-core)
        (snail-scheme ir) (snail-scheme source)
        (only (snail-scheme strict-types) resolve)
        (only (snail-scheme chromium-trace) with-chromium-trace-to)
        (only (scheme hash-table) make-hash-table hash-table-ref/default hash-table-set!))

(define (record-literals program port)
  (let ((seen (make-hash-table eq?)))
    (define (visit node)
      (when (and (node? node) (not (hash-table-ref/default seen node #f)))
        (hash-table-set! seen node #t)
        (let ((type (resolve (node-type node))) (loc (node-loc node)))
          (when (and (literal? node) (loc? loc) (memq type '(I32 I64 F32 F64)))
            (write (list (loc-filename loc) (loc-line loc) (loc-column loc)
                         type (literal-value node)) port)
            (newline port)))
        (for-each visit (children node))))
    (for-each (lambda (binding) (visit (binding-initializer binding)))
              (program-globals program))
    (visit (program-body program))))

(let* ((arguments (cdr (command-line))) (root (car arguments))
       (source (cadr arguments)) (output (car (cddr arguments))))
  (with-chromium-trace-to
   (string-append output ".trace.json")
   (lambda ()
     (let ((program (source-file->core root source)))
       (call-with-output-file output
         (lambda (port) (record-literals program port)))))))
