;; Chibi-only diagnostic: ROOT INPUT OUTPUT, like the Scheme compiler entry.
;; Print inclusive (elapsed-seconds gc-seconds gc-count) for compiler stages, source reads,
;; and LLVM sections. Read timings include parsing. LLVM sections are nested.
;; Instrumentation changes allocation/GC behavior: use the normal compiler's
;; Chromium traces for before/after latency comparisons.
(import (scheme base) (scheme time) (scheme write) (scheme eval)
        (scheme process-context) (snail-scheme compiler)
        (only (chibi ast) gc-usecs gc-count)
        (only (meta) module-env find-module))

(define observations '())
(define (observe category name procedure)
  (lambda arguments
    (let* ((gc-before (gc-usecs)) (count-before (gc-count))
           (start (current-jiffy)) (result (apply procedure arguments))
           (elapsed (/ (- (current-jiffy) start) (* 1.0 (jiffies-per-second)))))
      (set! observations (cons (list category name elapsed (/ (- (gc-usecs) gc-before) 1000000.0)
                                     (- (gc-count) count-before)) observations))
      result)))
(define compiler-env (module-env (find-module '(snail-scheme compiler))))
(define (replace! env name procedure)
  (eval (list 'set! name (list 'quote procedure)) env))
(for-each
 (lambda (name) (replace! compiler-env name (observe 'stage name (eval name compiler-env))))
 '(source-file->syntax-list mir-library->llvm-file mir-library->dump-file))
(for-each
 (lambda (module-and-name)
   (let* ((env (module-env (find-module (car module-and-name))))
          (name (cadr module-and-name)))
     (replace! env name (observe 'stage name (eval name env)))))
 '(((snail-scheme expand) syntax-list->hir-library)
   ((snail-scheme lower) hir-library->mir-library)))
(define llvm-env (module-env (find-module '(snail-scheme llvm))))
(for-each
 (lambda (name) (replace! llvm-env name (observe 'llvm name (eval name llvm-env))))
 '(write-data write-vm-instructions write-execution initialization-body
              dispatch-body dispatch-inputs dispatch-targets))
(apply source-file->llvm-file (cdr (command-line)))
(for-each
 (lambda (row)
   (display (car row)) (display "\t")
   (display (cadr row)) (display "\t")
   (write (cddr row)) (newline))
 (reverse observations))
