(import (scheme base) (scheme cxr) (scheme write) (scheme process-context)
        (only (chibi ast) env-cell) (only (meta) module-env)
        (chibi modules) (snail-scheme compiler) (snail-scheme expand)
        (snail-scheme bootstrap) (snail-scheme library) (snail-scheme source)
        (snail-scheme wasm) (snail-scheme specialize) (snail-scheme type-analysis)
        (snail-scheme chromium-trace) (prefix (snail-scheme ir) ir:))

;; ---- Process-local compiler request observer ----

;; Only this diagnostic Chibi process replaces the private request binding.
;; It calls the original with the same arguments and returns the same result.
;; Counts describe planning requests, never executed Wasm or allocation costs.
(define request-count 0)
(define rejected '())
(define rejected-total-only 0)
(define rejected-source-only 0)
(define rejected-both 0)
(define specialization-module (load-module '(snail-scheme specialize)))
(define original-request (module-ref specialization-module 'request-copy))
(define entries-of (module-ref specialization-module 'work-entries))
(define count-source (module-ref specialization-module 'copy-count))

(define (record-rejection source total count)
  (cond ((and (>= total 256) (>= count 8)) (set! rejected-both (+ rejected-both 1)))
        ((>= total 256) (set! rejected-total-only (+ rejected-total-only 1)))
        (else (set! rejected-source-only (+ rejected-source-only 1))))
  (let ((entry (assq source rejected)))
    (if entry (set-cdr! entry (+ (cdr entry) 1))
        (set! rejected (cons (cons source 1) rejected)))))

(define (observe-request source arguments signature substitutions captures callees work)
  (let* ((entries (entries-of work)) (total (length entries))
         (count (count-source source entries))
         (result (original-request source arguments signature substitutions captures callees work)))
    (set! request-count (+ request-count 1))
    (unless result
      (unless (or (>= total 256) (>= count 8)) (error "unexpected copy rejection"))
      (record-rejection source total count))
    result))

(set-cdr! (env-cell (module-env specialization-module) 'request-copy) observe-request)

;; ---- Original checking and specialization inputs ----

(define root (cadr (command-line)))
(define input (caddr (command-line)))
(define trace (cadddr (command-line)))

(define (prepare-plan)
  (let* ((program (syntax-list->ir-library
                   ((module-ref '(snail-scheme compiler) 'source-file->syntax-list) input)
                   ((module-ref '(snail-scheme compiler) 'library-loader) root '())
                   (list (make-core-library '(snail-scheme core) bootstrap-primitive-names)
                         ((module-ref '(snail-scheme compiler) 'make-extension-library) '()))))
         (libraries (library-dependency-order program))
         (module ((module-ref '(snail-scheme wasm) 'prepare-module) libraries '()))
         (checked ((module-ref '(snail-scheme wasm) 'generate-library-functions)
                   ((module-ref '(snail-scheme wasm) 'numbered) libraries) module))
         (output (cdr checked)))
    (check-recursive-instances ((module-ref '(snail-scheme wasm) 'output-calls) output))
    (cons module (cdr (specialize-libraries libraries ((module-ref '(snail-scheme wasm) 'module-typing) module)
                      ((module-ref '(snail-scheme wasm) 'output-instances) output)
                      ((module-ref '(snail-scheme wasm) 'output-scopes) output))))))

;; ---- Copy groups and reached budgets ----

(define (location source)
  (let ((loc (ir:lambda-loc source)))
    (and loc (list (loc-filename loc) (loc-line loc) (loc-column loc)))))
(define (rejections source)
  (let ((entry (assq source rejected))) (if entry (cdr entry) 0)))
(define (source-entry source copies module)
  (let ((number (assq source ((module-ref '(snail-scheme wasm) 'module-functions) module))))
    (list 'source (and number (cdr number)) (location source)
          (map ir:value-definition-name (ir:lambda-parameters source))
          (count-source source copies) (rejections source))))
(define (print-group source copies module)
  (write (source-entry source copies module)) (newline))
(define (print-groups copies module)
  (let loop ((remaining copies) (seen '()))
    (unless (null? remaining)
      (let ((source (specialized-source (car remaining))))
        (unless (memq source seen) (print-group source copies module))
        (loop (cdr remaining) (cons source seen))))))
(define (inspect-plan)
  (let* ((plan (prepare-plan)) (module (car plan)) (copies (cdr plan)))
    (when (and (pair? copies) (= request-count 0)) (error "copy request observer did not attach"))
    (write (list 'summary (length copies) 256 8 request-count (apply + (map cdr rejected))
                 rejected-total-only rejected-source-only rejected-both))
    (newline) (print-groups copies module)
    (for-each (lambda (entry)
                (unless (> (count-source (car entry) copies) 0) (print-group (car entry) copies module))) rejected)))

(with-chromium-trace-to trace inspect-plan)
