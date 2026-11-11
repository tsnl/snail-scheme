;; Query: the scheme of each value a declaration makes, which follows from
;; the entity, as the old compiler gives it (`with-case-values`,
;; `instance-method-scheme` and `default-scheme`,
;; src/snail/shell/compiler/expand.sld). Each is executable code's: a
;; function is `(Callable Dyn FnContract arrow)`.
;;
;; - A case's constructor takes its fields and returns its type, at the
;;   type's parameters.
;; - Each field is read by an accessor, which performs `mut` when the field
;;   is mutable; a mutable field is written by a setter and swapped by a
;;   swapper, which perform `mut`; a field of a struct with no mutable
;;   field is replaced by a replacer, which copies the struct.
;; - A class's method quantifies the class's parameters and outputs, then
;;   its own variables, and requires the class first. A field class
;;   `::label` is `(::label R T)`, two types and no output, and its one
;;   method, the reader, has the scheme `(Fn R -> T)` of its own.
;; - An operation's type performs its effect besides its latent effects; a
;;   default's performs only its latent effects, since no handler of the
;;   effect is in scope where a default runs.
;; - An instance's implementation of a method has the method's own scheme
;;   at the instance's head: the instance's variables and requirements
;;   first, then the method's own, each of its variables kept apart as
;;   `(Own variable)`. A row ending with a parameter the head gives a row
;;   becomes the one row they make, as the old compiler substitutes it.
;;
;; And a type with its variables bound, as the old compiler's `substitute`
;; makes it, which the schemes above are made with, as is a struct's field
;; at its type's arguments; and whether a struct has no mutable field,
;; which gives its fields replacers and each the instance of its label's
;; field class that reads it.
(define-library (snail compiler declare schemes)
  (export
   constructor-scheme
   field-schemes
   pure-struct?
   field-class-parameters
   field-reader-scheme
   method-scheme
   operation-scheme
   default-scheme
   implementation-scheme
   substituted)
  (import
   (snail core base)
   (only (snail compiler expand language)
         Global
         ClassGlobal
         Dyn
         FnContract
         FieldRole
         Accessor
         Replacer
         Setter
         Swapper)
   (snail compiler declare language)
   (snail compiler declare forms)
   (snail compiler declare equality))
  (begin

    ;; ---- Data ----

    (: function (impl (Fn (List Type) Type (List Global) -> Type)))
    (define (function parameters result effects)
      (Callable (Dyn) (FnContract) (Arrow parameters result (Effects effects (None)))))

    (: data-scheme (impl (Fn Data Type -> Scheme)))
    (define (data-scheme data type)
      (Scheme (map Written (::parameters data)) (Nil) (Nil) type))

    (: self-type (impl (Fn Data -> Type)))
    (define (self-type data)
      (Con (::global data) (map (lambda (name) (Var (Written name))) (::parameters data))))

    (: constructor-scheme (impl (Fn Data DataCase -> Scheme)))
    (define (constructor-scheme data case)
      (data-scheme data (function (map ::type (::fields case)) (self-type data) (Nil))))

    (: mut-effect Global)
    (define mut-effect
      (Global forms-library "mut" 0))

    ;; The functions a field has, each with its scheme, in the old
    ;; compiler's order.
    (: field-schemes (impl (Fn Data DataCase DataField -> (List (Pair FieldRole Scheme)))))
    (define (field-schemes data case field)
      (let* ((self (self-type data))
             (type (::type field))
             (accessor (Pair (Accessor)
                             (data-scheme data
                                          (function (list self)
                                                    type
                                                    (if (::mutable? field)
                                                        (list mut-effect)
                                                        (Nil)))))))
        (cond ((::mutable? field)
               (list accessor
                     (Pair (Setter)
                           (data-scheme data
                                        (function (list self type)
                                                  (Con (Global forms-library "Unit" 0) (Nil))
                                                  (list mut-effect))))
                     (Pair (Swapper)
                           (data-scheme data (function (list self type) type (list mut-effect))))))
              ((pure-struct? data case)
               (list accessor
                     (Pair (Replacer) (data-scheme data (function (list self type) self (Nil))))))
              (else (list accessor)))))

    ;; Whether `case`, a case of `data`, is a struct's with no mutable
    ;; field: a value read by path, whose fields are replaced by copying.
    (: pure-struct? (impl (Fn Data DataCase -> Bool)))
    (define (pure-struct? data case)
      (match (::kind data)
        ((StructData) (not (any? ::mutable? (::fields case))))
        ((EnumData) #f)))

    ;; ---- Classes ----

    ;; A field class's parameters: the record type, then its field's type.
    (: field-class-parameters (List ClassParameter))
    (define field-class-parameters
      (list (TypeParameter "R") (TypeParameter "T")))

    ;; The reader's own scheme, over the field class's parameters.
    (: field-reader-scheme Scheme)
    (define field-reader-scheme
      (Scheme (Nil) (Nil) (Nil) (function (list (Var (Written "R"))) (Var (Written "T")) (Nil))))

    (: class-variables (impl (Fn Class -> (List TypeVariable))))
    (define (class-variables class)
      (map Written
           (append (map (lambda (parameter)
                          (match parameter
                            ((TypeParameter name) name)
                            ((RowParameter name) name)))
                        (::parameters class))
                   (map (lambda (output) (::name (::label output))) (::outputs class)))))

    (: method-scheme (impl (Fn Class Method -> Scheme)))
    (define (method-scheme class method)
      (let ((own (::scheme method))
            (variables (class-variables class)))
        (Scheme (append variables (::variables own))
                (Cons (ClassRequirement (ClassGlobal (::global class)) (map Var variables))
                      (::requirements own))
                (::copied own)
                (::type own))))

    ;; ---- Effects ----

    (: operation-scheme (impl (Fn Global Operation -> Scheme)))
    (define (operation-scheme effect operation)
      (Scheme (Nil)
              (Nil)
              (Nil)
              (function (::parameters operation)
                        (::result operation)
                        (effect-set (Cons effect (::latent operation))))))

    (: default-scheme (impl (Fn Operation -> Scheme)))
    (define (default-scheme operation)
      (Scheme (Nil)
              (Nil)
              (Nil)
              (function (::parameters operation) (::result operation) (::latent operation))))

    ;; ---- Instances ----

    ;; `class` is the instance's, declared, and `method` one of its methods.
    (: implementation-scheme (impl (Fn Class Method Instance -> Scheme)))
    (define (implementation-scheme class method instance)
      (let* ((own (::scheme method))
             (bindings (append (zip (class-variables class)
                                    (append (::types instance) (::outputs instance)))
                               (map (lambda (variable) (Pair variable (Var (Own variable))))
                                    (::variables own)))))
        (Scheme (append (::variables instance) (map Own (::variables own)))
                (append (::requirements instance)
                        (map (lambda (requirement) (substituted-requirement bindings requirement))
                             (::requirements own)))
                (append (::copied instance) (map Own (::copied own)))
                (substituted bindings (::type own)))))

    (: substituted (impl (Fn (List (Pair TypeVariable Type)) Type -> Type)))
    (define (substituted bindings type)
      (match type
        ((Var variable) (bound-to bindings variable type))
        ((Con global arguments)
         (Con global (map (lambda (argument) (substituted bindings argument)) arguments)))
        ((Callable former contract arrow)
         (Callable former contract (substituted-arrow bindings arrow)))
        ((Code arrow) (Code (substituted-arrow bindings arrow)))
        ((Row effects) (Row (substituted-effects bindings effects)))))

    (: bound-to (impl (Fn (List (Pair TypeVariable Type)) TypeVariable Type -> Type)))
    (define (bound-to bindings variable type)
      (match (find (lambda (binding) (same-variable? (::first binding) variable)) bindings)
        ((Some binding) (::second binding))
        ((None) type)))

    (: substituted-arrow (impl (Fn (List (Pair TypeVariable Type)) Arrow -> Arrow)))
    (define (substituted-arrow bindings arrow)
      (Arrow (map (lambda (parameter) (substituted bindings parameter)) (::parameters arrow))
             (substituted bindings (::result arrow))
             (substituted-effects bindings (::effects arrow))))

    ;; A tail that becomes a row joins its labels.
    (: substituted-effects (impl (Fn (List (Pair TypeVariable Type)) Effects -> Effects)))
    (define (substituted-effects bindings effects)
      (match (::tail effects)
        ((None) effects)
        ((Some tail)
         (match (substituted bindings tail)
           ((Row (Effects labels rest))
            (Effects (effect-set (append (::labels effects) labels)) rest))
           (other (Effects (::labels effects) (Some other)))))))

    (: substituted-requirement
       (impl (Fn (List (Pair TypeVariable Type)) Requirement -> Requirement)))
    (define (substituted-requirement bindings requirement)
      (match requirement
        ((ClassRequirement class types)
         (ClassRequirement class (map (lambda (type) (substituted bindings type)) types)))
        ((CallableRequirement contract receiver arrow)
         (CallableRequirement contract
                              (substituted bindings receiver)
                              (substituted-arrow bindings arrow)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-schemes)
    (import
     (snail compiler source)
     (only (snail compiler expand language) Label)
     (snail stage0 testing))
    (begin
      (define (test-schemes)
        (test-data)
        (test-classes)
        (test-effects))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define i64 (Con (Global forms-library "I64" 0) (list)))
      (define (var name)
        (Var (Written name)))

      (define (fn parameters result effects)
        (Callable (Dyn) (FnContract) (Arrow parameters result (Effects effects (None)))))

      ;; (struct (Cell a) (mut value a)) and (struct Point (x I64)).
      (define (test-data)
        (let* ((value (DataField "value" #t (var "a") (list) loc))
               (cell-case (DataCase (global "Cell") 0 (list value) (list) loc))
               (cell
                (Data (global "Cell") (list "a") (list cell-case) (StructData) #f #f (list) loc))
               (cell-type (Con (global "Cell") (list (var "a"))))
               (x (DataField "x" #f i64 (list) loc))
               (point-case (DataCase (global "Point") 0 (list x) (list) loc))
               (point
                (Data (global "Point") (list) (list point-case) (StructData) #f #f (list) loc))
               (point-type (Con (global "Point") (list))))
          (expect (constructor-scheme cell cell-case)
                  (Scheme (list (Written "a"))
                          (list)
                          (list)
                          (fn (list (var "a")) cell-type (list))))
          (expect (map ::first (field-schemes cell cell-case value))
                  (list (Accessor) (Setter) (Swapper)))
          (expect (map (lambda (pair) (pure-struct? (::first pair) (::second pair)))
                       (list (Pair cell cell-case) (Pair point point-case)))
                  (list #f #t))
          (expect (::second (list-ref (field-schemes cell cell-case value) 0))
                  (Scheme (list (Written "a"))
                          (list)
                          (list)
                          (fn (list cell-type) (var "a") (list mut-effect))))
          (expect (field-schemes point point-case x)
                  (list
                   (Pair (Accessor) (Scheme (list) (list) (list) (fn (list point-type) i64 (list))))
                   (Pair (Replacer)
                         (Scheme (list)
                                 (list)
                                 (list)
                                 (fn (list point-type i64) point-type (list))))))))

      ;; (typeclass (Store e S) (: put (Fn S -> S ! e))) and its instance
      ;; (Store (! log) I64), whose implementation's row is the one row.
      (define (test-classes)
        (let* ((log (global "log"))
               (put (Method (global "put")
                            (Scheme (list (Written "b"))
                                    (list)
                                    (list)
                                    (Callable (Dyn)
                                              (FnContract)
                                              (Arrow (list (var "S") (var "b"))
                                                     (var "S")
                                                     (Effects (list) (Some (var "e"))))))
                            (list)
                            loc))
               (store (Class (global "Store")
                             (list (RowParameter "e") (TypeParameter "S"))
                             (list)
                             (list put)
                             (list)
                             loc))
               (instance (Instance (global "Store")
                                   (ClassGlobal (global "Store"))
                                   (list)
                                   (list (Row (Effects (list log) (None))) i64)
                                   (list)
                                   (list)
                                   (list)
                                   (Methods (list))
                                   loc)))
          (expect (method-scheme store put)
                  (Scheme (list (Written "e") (Written "S") (Written "b"))
                          (list (ClassRequirement (ClassGlobal (global "Store"))
                                                  (list (var "e") (var "S"))))
                          (list)
                          (::type (::scheme put))))
          (expect
           (method-scheme (Class (global "::x") field-class-parameters (list) (list) (list) loc)
                          (Method (global "::x") field-reader-scheme (list) loc))
           (Scheme (list (Written "R") (Written "T"))
                   (list (ClassRequirement (ClassGlobal (global "::x"))
                                           (list (var "R") (var "T"))))
                   (list)
                   (fn (list (var "R")) (var "T") (list))))
          (expect (implementation-scheme store put instance)
                  (Scheme (list (Own (Written "b")))
                          (list)
                          (list)
                          (Callable (Dyn)
                                    (FnContract)
                                    (Arrow (list i64 (Var (Own (Written "b"))))
                                           i64
                                           (Effects (list log) (None))))))))

      (define (test-effects)
        (let ((read (Operation (global "read") #f (list) i64 (list (global "log")) (list) loc)))
          (expect (operation-scheme (global "io") read)
                  (Scheme (list) (list) (list) (fn (list) i64 (list (global "io") (global "log")))))
          (expect (default-scheme read)
                  (Scheme (list) (list) (list) (fn (list) i64 (list (global "log")))))))))
   (else)))
