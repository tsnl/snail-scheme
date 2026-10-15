;; Typed expressions retain source identities and locations. The inference pass
;; may leave quantified variables in templates; monomorphization must resolve
;; every node in an emitted body before representation selection.
(define-library (snail-scheme strict-core)
  (export make-node node? node-kind node-type node-loc node-data node-constraints
          make-binding binding? binding-definition binding-scheme set-binding-scheme!
          binding-initializer set-binding-initializer! binding-kind binding-payload
          make-program program? program-body program-globals program-classes program-instances
          make-class class? class-definition class-variables class-methods
          make-instance instance? instance-class instance-types instance-members
          node-location children)
  (import (scheme base) (prefix (snail-scheme ir) ir:))
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
      (make-class definition variables methods) class?
      (definition class-definition) (variables class-variables) (methods class-methods))
    (define-record-type <instance>
      (make-instance class types members) instance?
      (class instance-class) (types instance-types) (members instance-members))

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
            ((ir:instance-declaration? node) (ir:instance-declaration-loc node)) (else #f)))
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
