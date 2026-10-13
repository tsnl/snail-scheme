;; Typed expressions retain source identities and locations. The inference pass
;; may leave quantified variables in templates; monomorphization must resolve
;; every node in an emitted body before representation selection.
(define-library (snail-scheme strict-core)
  (export make-node node? node-kind node-type node-loc node-data node-constraints
          make-binding binding? binding-definition binding-scheme set-binding-scheme!
          binding-initializer set-binding-initializer! binding-kind binding-payload
          make-program program? program-body program-globals program-classes program-instances
          make-class class? class-definition class-variables class-methods class-overload?
          make-instance instance? instance-class instance-types instance-members
          improve-overloads!
          node-location children)
  (import (scheme base) (snail-scheme strict-types) (prefix (snail-scheme ir) ir:))
  (begin

    ;; ---- Typed source templates ----

    (define-record-type <node>
      (make-node kind type loc data constraints) node?
      (kind node-kind) (type node-type) (loc node-loc)
      (data node-data) (constraints node-constraints))
    (define-record-type <binding>
      (make-binding definition scheme initializer kind payload) binding?
      (definition binding-definition)
      (scheme binding-scheme set-binding-scheme!)
      (initializer binding-initializer set-binding-initializer!)
      (kind binding-kind) (payload binding-payload))
    (define-record-type <program>
      (make-program body globals classes instances) program?
      (body program-body) (globals program-globals)
      (classes program-classes) (instances program-instances))

    ;; ---- Static class evidence ----

    (define-record-type <class>
      (make-class definition variables methods overload?) class?
      (definition class-definition) (variables class-variables) (methods class-methods)
      (overload? class-overload?))
    (define-record-type <instance>
      (make-instance class types members) instance?
      (class instance-class) (types instance-types) (members instance-members))

    ;; Overload families are classes whose final parameter is determined by the
    ;; preceding argument types. Ordinary classes retain complete-head lookup.
    ;; Solving never guesses arguments from results or from available instances.
    (define (overload-class definition classes)
      (cond ((null? classes) #f)
            ((eq? definition (class-definition (car classes)))
             (and (class-overload? (car classes)) (car classes)))
            (else (overload-class definition (cdr classes)))))
    (define (overload-inputs types) (reverse (cdr (reverse types))))
    (define (overload-output types) (car (reverse types)))
    (define (overload-instance class arguments instances)
      (cond ((null? instances) #f)
            ((and (eq? class (instance-class (car instances)))
                  (type-equal? arguments (overload-inputs (instance-types (car instances)))))
             (car instances))
            (else (overload-instance class arguments (cdr instances)))))
    (define (matching-overload-goal constraint goals)
      (cond ((null? goals) #f)
            ((and (not (eq? constraint (car goals))) (eq? (car constraint) (caar goals))
                  (type-equal? (overload-inputs (cdr constraint)) (overload-inputs (cdar goals))))
             (car goals))
            (else (matching-overload-goal constraint (cdr goals)))))
    (define (check-overload-goals goals classes loc)
      (for-each (lambda (constraint)
                  (let ((class (overload-class (car constraint) classes)))
                    (when (and class (not (= (length (cdr constraint)) (length (class-variables class)))))
                      (strict-error loc "wrong number of overload constraint arguments")))) goals))
    (define (select-overload-result! class constraint instances loc)
      (let ((arguments (overload-inputs (cdr constraint))))
        (when (concrete-type? arguments)
          (let ((instance (overload-instance class arguments instances)))
            (unless instance (strict-error loc "no exact overload for argument types" arguments))
            (unify! (overload-output (cdr constraint)) (overload-output (instance-types instance)) loc)))))
    (define (equate-overload-results! left right loc)
      (let ((left (resolve left)) (right (resolve right)))
        (when (and (variable? left) (variable-rigid? left) (variable? right) (variable-rigid? right)
                   (not (eq? left right)))
          (strict-error loc "overload constraints with equal arguments require one shared result variable"))
        (unify! left right loc)))
    (define (improve-overload! constraint goals classes instances loc)
      (let ((class (overload-class (car constraint) classes)))
        (when class
          (let ((same (matching-overload-goal constraint goals)))
            (when same (equate-overload-results! (overload-output (cdr constraint)) (overload-output (cdr same)) loc)))
          (select-overload-result! class constraint instances loc))))
    (define (improve-overloads! constraints assumptions classes instances loc)
      (let ((before (type-datum constraints)) (goals (append assumptions constraints)))
        (check-overload-goals goals classes loc)
        (for-each (lambda (constraint) (improve-overload! constraint goals classes instances loc)) constraints)
        (unless (equal? (type-datum constraints) before)
          (improve-overloads! constraints assumptions classes instances loc))))

    ;; ---- Located expansion input ----

    (define (node-location node)
      (cond ((ir:literal? node) (ir:literal-loc node)) ((ir:name? node) (ir:name-loc node))
            ((ir:lambda? node) (ir:lambda-loc node)) ((ir:application? node) (ir:application-loc node))
            ((ir:block? node) (ir:block-loc node)) ((ir:conditional? node) (ir:conditional-loc node))
            ((ir:value-binding? node) (ir:value-binding-loc node))
            ((ir:assignment? node) (ir:assignment-loc node))
            ((ir:type-declaration? node) (ir:type-declaration-loc node))
            ((ir:annotation? node) (ir:annotation-loc node))
            ((ir:instantiation? node) (ir:instantiation-loc node))
            ((ir:class-declaration? node) (ir:class-declaration-loc node))
            ((ir:instance-declaration? node) (ir:instance-declaration-loc node))
            ((ir:overload-declaration? node) (ir:overload-declaration-loc node))
            ((ir:extern-declaration? node) (ir:extern-declaration-loc node)) (else #f)))
    (define (children node)
      (cond ((ir:lambda? node) (list (ir:lambda-body node)))
            ((ir:block? node) (ir:block-items node))
            ((ir:application? node) (cons (ir:application-operator node) (ir:application-operands node)))
            ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
            ((ir:conditional? node) (list (ir:conditional-test node) (ir:conditional-consequent node)
                                          (ir:conditional-opt-alternate node)))
            ((ir:annotation? node) (list (ir:annotation-expression node)))
            ((ir:instantiation? node) (list (ir:instantiation-expression node)))
            ((ir:assignment? node) (list (ir:assignment-value node))) (else '())))))
