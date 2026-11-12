;; Classes: a class becomes its Class, as the old compiler's
;; `declare-class` (src/snail/shell/compiler/expand.sld) declares it. Each
;; method's scheme is converted in order, over the class's parameters and
;; outputs, in the scope of the class's own requirement `(Class parameter
;; ... output ...)`, so a projection of the class names that requirement's
;; output; the first problem stops the declaration. The class itself is
;; known there by its shape alone, every parameter a type, since its
;; declaration is reached only once its methods are. A method's scheme is
;; executable code's. Then each written parameter's kind is found from the
;; methods' types: a row when one ends a row with it. A parameter written
;; both as a row and as a type, or an output that is a row, is refused at
;; the class, once every method's scheme is converted.
(define-library (snail compiler declare classes)
  (export
   declared-class)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler names globals) Global ClassGlobal)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare callables)
   (snail compiler declare kinds)
   (snail compiler declare types)
   (snail compiler declare values))
  (begin

    ;; ---- Classes ----

    (: declared-class
       (impl (Fn Known
                 Signatures
                 Global
                 (List String)
                 (List expanded-Member)
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result Class (List Feedback)))))
    (define (declared-class known signatures global parameters members annotations loc)
      (let* ((outputs (class-outputs members))
             (scope (Scope known (list (own-requirement global parameters outputs)))))
        (result-let* ((methods (map-results (lambda (signature)
                                              (class-method scope signatures signature))
                                            (method-signatures members)))
                      (kinds (parameter-kinds parameters outputs methods loc)))
          (Ok (Class global kinds outputs methods annotations loc)))))

    ;; Each written parameter's kind, from the methods' types, refused at
    ;; the class.
    (: parameter-kinds
       (impl (Fn (List String)
                 (List Output)
                 (List Method)
                 Loc
                 ->
                 (Result (List ClassParameter) (List Feedback)))))
    (define (parameter-kinds parameters outputs methods loc)
      (match (class-parameters parameters
                               (map (lambda (output) (::name (::label output))) outputs)
                               (map (lambda (method) (::type (::scheme method))) methods))
        ((Ok kinds) (Ok kinds))
        ((Err message) (fail loc message))))

    ;; `(Class parameter ... output ...)`, each a variable.
    (: own-requirement (impl (Fn Global (List String) (List Output) -> Requirement)))
    (define (own-requirement global parameters outputs)
      (ClassRequirement (ClassGlobal global)
                        (map (lambda (name) (Var (Written name)))
                             (append parameters
                                     (map (lambda (output) (::name (::label output))) outputs)))))

    ;; ---- Members ----

    (: class-outputs (impl (Fn (List expanded-Member) -> (List Output))))
    (define (class-outputs members)
      (concatenate (map (lambda (member)
                          (match member
                            ((expanded-AssociatedOutput label annotations)
                             (list (Output label annotations)))
                            ((expanded-MethodSignature _ _ _ _) (Nil))))
                        members)))

    (: method-signatures (impl (Fn (List expanded-Member) -> (List expanded-Member))))
    (define (method-signatures members)
      (filter (lambda (member)
                (match member
                  ((expanded-MethodSignature _ _ _ _) #t)
                  ((expanded-AssociatedOutput _ _) #f)))
              members))

    ;; `method-signatures` holds only methods, so the other case is none.
    (: class-method (impl (Fn Scope Signatures expanded-Member -> (Result Method (List Feedback)))))
    (define (class-method scope signatures member)
      (match member
        ((expanded-MethodSignature global scheme annotations loc)
         (result-let* ((declared (declared-scheme scope scheme)))
           (Ok (Method global
                       (operational-scheme declared)
                       (append annotations (signature-annotations signatures global))
                       loc))))
        ((expanded-AssociatedOutput _ _) (panic "declare: an output is no method"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-classes)
    (import
     (snail core table)
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler names globals) Label)
     (snail stage0 testing))
    (begin
      (define (test-classes)
        (test-methods)
        (test-kinds)
        (test-problems))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define (builtin name)
        (Global forms-library name 0))

      ;; (main) scans the class (Collect c) with the output Item, and the
      ;; class (Store e s).
      (define known
        (Known main
               (Scanned empty-table
                        (by-name (by-name empty-table
                                          "Collect"
                                          (ScannedClass (global "Collect")
                                                        (list "c")
                                                        (list "Item")))
                                 "Store"
                                 (ScannedClass (global "Store") (list "e" "s") (list))))
               (Declarations main empty-table empty-table empty-table)
               (list)))

      (define no-signatures
        (match (declared-signatures known (list))
          ((Ok signatures) signatures)
          ((Err _) (panic "no signatures"))))

      (define (variable name)
        (expanded-Variable name loc))

      (define (applied name arguments line)
        (expanded-Applied (builtin name) name arguments (at line)))

      (define (function parameters result effects)
        (expanded-Callable (expanded-Impl)
                           (expanded-FnContract)
                           (expanded-Arrow parameters result effects)
                           loc))

      (define pure (expanded-Effects (list) (None)))

      (define (method name type line)
        (expanded-MethodSignature (global name)
                                  (expanded-Scheme (list) (list) type (at line))
                                  (list)
                                  (at line)))

      (define item-output (expanded-AssociatedOutput (Label "Item" (at 2)) (list)))

      (define (var name)
        (Var (Written name)))

      ;; A method's scheme is converted over the class's parameters and
      ;; outputs, a projection of the class naming its own requirement's
      ;; output, and is executable code's.
      (define (test-methods)
        (expect (declared-class known
                                no-signatures
                                (global "Collect")
                                (list "c")
                                (list item-output
                                      (method "first"
                                              (function (list (variable "c"))
                                                        (expanded-Projection (global "Collect")
                                                                             "Item"
                                                                             (list (variable "c"))
                                                                             loc)
                                                        pure)
                                              3))
                                (list)
                                loc)
                (Ok (Class (global "Collect")
                           (list (TypeParameter "c"))
                           (list (Output (Label "Item" (at 2)) (list)))
                           (list (Method (global "first")
                                         (Scheme (list)
                                                 (list)
                                                 (list)
                                                 (Callable (expanded-Dyn)
                                                           (expanded-FnContract)
                                                           (Arrow (list (var "c"))
                                                                  (var "Item")
                                                                  (Effects (list) (None)))))
                                         (list)
                                         (at 3)))
                           (list)
                           loc))))

      ;; A parameter a method's type ends a row with is a row.
      (define (test-kinds)
        (match (declared-class known
                               no-signatures
                               (global "Store")
                               (list "e" "s")
                               (list (method "fetch"
                                             (function (list (variable "s"))
                                                       (applied "String" (list) 4)
                                                       (expanded-Effects (list)
                                                                         (Some (variable "e"))))
                                             4))
                               (list)
                               loc)
          ((Ok class) (expect (::parameters class) (list (RowParameter "e") (TypeParameter "s"))))
          (other (expect other "a class"))))

      ;; The methods in order, the first problem stopping them; then the
      ;; kinds, refused at the class: a row written as a type, then an
      ;; output that is a row (error-class-row-kind.sld and
      ;; error-associated-row.sld).
      (define (test-problems)
        (expect (declared-class known
                                no-signatures
                                (global "Store")
                                (list "e" "s")
                                (list (method "a" (applied "Array" (list) 5) 5)
                                      (method "b" (applied "Vector" (list) 6) 6))
                                (list)
                                loc)
                (fail (at 5) "wrong number of type arguments: Array"))
        (expect (declared-class known
                                no-signatures
                                (global "Store")
                                (list "e" "s")
                                (list (method "mixed"
                                              (function (list (variable "e"))
                                                        (applied "Unit" (list) 7)
                                                        (expanded-Effects (list)
                                                                          (Some (variable "e"))))
                                              7)
                                      (method "b" (applied "Vector" (list) 8) 8))
                                (list)
                                (at 6))
                (fail (at 8) "wrong number of type arguments: Vector"))
        (expect (declared-class known
                                no-signatures
                                (global "Store")
                                (list "e" "s")
                                (list (method "mixed"
                                              (function (list (variable "e"))
                                                        (applied "Unit" (list) 7)
                                                        (expanded-Effects (list)
                                                                          (Some (variable "e"))))
                                              7))
                                (list)
                                (at 6))
                (fail (at 6) "the class parameter e is written both as a row and as a type"))
        (expect (declared-class known
                                no-signatures
                                (global "Collect")
                                (list "c")
                                (list item-output
                                      (method "bad"
                                              (function (list (variable "c"))
                                                        (variable "c")
                                                        (expanded-Effects (list)
                                                                          (Some (variable "Item"))))
                                              9))
                                (list)
                                (at 10))
                (fail (at 10) "an associated type must have kind Type, not an effect row")))))
   (else)))
