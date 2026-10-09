;; Lower resolved Scheme into explicit stack operations. Binding identities choose
;; storage; printed names are only diagnostics. Locals are cells in this baseline,
;; so closures and recursive initializers share a binding without lifetime tricks.
(define-library (snail-scheme lower)
  (export lower-program)
  (import (scheme base) (scheme cxr)
          (prefix (snail-scheme hir) hir:)
          (snail-scheme vm))
  (begin
    (define-record-type <builder>
      (make-builder globals instructions next-label constants next-constant)
      builder?
      (globals builder-globals)
      (instructions builder-instructions set-builder-instructions!)
      (next-label builder-next-label set-builder-next-label!)
      (constants builder-constants set-builder-constants!)
      (next-constant builder-next-constant set-builder-next-constant!))

    (define (lower-program program)
      (let ((libraries (program-libraries program)))
        (lower-program-items (append (library-items libraries) (hir:program-items program))
                             (primitive-definitions libraries) (hir:program-loc program))))

    (define (lower-program-items items primitives loc)
      (let* ((globals (unique-identities (append primitives (item-definitions items))))
             (builder (make-builder (numbered globals) '() 0 '() 0))
             (locals (local-definitions items globals))
             (environment (storage-environment locals '()))
             (finish (emit! builder 'return '() #f loc))
             (entry (lower-items items environment builder finish #t)))
        (finish-program builder entry locals primitives)))

    (define (finish-program builder entry locals primitives)
      (make-vm-program entry (length locals)
                       (reverse (builder-instructions builder))
                       (reverse (builder-constants builder))
                       (map (lambda (slot) (hir:value-definition-name (car slot)))
                            (builder-globals builder))
                       (map (lambda (definition)
                              (cons (cdr (assq definition (builder-globals builder)))
                                    (hir:value-definition-name definition))) primitives)))

    ;; Library bodies execute once, after their dependencies, before the program.
    (define (program-libraries program)
      (let ((seen '()) (ordered '()))
        (define (visit library)
          (if (not (memq library seen))
              (begin
                (set! seen (cons library seen))
                (for-each visit
                          (declaration-libraries (hir:library-declarations library)))
                (set! ordered (cons library ordered)))))
        (for-each visit (declaration-libraries (hir:program-imports program)))
        (reverse ordered)))

    (define (declaration-libraries declarations)
      (if (null? declarations) '()
          (append
           (if (hir:import-declaration? (car declarations))
               (map import-library (hir:import-declaration-sets (car declarations))) '())
           (declaration-libraries (cdr declarations)))))

    (define (import-library import)
      (cond
       ((hir:library-import? import) (hir:library-import-library import))
       ((hir:only-import? import) (import-library (hir:only-import-import-set import)))
       ((hir:except-import? import) (import-library (hir:except-import-import-set import)))
       ((hir:prefix-import? import) (import-library (hir:prefix-import-import-set import)))
       ((hir:rename-import? import) (import-library (hir:rename-import-import-set import)))
       (else (error "unknown HIR import" import))))

    (define (library-items libraries)
      (define (body-items declarations)
        (if (null? declarations) '()
            (append (if (hir:library-body? (car declarations))
                        (hir:library-body-items (car declarations)) '())
                    (body-items (cdr declarations)))))
      (apply append (map (lambda (library)
                           (body-items (hir:library-declarations library))) libraries)))

    (define (primitive-definitions libraries)
      (apply append
             (map (lambda (library)
                    (if (equal? (hir:library-name library) '(snail-scheme core))
                        (value-exports (hir:library-exports library)) '())) libraries)))

    (define (value-exports exports)
      (if (null? exports) '()
          (let ((definition (hir:named-binding-definition (car exports))))
            (if (hir:value-definition? definition)
                (cons definition (value-exports (cdr exports)))
                (value-exports (cdr exports))))))

    (define (item-definitions items)
      (if (null? items) '()
          (if (hir:value-binding? (car items))
              (cons (hir:value-binding-definition (car items))
                    (item-definitions (cdr items)))
              (item-definitions (cdr items)))))

    (define (unique-identities definitions)
      (let loop ((remaining definitions) (seen '()) (result '()))
        (cond ((null? remaining) (reverse result))
              ((memq (car remaining) seen) (loop (cdr remaining) seen result))
              (else (loop (cdr remaining) (cons (car remaining) seen)
                          (cons (car remaining) result))))))

    (define (numbered values)
      (let loop ((values values) (index 0))
        (if (null? values) '()
            (cons (cons (car values) index) (loop (cdr values) (+ index 1))))))

    (define (storage-environment locals free)
      (append (map (lambda (entry) (cons (car entry) (cons 'local (cdr entry))))
                   (numbered locals))
              (map (lambda (entry) (cons (car entry) (cons 'free (cdr entry))))
                   (numbered free))))

    (define (storage definition environment builder)
      (let ((local (assq definition environment))
            (global (assq definition (builder-globals builder))))
        (cond (local (cdr local))
              (global (cons 'global (cdr global)))
              (else (error "binding has no VM storage"
                           (hir:value-definition-name definition)
                           (hir:value-definition-loc definition))))))

    ;; Descend through blocks in this activation, stopping at nested procedures.
    ;; Their binding identities belong to a different activation.
    (define (local-definitions items globals)
      (define (collect node)
        (cond ((hir:lambda? node) '())
              ((hir:value-binding? node)
               (append (if (memq (hir:value-binding-definition node) globals) '()
                           (list (hir:value-binding-definition node)))
                       (collect (hir:value-binding-initializer node))))
              (else (apply append (map collect (children node))))))
      (unique-identities (apply append (map collect items))))

    (define (children node)
      (cond
       ((hir:application? node)
        (cons (hir:application-operator node) (hir:application-operands node)))
       ((hir:block? node) (append (hir:block-items node) (list (hir:block-result node))))
       ((hir:conditional? node)
        (append (list (hir:conditional-test node) (hir:conditional-consequent node))
                (if (hir:conditional-opt-alternate node)
                    (list (hir:conditional-opt-alternate node)) '())))
       ((hir:assignment? node) (list (hir:assignment-target node) (hir:assignment-value node)))
       ((hir:value-binding? node) (list (hir:value-binding-initializer node)))
       (else '())))

    (define (lambda-locals procedure)
      (append (hir:lambda-parameters procedure)
              (if (hir:lambda-opt-rest-parameter procedure)
                  (list (hir:lambda-opt-rest-parameter procedure)) '())
              (local-definitions (list (hir:lambda-body procedure)) '())))

    ;; Unlike local collection, capture analysis enters nested lambdas. A child
    ;; can need an outer cell even if its parent never reads it. Every lambda's
    ;; definitions are bound before visiting initializers, including recursive ones.
    (define (free-definitions procedure globals)
      (define (visit node bound)
        (cond
         ((hir:name? node)
          (let ((definition (hir:name-definition node)))
            (if (or (memq definition bound) (assq definition globals)) '()
                (list definition))))
         ((hir:lambda? node)
          (visit (hir:lambda-body node) (append (lambda-locals node) bound)))
         (else (apply append (map (lambda (child) (visit child bound)) (children node))))))
      (unique-identities (visit procedure '())))

    (define (emit! builder operation operands next loc)
      (let ((label (builder-next-label builder)))
        (set-builder-next-label! builder (+ label 1))
        (set-builder-instructions!
         builder (cons (make-instruction label operation operands next loc)
                       (builder-instructions builder)))
        label))

    (define (add-constant! builder kind data)
      (let ((index (builder-next-constant builder)))
        (set-builder-next-constant! builder (+ index 1))
        (set-builder-constants! builder (cons (make-constant kind data)
                                              (builder-constants builder)))
        index))

    (define (literal-constant! builder datum)
      (cond
       ((pair? datum)
        (let* ((head (literal-constant! builder (car datum)))
               (tail (literal-constant! builder (cdr datum))))
          (add-constant! builder 'pair (list head tail))))
       ((vector? datum)
        (add-constant! builder 'vector
                       (map (lambda (item) (literal-constant! builder item))
                            (vector->list datum))))
       ((null? datum) (add-constant! builder 'nil #f))
       ((boolean? datum) (add-constant! builder 'boolean datum))
       ((char? datum) (add-constant! builder 'character datum))
       ((string? datum) (add-constant! builder 'string datum))
       ((symbol? datum) (add-constant! builder 'symbol datum))
       ((bytevector? datum) (add-constant! builder 'bytevector datum))
       ((exact-integer? datum) (add-constant! builder 'integer datum))
       ((and (number? datum) (real? datum) (inexact? datum))
        (add-constant! builder 'float datum))
       (else (error "unsupported literal in baseline runtime" datum))))

    (define (lower-items items environment builder next tail?)
      (if (null? items) next
          (let ((rest (lower-items (cdr items) environment builder next tail?)))
            (lower (car items) environment builder rest (and tail? (null? (cdr items)))))))

    ;; Every expression replaces the result sequence. Nonfinal expressions need
    ;; no discard instruction; single-value checks belong to their receiving ops.

    (define (lower node environment builder next tail?)
      (cond
       ((hir:literal? node)
        (emit! builder 'constant (list (literal-constant! builder (hir:literal-value node)))
               next (hir:literal-loc node)))
       ((hir:name? node)
        (lower-reference node environment builder next))
       ((hir:lambda? node)
        (lower-lambda node environment builder next))
       ((hir:application? node)
        (lower-application node environment builder next tail?))
       ((hir:conditional? node)
        (lower-conditional node environment builder next tail?))
       ((hir:block? node)
        (lower-items (append (hir:block-items node) (list (hir:block-result node)))
                     environment builder next tail?))
       ((hir:value-binding? node)
        (lower-store (hir:value-binding-definition node) (hir:value-binding-initializer node)
                     environment builder next (hir:value-binding-loc node)))
       ((hir:assignment? node)
        (lower-store (hir:name-definition (hir:assignment-target node))
                     (hir:assignment-value node) environment builder next
                     (hir:assignment-loc node)))
       (else (error "unknown HIR node" node))))

    (define (lower-reference node environment builder next)
      (let ((slot (storage (hir:name-definition node) environment builder)))
        (emit! builder (case (car slot)
                         ((local) 'refer-local) ((free) 'refer-free) ((global) 'refer-global))
               (list (cdr slot)) next (hir:name-loc node))))

    (define (lower-store definition value environment builder next loc)
      (let* ((slot (storage definition environment builder))
             (store (emit! builder (case (car slot)
                                     ((local) 'set-local) ((free) 'set-free) ((global) 'set-global))
                           (list (cdr slot)) next loc)))
        (lower value environment builder store #f)))

    (define (lower-lambda procedure environment builder next)
      (let* ((locals (lambda-locals procedure))
             (free (free-definitions procedure (builder-globals builder)))
             (return (emit! builder 'return '() #f (hir:lambda-loc procedure)))
             (entry (lower (hir:lambda-body procedure) (storage-environment locals free)
                           builder return #t))
             (close (emit! builder 'close
                           (list entry (length (hir:lambda-parameters procedure))
                                 (if (hir:lambda-opt-rest-parameter procedure) 1 0)
                                 (length locals) (length free)) next (hir:lambda-loc procedure))))
        (lower-captures free environment builder close (hir:lambda-loc procedure))))

    (define (lower-captures free environment builder next loc)
      (if (null? free) next
          (let ((rest (lower-captures (cdr free) environment builder next loc))
                (slot (storage (car free) environment builder)))
            (emit! builder (case (car slot)
                             ((local) 'capture-local) ((free) 'capture-free)
                             (else (error "global unnecessarily captured" (car free))))
                   (list (cdr slot)) rest loc))))

    ;; Evaluate arguments left to right, then the operator. Scheme leaves their
    ;; relative order unspecified; this choice puts the procedure in the accumulator.
    (define (lower-application application environment builder next tail?)
      (let* ((operands (hir:application-operands application))
             (call (emit! builder 'call (list (length operands) next (if tail? 1 0))
                          #f (hir:application-loc application)))
             (operator (lower (hir:application-operator application)
                              environment builder call #f)))
        (lower-arguments operands environment builder operator (hir:application-loc application))))

    (define (lower-arguments arguments environment builder next loc)
      (if (null? arguments) next
          (let* ((rest (lower-arguments (cdr arguments) environment builder next loc))
                 (push (emit! builder 'push '() rest loc)))
            (lower (car arguments) environment builder push #f))))

    (define (lower-conditional conditional environment builder next tail?)
      (let* ((yes (lower (hir:conditional-consequent conditional)
                         environment builder next tail?))
             (no (if (hir:conditional-opt-alternate conditional)
                     (lower (hir:conditional-opt-alternate conditional)
                            environment builder next tail?)
                     (emit! builder 'constant (list (add-constant! builder 'unspecified #f))
                            next (hir:conditional-loc conditional))))
             (test (emit! builder 'test (list yes no) #f (hir:conditional-loc conditional))))
        (lower (hir:conditional-test conditional) environment builder test #f)))))
