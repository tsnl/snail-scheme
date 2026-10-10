;; Construct MIR directly to test C calls, structured joins, and producer identity.
;; Failure stops the VM with a numbered diagnostic; success prints nothing.
(import (scheme base) (scheme cxr) (snail-scheme llvm) (snail-scheme machine)
        (prefix (snail-scheme mir) mir:)
        (prefix (snail-scheme library) library:))

;; ---- Foreign calls and observations ----

(define add (mir:foreign "snail_foreign_add_i32" '(i32 i32) 'i32 'pure))
(define select (mir:foreign "snail_foreign_select_i32" '(i32) 'ptr 'effect))
(define invalid (mir:foreign "snail_invalid_pc" '(ptr i32) 'void 'state))
(define (integer value) (mir:literal 'i32 value))
(define (direct descriptor . arguments) (mir:call-direct descriptor arguments))
(define (failure number)
  (mir:sequence (list (direct invalid mir:vm (integer number)) mir:finish)))
(define (expect-equal actual expected number next)
  (mir:conditional (mir:compare 'eq actual (integer expected)) next (failure number)))

;; The argc field is scratch storage after the root closure has been entered.
;; Reusing the earlier load after overwriting this field must retain its old value.
(define (load-once next)
  (mir:let* ((slot (mir:offset mir:state (integer 36))))
            (mir:sequence
             (list (mir:store (integer 41) slot 'state)
                   (mir:let* ((before (mir:load 'i32 slot 'state)))
                             (mir:sequence
                              (list (mir:store (integer 99) slot)
                                    (expect-equal (direct add before before) 82 4
                                                  (expect-equal (mir:load 'i32 slot 'state)
                                                                99 5 next)))))))))

(define (foreign-body)
  (mir:let* ((pointer (direct select (integer 0)))
             (first (mir:call-indirect add pointer (list (integer 20) (integer 22))))
             (second (direct add (integer 20) (integer 22)))
             (difference-pointer (direct select (integer 1)))
             (difference (mir:call-indirect add difference-pointer
                                            (list (integer 20) (integer 22))))
             (joined (mir:conditional (mir:compare 'eq first second)
                                      (integer 42) (integer -1))))
            (expect-equal joined 42 1
                          (expect-equal difference -2 2
                                        (expect-equal (direct add first first) 84 3
                                                      (load-once mir:finish))))))

;; ---- Fixture validation ----

;; These checks describe the explicit producer scopes used by this fixture.
;; They are test support, not runtime checks or requirements on MIR constructors.
(define (require condition message)
  (if (not condition) (error message)))
(define (anchors node)
  (if (mir:region? node)
      (apply append (map (lambda (item)
                           (if (mir:region? item) (anchors item) (list item)))
                         (mir:region-instructions node)))
      '()))
(define (all-anchors node)
  (append (anchors node) (apply append (map all-anchors (mir:expression-children node)))))
(define (same-representation? actual expected)
  (or (eq? actual expected) (and (memq actual '(word i32)) (memq expected '(word i32)))))
(define (validate-call node)
  (let* ((items (mir:expression-operands node)) (callee (car items))
         (indirect? (eq? (mir:expression-operation node) 'call-indirect))
         (arguments (if indirect? (cdddr items) (cddr items))))
    (if (mir:foreign? callee)
        (begin
          (if indirect?
              (require (eq? (mir:expression-type (caddr items)) 'ptr) "foreign function pointer"))
          (require (= (length arguments) (length (mir:foreign-arguments callee))) "foreign arity")
          (for-each (lambda (actual expected)
                      (require (same-representation? (mir:expression-type actual) expected)
                               "foreign argument representation"))
                    arguments (mir:foreign-arguments callee))))))
(define (validate-operand node available declared)
  (cond ((memq node available) #t)
        ((memq node declared) (error "producer used before definition or outside its region"))
        (else (validate-node node available declared))))
(define (validate-region instructions available declared)
  (if (pair? instructions)
      (let ((item (car instructions)))
        (validate-node item available declared)
        (validate-region (cdr instructions) (cons item available) declared))))
(define (validate-node node available declared)
  (if (mir:region? node)
      (validate-region (mir:region-instructions node) available declared)
      (let ((items (mir:expression-operands node)))
        (case (mir:expression-operation node)
          ((call-direct call-indirect) (validate-call node))
          ((if)
           (validate-operand (car items) available declared)
           (validate-node (cadr items) available declared)
           (validate-node (caddr items) available declared)))
        (if (not (eq? (mir:expression-operation node) 'if))
            (for-each (lambda (operand) (validate-operand operand available declared))
                      (mir:expression-children node))))))
(define (validate-code-references module-body)
  (let ((codes (map mir:definition-code (mir:body-definitions module-body))))
    (define (visit node)
      (if (mir:expression? node)
          (for-each (lambda (operand)
                      (if (mir:code? operand) (require (memq operand codes) "undefined code body")))
                    (mir:expression-operands node)))
      (for-each visit (mir:expression-children node)))
    (require (memq (mir:body-entry module-body) codes) "undefined entry body")
    (for-each (lambda (definition) (visit (mir:definition-body definition)))
              (mir:body-definitions module-body))))

(define (rejects-body? body)
  (guard (problem (else #t))
    (validate-node body '() (all-anchors body))
    #f))
(define (check-fixture-validation)
  (let* ((producer (direct add (integer 1) (integer 2)))
         (consumer (direct add producer (integer 3)))
         (branch (mir:conditional (integer 1) (mir:sequence (list producer)) (integer 0))))
    (require (rejects-body? (direct add (integer 1))) "validator accepted wrong arity")
    (require (rejects-body? (direct add mir:vm (integer 1))) "validator accepted wrong type")
    (require (rejects-body? (mir:sequence (list consumer producer))) "validator accepted forward use")
    (require (rejects-body? (mir:sequence (list branch consumer))) "validator accepted escaped producer")))

;; ---- Library emission ----

(check-fixture-validation)
(let* ((machine (create-machine)) (entry (mir:make-code 'foreign-fixture))
       (body (foreign-body))
       (module-body (mir:make-body entry 0
                                   (append (machine-definitions machine)
                                           (list (mir:make-definition entry body)))
                                   '() '() '())))
  (validate-node body '() (all-anchors body))
  (validate-code-references module-body)
  (write-mir-library-as-llvm
   (library:make-library #f '() '() '() module-body #f) (current-output-port)))
