;; Resolved high-level representation. See doc/hir.md for the grammar,
;; lexical binding rules, macro expansion, and the boundary with later lowering.
;; expand.sld constructs these immutable records from located syntax. Environments
;; are transient alists passed through expansion, never fields of HIR nodes.
;;
;; Item        = value-binding | Expression
;; Expression  = name | literal | application | lambda | block | conditional | assignment
;;
;; Binding nodes and name references share value-definition identities. Reserving
;; those identities before expanding bodies supports recursion without mutation.
;; Lambda parameters are ordinary definitions; free references need no capture list.
;; All loc fields hold source locations, or #f for compiler-provided nodes.

(define-library (snail-scheme hir)
  (export

   ;; ---- Program and library ----

   <program> make-program program? program-imports program-items
   program-dependencies program-loc
   <library> make-library library? library-name library-declarations
   library-exports library-dependencies library-loc
   <library-body> make-library-body library-body? library-body-items library-body-loc

   ;; ---- Import and export ----

   <import-declaration> make-import-declaration import-declaration? import-declaration-sets
   import-declaration-bindings import-declaration-loc
   <export-declaration> make-export-declaration export-declaration? export-declaration-specs
   export-declaration-loc
   <export-spec> make-export-spec export-spec? export-spec-local-name export-spec-external-name
   export-spec-definition export-spec-loc
   <library-import> make-library-import library-import? library-import-name
   library-import-library library-import-loc
   <only-import> make-only-import only-import? only-import-import-set only-import-names
   only-import-loc
   <except-import> make-except-import except-import? except-import-import-set
   except-import-names except-import-loc
   <prefix-import> make-prefix-import prefix-import? prefix-import-import-set
   prefix-import-prefix prefix-import-loc
   <rename-import> make-rename-import rename-import? rename-import-import-set
   rename-import-renamings rename-import-loc
   <import-rename> make-import-rename import-rename? import-rename-from import-rename-to
   import-rename-loc

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
   <block> make-block block? block-items block-result block-loc
   <conditional> make-conditional conditional? conditional-test conditional-consequent
   conditional-opt-alternate conditional-loc
   <assignment> make-assignment assignment? assignment-target assignment-value assignment-loc

   ;; ---- Identity ----

   <value-definition> make-value-definition value-definition? value-definition-name
   value-definition-loc
   <named-binding> make-named-binding named-binding? named-binding-name named-binding-definition)

  (import (scheme base))
  (begin

    ;; ---- Program and library ----

    (define-record-type <program>
      (make-program
       imports ; list of import-declaration
       items ; ordered value-binding or expression nodes
       dependencies ; library names, including dependencies introduced by macros
       loc)
      program?
      (imports program-imports)
      (items program-items)
      (dependencies program-dependencies)
      (loc program-loc))

    (define-record-type <library>
      (make-library
       name ; library name: list of symbols or nonnegative integers
       declarations ; ordered import-declaration, export-declaration, or library-body nodes
       exports ; list of named-binding, using external names
       dependencies ; library names
       loc)
      library?
      (name library-name)
      (declarations library-declarations)
      (exports library-exports)
      (dependencies library-dependencies)
      (loc library-loc))

    (define-record-type <library-body>
      (make-library-body
       items ; ordered value-binding or expression nodes
       loc)
      library-body?
      (items library-body-items)
      (loc library-body-loc))

    ;; ---- Import and export ----

    (define-record-type <import-declaration>
      (make-import-declaration
       sets ; list of structured import sets below
       bindings ; list of named-binding, using local names
       loc)
      import-declaration?
      (sets import-declaration-sets)
      (bindings import-declaration-bindings)
      (loc import-declaration-loc))

    (define-record-type <export-declaration>
      (make-export-declaration
       specs ; list of export-spec
       loc)
      export-declaration?
      (specs export-declaration-specs)
      (loc export-declaration-loc))

    (define-record-type <export-spec>
      (make-export-spec
       local-name ; symbol
       external-name ; symbol; equal to local-name for an unrenamed export
       definition ; the original definition, including for re-exports
       loc)
      export-spec?
      (local-name export-spec-local-name)
      (external-name export-spec-external-name)
      (definition export-spec-definition)
      (loc export-spec-loc))

    (define-record-type <library-import>
      (make-library-import
       name ; library name
       library ; resolved library, retaining its body for subsequent passes
       loc)
      library-import?
      (name library-import-name)
      (library library-import-library)
      (loc library-import-loc))

    (define-record-type <only-import>
      (make-only-import
       import-set
       names ; list of symbols
       loc)
      only-import?
      (import-set only-import-import-set)
      (names only-import-names)
      (loc only-import-loc))

    (define-record-type <except-import>
      (make-except-import
       import-set
       names ; list of symbols
       loc)
      except-import?
      (import-set except-import-import-set)
      (names except-import-names)
      (loc except-import-loc))

    (define-record-type <prefix-import>
      (make-prefix-import
       import-set
       prefix ; symbol
       loc)
      prefix-import?
      (import-set prefix-import-import-set)
      (prefix prefix-import-prefix)
      (loc prefix-import-loc))

    (define-record-type <rename-import>
      (make-rename-import
       import-set
       renamings ; list of import-rename
       loc)
      rename-import?
      (import-set rename-import-import-set)
      (renamings rename-import-renamings)
      (loc rename-import-loc))

    (define-record-type <import-rename>
      (make-import-rename
       from ; exported symbol
       to ; local symbol
       loc)
      import-rename?
      (from import-rename-from)
      (to import-rename-to)
      (loc import-rename-loc))

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
       body ; block: internal definitions, expressions, and a final result
       loc)
      lambda?
      (parameters lambda-parameters)
      (opt-rest-parameter lambda-opt-rest-parameter)
      (body lambda-body)
      (loc lambda-loc))

    (define-record-type <block>
      (make-block
       items ; ordered value-binding or expression nodes
       result ; mandatory final expression
       loc)
      block?
      (items block-items)
      (result block-result)
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

    (define-record-type <named-binding>
      (make-named-binding
       name ; visible symbol in an import or export interface
       definition) ; original definition, never copied to implement a rename
      named-binding?
      (name named-binding-name)
      (definition named-binding-definition))

    ))
