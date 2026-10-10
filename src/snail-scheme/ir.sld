;; Resolved high-level representation. See doc/ir.md for the grammar,
;; lexical binding rules, macro expansion, and the boundary with later lowering.
;; expand.sld constructs these immutable records from located syntax. Environments
;; are transient alists passed through expansion, never fields of IR nodes.
;;
;; Item        = value-binding | Expression
;; Expression  = name | literal | application | lambda | block | conditional | assignment
;;
;; Binding nodes and name references share value-definition identities. Reserving
;; those identities before expanding bodies supports recursion without mutation.
;; Lambda parameters are ordinary definitions; free references need no capture list.
;; All loc fields hold source locations, or #f for compiler-provided nodes.
;; library.sld owns compilation containers; their IR bodies are ordered item lists.

(define-library (snail-scheme ir)
  (export

   ;; ---- Value definition ----

   <value-binding> make-value-binding value-binding? value-binding-definition
   value-binding-initializer value-binding-loc

   ;; ---- Expression ----

   <name> make-name name? name-definition name-loc
   <literal> make-literal literal? literal-value literal-loc
   <application> make-application application? application-operator application-operands
   application-loc
   <lambda> make-lambda lambda? lambda-parameters lambda-opt-rest-parameter
   lambda-body lambda-loc
   <block> make-block block? block-items block-loc
   <conditional> make-conditional conditional? conditional-test conditional-consequent
   conditional-opt-alternate conditional-loc
   <assignment> make-assignment assignment? assignment-target assignment-value assignment-loc

   ;; ---- Identity ----

   <value-definition> make-value-definition value-definition? value-definition-name
   value-definition-loc)

  (import (scheme base))
  (begin

    ;; ---- Value binding ----

    ;; The initializer and references share an identity reserved during body discovery.
    (define-record-type <value-binding>
      (make-value-binding
       definition ; value-definition shared with every reference to this binding
       initializer ; one expression, evaluated once
       loc)
      value-binding?
      (definition value-binding-definition)
      (initializer value-binding-initializer)
      (loc value-binding-loc))

    ;; ---- Expression ----

    ;; A reference retains both the definition identity and its own source location.
    (define-record-type <name>
      (make-name
       definition ; reference to a value-definition
       loc) ; location of this reference
      name?
      (definition name-definition)
      (loc name-loc))

    (define-record-type <literal>
      (make-literal
       value ; quoted datum or self-evaluating Scheme value
       loc)
      literal?
      (value literal-value)
      (loc literal-loc))

    (define-record-type <application>
      (make-application
       operator ; expression
       operands ; ordered list of expressions
       loc)
      application?
      (operator application-operator)
      (operands application-operands)
      (loc application-loc))

    (define-record-type <lambda>
      (make-lambda
       parameters ; ordered value-definition objects
       opt-rest-parameter ; value-definition, or #f for fixed arity
       body ; block: ordered items ending in a result expression
       loc)
      lambda?
      (parameters lambda-parameters)
      (opt-rest-parameter lambda-opt-rest-parameter)
      (body lambda-body)
      (loc lambda-loc))

    (define-record-type <block>
      (make-block
       items ; nonempty ordered items; the last is an expression providing the result
       loc)
      block?
      (items block-items)
      (loc block-loc))

    (define-record-type <conditional>
      (make-conditional
       test
       consequent
       opt-alternate ; expression, or #f for an unspecified false-branch result
       loc)
      conditional?
      (test conditional-test)
      (consequent conditional-consequent)
      (opt-alternate conditional-opt-alternate)
      (loc conditional-loc))

    ;; Source set! is represented as data; building this node does not mutate a binding.
    (define-record-type <assignment>
      (make-assignment
       target ; name reference
       value ; expression
       loc)
      assignment?
      (target assignment-target)
      (value assignment-value)
      (loc assignment-loc))

    ;; ---- Identity ----

    ;; Defining nodes and references share this object; neither stores a scope.
    (define-record-type <value-definition>
      (make-value-definition name loc)
      value-definition?
      (name value-definition-name)
      (loc value-definition-loc))

    ))
