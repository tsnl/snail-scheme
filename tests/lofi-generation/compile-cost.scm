;; Diagnostic phase timings for source depth, without Wasm execution or timing
;; assertions. Select the compiler revision with -I; optional arguments are depths.
(import (scheme base) (scheme write) (scheme time) (scheme process-context)
        (prefix (lofi ir) ir:)
        (only (lofi infer) infer-program)
        (only (lofi specialize) prepare-generation)
        (only (lofi emit-wasm) strict-core->wasm))

;; ---- Source shapes ----

(define (nested-addition depth binding)
  (if (= depth 0) (ir:make-literal 1 #f)
      (ir:make-application (ir:make-name binding #f)
                           (list (ir:make-literal 1 #f) (nested-addition (- depth 1) binding)) #f)))

(define (discarded-conditional depth)
  (if (= depth 0) (ir:make-literal 1 #f)
      (ir:make-conditional (ir:make-literal #t #f)
                           (ir:make-block (list (discarded-conditional (- depth 1)) (ir:make-literal 1 #f)) #f)
                           (ir:make-literal 1 #f) #f)))

(define (generic-fixed-result depth binding)
  (if (= depth 0) (ir:make-literal 1 #f)
      (ir:make-application (ir:make-name binding #f)
                           (list (generic-fixed-result (- depth 1) binding)) #f)))

(define (diagnostic-source workload depth)
  (case workload
    ((addition)
     (let ((binding (ir:make-value-definition 'add #f)))
       (values (list (nested-addition depth binding)) (list (cons binding 'i32-add)))))
    ((discarded-if) (values (list (discarded-conditional depth)) '()))
    ((generic-result)
     (let* ((binding (ir:make-value-definition 'erase #f))
            (parameter (ir:make-value-definition 'ignored #f))
            (definition (ir:make-value-binding binding
                                               (ir:make-lambda (list parameter) #f (ir:make-literal 42 #f) #f) #f)))
       (values (list definition (generic-fixed-result depth binding)) '())))))

;; ---- Phase measurements ----

(define (seconds start finish) (inexact (/ (- finish start) (jiffies-per-second))))

(define (run-sample workload depth)
  (let-values (((source primitives) (diagnostic-source workload depth)))
    (let* ((start (current-jiffy)) (program (infer-program source primitives #f))
           (checked (current-jiffy)) (prepared (prepare-generation program))
           (planned (current-jiffy)) (wasm (strict-core->wasm prepared)) (finished (current-jiffy)))
      (unless (and (pair? wasm) (eq? (car wasm) 'module)) (error "expected a Wasm module"))
      (write (list 'workload workload 'depth depth 'check (seconds start checked)
                   'prepare (seconds checked planned) 'emit (seconds planned finished)))
      (newline))))

(define (parse-depth text)
  (let ((depth (string->number text)))
    (unless (and (exact-integer? depth) (>= depth 0)) (error "expected a nonnegative depth" text))
    depth))

(define depths
  (if (null? (cdr (command-line))) '(64 128 256 512) (map parse-depth (cdr (command-line)))))

(for-each (lambda (depth)
            (for-each (lambda (workload) (run-sample workload depth)) '(addition discarded-if generic-result)))
          depths)
