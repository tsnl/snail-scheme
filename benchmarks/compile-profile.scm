;; Chibi-only diagnostic: ROOT INPUT OUTPUT, like the Scheme compiler entry.
;; Print inclusive (elapsed-us gc-us gc-count) for compiler stages, source reads,
;; and LLVM sections. Read timings include parsing. LLVM sections are nested.
;; Instrumentation changes allocation/GC behavior: use the normal compiler's
;; --timing option, not these observations, for before/after latency comparisons.
(import (scheme base) (scheme time) (scheme write) (scheme eval)
        (scheme process-context) (snail-scheme compiler)
        (only (chibi ast) gc-usecs gc-count)
        (only (meta) module-env find-module))

(define observations '())
(define (observe category name procedure)
  (lambda arguments
    (let* ((gc-before (gc-usecs)) (count-before (gc-count))
           (start (current-jiffy)) (result (apply procedure arguments))
           (elapsed (quotient (* (- (current-jiffy) start) 1000000)
                              (jiffies-per-second))))
      (set! observations (cons (list category name elapsed (- (gc-usecs) gc-before)
                                     (- (gc-count) count-before)) observations))
      result)))
(define compiler-env (module-env (find-module '(snail-scheme compiler))))
(define (replace! env name procedure)
  (eval (list 'set! name (list 'quote procedure)) env))
(replace! compiler-env 'time-stage
          (lambda (name thunk) ((observe 'stage name thunk))))
(replace! compiler-env 'expand-source
          (observe 'stage 'expand-including-imports (eval 'expand-source compiler-env)))
(let ((read-source (eval 'read-source compiler-env)))
  (replace! compiler-env 'read-source
            (lambda (path) ((observe 'read path read-source) path))))
(define llvm-env (module-env (find-module '(snail-scheme llvm))))
(for-each
 (lambda (name) (replace! llvm-env name (observe 'llvm name (eval name llvm-env))))
 '(write-data write-vm-instructions write-execution write-initialization
              write-dispatch write-destinations dispatch-targets))
(apply compile-file (cdr (command-line)))
(for-each
 (lambda (row)
   (display (car row)) (display "\t")
   (display (cadr row)) (display "\t")
   (write (cddr row)) (newline))
 (reverse observations))
