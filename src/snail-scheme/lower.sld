;; Lower resolved Scheme into explicit stack operations. Binding identities choose
;; storage; printed names are only diagnostics. Assigned lexical bindings are
;; cells; immutable captures are values. Frames and arguments share one stack.
(define-library (snail-scheme lower)
  (export hir-program->vm-program)
  (import (snail-scheme trace) (scheme base) (scheme cxr)
          (prefix (snail-scheme hir) hir:)
          (snail-scheme vm))
  (begin
    (define-record-type <builder>
      (make-builder globals primitives boxed instructions next-label constants next-constant)
      builder?
      (globals builder-globals)
      (primitives builder-primitives)
      (boxed builder-boxed)
      (instructions builder-instructions set-builder-instructions!)
      (next-label builder-next-label set-builder-next-label!)
      (constants builder-constants set-builder-constants!)
      (next-constant builder-next-constant set-builder-next-constant!))

    (define-traced (hir-program->vm-program program)
      (let ((libraries (program-libraries program)))
        (lower-program-items (append (library-items libraries) (hir:program-items program))
                             (primitive-definitions libraries) (hir:program-loc program))))

    (define (lower-program-items items primitives loc)
      (let* ((globals (unique-identities (append primitives (item-definitions items))))
             (builder (make-builder (numbered globals)
                                    (immutable-primitives primitives items)
                                    (boxed-definitions items globals)
                                    '() 0 '() 0))
             (locals (local-definitions items globals))
             (environment (storage-environment locals '()))
             (finish (emit! builder 'return '() #f loc))
             (body (lower-items items environment builder finish #t))
             (entry (lower-boxes locals builder body loc)))
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

    ;; Descend into child procedures because their set! can assign an outer name.
    (define (assigned-definitions items)
      (define (visit node)
        (append
         (if (hir:assignment? node)
             (list (hir:name-definition (hir:assignment-target node))) '())
         (if (hir:lambda? node) (visit (hir:lambda-body node))
             (apply append (map visit (children node))))))
      (unique-identities (apply append (map visit items))))

    ;; A closure created before a definition's initializer must retain its
    ;; location, not copy UNINITIALIZED. Otherwise immutable locals stay unboxed.
    ;; The walk tracks definitely initialized identities through evaluation order;
    ;; branches keep only identities initialized on both paths.
    (define (boxed-definitions items globals)
      (define (nested node)
        (if (hir:lambda? node)
            (append (car (initialization-sequence (list (hir:lambda-body node))
                                                  (lambda-locals node) globals
                                                  (lambda-arguments node)))
                    (nested (hir:lambda-body node)))
            (apply append (map nested (children node)))))
      (unique-identities
       (append (assigned-definitions items)
               (car (initialization-sequence items (local-definitions items globals) globals '()))
               (apply append (map nested items)))))

    (define (lambda-arguments procedure)
      (append (hir:lambda-parameters procedure)
              (if (hir:lambda-opt-rest-parameter procedure)
                  (list (hir:lambda-opt-rest-parameter procedure)) '())))

    (define (initialization-sequence nodes locals globals initialized)
      (if (null? nodes) (cons '() initialized)
          (let* ((first (initialization-state (car nodes) locals globals initialized))
                 (rest (initialization-sequence (cdr nodes) locals globals (cdr first))))
            (cons (append (car first) (car rest)) (cdr rest)))))

    (define (uninitialized-captures procedure locals globals initialized)
      (let loop ((free (free-definitions procedure (numbered globals))))
        (cond ((null? free) '())
              ((and (memq (car free) locals) (not (memq (car free) initialized)))
               (cons (car free) (loop (cdr free))))
              (else (loop (cdr free))))))

    (define (initialization-state node locals globals initialized)
      (cond ((hir:lambda? node)
             (cons (uninitialized-captures node locals globals initialized) initialized))
            ((hir:value-binding? node)
             (let ((state (initialization-state (hir:value-binding-initializer node)
                                                locals globals initialized)))
               (cons (car state) (cons (hir:value-binding-definition node) (cdr state)))))
            ((hir:conditional? node) (conditional-initialization node locals globals initialized))
            ((hir:application? node)
             (initialization-sequence (append (hir:application-operands node)
                                              (list (hir:application-operator node)))
                                      locals globals initialized))
            (else (initialization-sequence (children node) locals globals initialized))))

    (define (conditional-initialization node locals globals initialized)
      (let* ((test (initialization-state (hir:conditional-test node) locals globals initialized))
             (yes (initialization-state (hir:conditional-consequent node) locals globals (cdr test)))
             (no (if (hir:conditional-opt-alternate node)
                     (initialization-state (hir:conditional-opt-alternate node) locals globals (cdr test))
                     (cons '() (cdr test)))))
        (cons (append (car test) (car yes) (car no))
              (let loop ((identities (cdr yes)))
                (cond ((null? identities) '())
                      ((memq (car identities) (cdr no))
                       (cons (car identities) (loop (cdr identities))))
                      (else (loop (cdr identities))))))))

    (define (lower-boxes locals builder next loc)
      (let loop ((remaining locals) (index 0))
        (if (null? remaining) next
            (let ((rest (loop (cdr remaining) (+ index 1))))
              (if (memq (car remaining) (builder-boxed builder))
                  (emit! builder 'box (list index) rest loc) rest)))))

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
      (let* ((definition (hir:name-definition node))
             (slot (storage definition environment builder))
             (read (if (and (not (eq? (car slot) 'global))
                            (memq definition (builder-boxed builder)))
                       (emit! builder 'indirect '() next (hir:name-loc node)) next)))
        (emit! builder (case (car slot)
                         ((local) 'refer-local) ((free) 'refer-free) ((global) 'refer-global))
               (list (cdr slot)) read (hir:name-loc node))))

    (define (lower-store definition value environment builder next loc)
      (let* ((slot (storage definition environment builder))
             (store (emit! builder (case (car slot)
                                     ((local) (if (memq definition (builder-boxed builder))
                                                  'set-local 'init-local))
                                     ((free) 'set-free) ((global) 'set-global))
                           (list (cdr slot)) next loc)))
        (lower value environment builder store #f)))

    (define (lower-lambda procedure environment builder next)
      (let* ((locals (lambda-locals procedure))
             (free (free-definitions procedure (builder-globals builder)))
             (return (emit! builder 'return '() #f (hir:lambda-loc procedure)))
             (body (lower (hir:lambda-body procedure) (storage-environment locals free)
                          builder return #t))
             (entry (lower-boxes locals builder body (hir:lambda-loc procedure)))
             (close (emit! builder 'close
                           (list entry (length (hir:lambda-parameters procedure))
                                 (if (hir:lambda-opt-rest-parameter procedure) 1 0)
                                 (length locals) (length free)) next (hir:lambda-loc procedure))))
        (lower-captures free environment builder close (hir:lambda-loc procedure))))

    (define (lower-captures free environment builder next loc)
      (if (null? free) next
          (let* ((rest (lower-captures (cdr free) environment builder next loc))
                 (push (emit! builder 'argument '() rest loc))
                 (slot (storage (car free) environment builder)))
            (emit! builder (case (car slot)
                             ((local) 'refer-local) ((free) 'refer-free)
                             (else (error "global unnecessarily captured" (car free))))
                   (list (cdr slot)) push loc))))

    ;; A core binding is eligible only if no source initializer or set! can
    ;; replace it. Identity, not spelling, distinguishes imports from shadowing.
    (define (initialized-definitions items)
      (define (visit node)
        (append (if (hir:value-binding? node) (list (hir:value-binding-definition node)) '())
                (if (hir:lambda? node) (visit (hir:lambda-body node))
                    (apply append (map visit (children node))))))
      (apply append (map visit items)))

    (define (immutable-primitives primitives items)
      (let ((written (append (initialized-definitions items) (assigned-definitions items))))
        (let loop ((remaining primitives))
          (cond ((null? remaining) '())
                ((memq (car remaining) written) (loop (cdr remaining)))
                (else (cons (car remaining) (loop (cdr remaining))))))))

    (define (binary-primitive application builder)
      (let ((operator (hir:application-operator application)))
        (and (= (length (hir:application-operands application)) 2)
             (hir:name? operator)
             (let ((definition (hir:name-definition operator)))
               (and (memq definition (builder-primitives builder))
                    (assq (hir:value-definition-name definition) binary-numeric-primitives))))))

    (define (lower-application application environment builder next tail?)
      (let ((primitive (binary-primitive application builder)))
        (if primitive
            (lower-binary-primitive application (cdr primitive) environment builder next)
            (lower-procedure-call application environment builder next tail?))))

    (define (lower-binary-primitive application operation environment builder next)
      (let* ((definition (hir:name-definition (hir:application-operator application)))
             (index (cdr (assq definition (builder-globals builder))))
             (loc (hir:application-loc application))
             (instruction (emit! builder operation (list index) next loc)))
        (lower-arguments (hir:application-operands application) environment builder instruction loc)))

    ;; Evaluate operands left to right, then operator; leave it in the accumulator.
    (define (lower-procedure-call application environment builder next tail?)
      (let* ((operands (hir:application-operands application)) (loc (hir:application-loc application))
             (call (emit! builder 'apply (list (length operands)) #f loc))
             (transfer (if tail? (emit! builder 'shift (list (length operands)) call loc) call))
             (operator (lower (hir:application-operator application)
                              environment builder transfer #f))
             (arguments (lower-arguments operands environment builder operator loc)))
        (if tail? arguments (emit! builder 'frame (list next) arguments loc))))

    (define (lower-arguments arguments environment builder next loc)
      (if (null? arguments) next
          (let* ((rest (lower-arguments (cdr arguments) environment builder next loc))
                 (push (emit! builder 'argument '() rest loc)))
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
        (lower (hir:conditional-test conditional) environment builder test #f))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-lower)
    (import (snail-scheme test-utils))
    (begin
      (define (test-procedure parameters items result)
        (hir:make-lambda parameters #f (hir:make-block items result #f) #f))
      (define (lowered-operations node)
        (map instruction-operation
             (vm-program-instructions (lower-program-items (list node) '() #f))))
      (define (operation-count operation operations)
        (let loop ((operations operations))
          (if (null? operations) 0
              (+ (if (eq? operation (car operations)) 1 0) (loop (cdr operations))))))
      (define (expect-unboxed node)
        (let ((operations (lowered-operations node)))
          (expect (operation-count 'box operations) 0)
          (expect (operation-count 'indirect operations) 0)))

      (define (test-immutable-bindings)
        (let* ((x (hir:make-value-definition 'x #f)) (reference (hir:make-name x #f))
               (capture (test-procedure '() '() reference)))
          (expect-unboxed (test-procedure (list x) '() reference))
          (expect-unboxed (test-procedure (list x) '() capture))
          (expect-unboxed (test-procedure '()
                                          (list (hir:make-value-binding x (hir:make-literal 1 #f) #f)) capture))))

      (define (test-assigned-bindings)
        (let* ((x (hir:make-value-definition 'x #f)) (reference (hir:make-name x #f))
               (assignment (hir:make-assignment reference (hir:make-literal 1 #f) #f))
               (procedure (test-procedure (list x) (list assignment) reference)))
          (expect (operation-count 'box (lowered-operations procedure)) 1)
          (expect (operation-count 'indirect (lowered-operations procedure)) 1)
          (expect (operation-count 'box (lowered-operations
                                         (test-procedure (list x) '() (test-procedure '() (list assignment) reference)))) 1)))

      (define (test-recursive-initialization)
        (let* ((f (hir:make-value-definition 'f #f)) (g (hir:make-value-definition 'g #f))
               (self (test-procedure '() '() (hir:make-name f #f)))
               (forward (test-procedure '() '() (hir:make-name g #f))))
          (expect (operation-count 'box (lowered-operations
                                         (test-procedure '() (list (hir:make-value-binding f self #f))
                                                         (hir:make-name f #f)))) 1)
          (expect (operation-count 'box (lowered-operations
                                         (test-procedure '()
                                                         (list (hir:make-value-binding f forward #f)
                                                               (hir:make-value-binding g (hir:make-literal 1 #f) #f))
                                                         (hir:make-name f #f)))) 1)))

      (define (test-explicit-call-frames)
        (let* ((f (hir:make-value-definition 'f #f))
               (call (hir:make-application (hir:make-name f #f) '() #f))
               (operations (lowered-operations (test-procedure (list f) (list call) call))))
          (expect (operation-count 'frame operations) 1)
          (expect (operation-count 'shift operations) 1)
          (expect (operation-count 'apply operations) 2)))

      (define (test-numeric-instructions)
        (let* ((builtin (hir:make-value-definition '+ #f))
               (shadow (hir:make-value-definition '+ #f))
               (reference (hir:make-name builtin #f)))
          (define (operations operator operands items)
            (map instruction-operation
                 (vm-program-instructions
                  (lower-program-items
                   (append items (list (hir:make-application operator operands #f))) (list builtin) #f))))
          (let ((operands (list (hir:make-literal 1 #f) (hir:make-literal 2 #f))))
            (expect (operation-count 'add (operations reference operands '())) 1)
            (expect (operation-count 'apply (operations reference operands '())) 0)
            (expect (operation-count 'add (operations (hir:make-name shadow #f) operands
                                                      (list (hir:make-value-binding shadow reference #f)))) 0)
            (expect (operation-count 'add (operations reference (cdr operands) '())) 0)
            (expect (operation-count 'add (operations reference operands
                                                      (list (test-procedure '() '()
                                                                            (hir:make-assignment reference reference #f))))) 0)
            (expect (immutable-primitives (list builtin)
                                          (list (test-procedure '() (list (hir:make-value-binding builtin reference #f)) reference))) '()))))

      (define (test-lower)
        (run-test test-immutable-bindings)
        (run-test test-assigned-bindings)
        (run-test test-recursive-initialization)
        (run-test test-explicit-call-frames)
        (run-test test-numeric-instructions))))))
