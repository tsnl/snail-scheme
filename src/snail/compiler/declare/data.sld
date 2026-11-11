;; Data: a struct or an enum becomes its Data, as the old compiler's
;; `declare-data` (src/snail/shell/compiler/expand.sld) declares it. Each
;; case's fields are converted in order, over the type's parameters, where
;; no requirement is in scope, so a projection in a field is refused; the
;; first problem stops the declaration. A case is tagged by its position,
;; and a struct is the one case its own Global constructs. A constructor's
;; annotations are its case's and those of every signature written for it.
;;
;; Whether the library declares a Drop instance for the type is not known
;; here: the instance may be written before the type or after it, and the
;; old compiler reads it only once every declaration is reached. So a type
;; is declared without one, and the top level says, once every declaration
;; is reached, which types have one.
(define-library (snail compiler declare data)
  (export
   struct-data
   enum-data)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare types)
   (snail compiler declare values))
  (begin

    ;; ---- Structs ----

    ;; `name-loc` is where the struct's name is written, its constructor's
    ;; place.
    (: struct-data
       (impl (Fn Known
                 Signatures
                 expanded-Global
                 (List String)
                 (List expanded-Field)
                 Bool
                 (List expanded-Annotation)
                 Loc
                 Loc
                 ->
                 (Result Data (List Feedback)))))
    (define (struct-data known signatures global parameters fields move? annotations name-loc loc)
      (result-let* ((declared (map-results (lambda (field) (struct-field known field)) fields)))
        (Ok (Data global
                  parameters
                  (list (DataCase global
                                  0
                                  declared
                                  (signature-annotations signatures global)
                                  name-loc))
                  (StructData)
                  move?
                  #f
                  annotations
                  loc))))

    (: struct-field (impl (Fn Known expanded-Field -> (Result DataField (List Feedback)))))
    (define (struct-field known field)
      (result-let* ((type (field-type known (::type field))))
        (Ok (DataField (::label field)
                       (::mutable? field)
                       type
                       (::annotations field)
                       (::loc field)))))

    ;; ---- Enums ----

    (: enum-data
       (impl (Fn Known
                 Signatures
                 expanded-Global
                 (List String)
                 (List expanded-Case)
                 Bool
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result Data (List Feedback)))))
    (define (enum-data known signatures global parameters cases move? annotations loc)
      (result-let* ((declared (map-results (lambda (tagged)
                                             (enum-case known
                                                        signatures
                                                        (::first tagged)
                                                        (::second tagged)))
                                           (zip (iota (length cases)) cases))))
        (Ok (Data global parameters declared (EnumData) move? #f annotations loc))))

    (: enum-case
       (impl (Fn Known Signatures I64 expanded-Case -> (Result DataCase (List Feedback)))))
    (define (enum-case known signatures tag case)
      (result-let* ((fields
                     (map-results (lambda (field) (case-field known field)) (::fields case))))
        (Ok (DataCase (::global case)
                      tag
                      fields
                      (append (::annotations case)
                              (signature-annotations signatures (::global case)))
                      (::loc case)))))

    ;; An enum's fields are never mutable.
    (: case-field (impl (Fn Known expanded-CaseField -> (Result DataField (List Feedback)))))
    (define (case-field known field)
      (result-let* ((type (field-type known (::type field))))
        (Ok (DataField (::label field) #f type (::annotations field) (::loc field)))))

    ;; ---- Fields ----

    (: field-type (impl (Fn Known expanded-TypeExpr -> (Result Type (List Feedback)))))
    (define (field-type known type)
      (declared-type (Scope known (Nil)) type))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-data)
    (import
     (snail core table)
     (prefix (only (snail compiler derive language) Signature) derived-)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-data)
        (test-structs)
        (test-enums))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (expanded-Global main name 0))

      ;; (main) scans (Box a), (Tree a) and the class (Show a) with output
      ;; Out.
      (define known
        (Known main
               (Scanned (by-name (by-name empty-table "Box" (ScannedType (global "Box") (list "a")))
                                 "Tree"
                                 (ScannedType (global "Tree") (list "a")))
                        (by-name empty-table
                                 "Show"
                                 (ScannedClass (global "Show") (list "a") (list "Out"))))
               (Declarations main empty-table empty-table empty-table)
               (list)))

      (define no-signatures
        (match (declared-signatures known (list))
          ((Ok signatures) signatures)
          ((Err _) (panic "no signatures"))))

      (define (i64-at line)
        (expanded-Applied (expanded-Global forms-library "I64" 0) "I64" (list) (at line)))

      (define (box-of argument line)
        (expanded-Applied (global "Box") "Box" (list argument) (at line)))

      (define i64 (Con (expanded-Global forms-library "I64" 0) (list)))

      (define (note text)
        (expanded-Documentation text loc))

      ;; A struct is its one case, its constructor at its name; a field
      ;; keeps its label, whether it is mutable, and its annotations.
      (define (test-structs)
        (expect (struct-data known
                             no-signatures
                             (global "Cell")
                             (list "a")
                             (list (expanded-Field "value"
                                                   #t
                                                   (expanded-Variable "a" loc)
                                                   (list (note "v"))
                                                   (at 2))
                                   (expanded-Field "count" #f (box-of (i64-at 3) 3) (list) (at 3)))
                             #t
                             (list (note "cell"))
                             (at 4)
                             (at 5))
                (Ok (Data (global "Cell")
                          (list "a")
                          (list (DataCase (global "Cell")
                                          0
                                          (list (DataField "value"
                                                           #t
                                                           (Var (Written "a"))
                                                           (list (note "v"))
                                                           (at 2))
                                                (DataField "count"
                                                           #f
                                                           (Con (global "Box") (list i64))
                                                           (list)
                                                           (at 3)))
                                          (list)
                                          (at 4)))
                          (StructData)
                          #t
                          #f
                          (list (note "cell"))
                          (at 5))))
        ;; The fields in order, the first problem stopping them.
        (expect (struct-data known
                             no-signatures
                             (global "P")
                             (list)
                             (list (expanded-Field "a" #f (box-of (i64-at 6) 6) (list) (at 6))
                                   (expanded-Field "b"
                                                   #f
                                                   (expanded-Applied (global "Box")
                                                                     "Box"
                                                                     (list)
                                                                     (at 7))
                                                   (list)
                                                   (at 7))
                                   (expanded-Field "c"
                                                   #f
                                                   (expanded-Applied (global "Box")
                                                                     "B"
                                                                     (list)
                                                                     (at 8))
                                                   (list)
                                                   (at 8)))
                             #f
                             (list)
                             loc
                             loc)
                (fail (at 7) "wrong number of type arguments: Box"))
        ;; No requirement is in scope, so a projection is refused.
        (expect (struct-data known
                             no-signatures
                             (global "Q")
                             (list "a")
                             (list (expanded-Field "f"
                                                   #f
                                                   (expanded-Projection (global "Show")
                                                                        "Out"
                                                                        (list (expanded-Variable "a"
                                                                                                 loc))
                                                                        (at 9))
                                                   (list)
                                                   (at 9)))
                             #f
                             (list)
                             loc
                             loc)
                (fail (at 9) "associated projection needs a matching requires constraint")))

      ;; Each case tagged by its position, with its constructor's
      ;; annotations and its signatures'.
      (define (test-enums)
        (let ((signatures (match (declared-signatures
                                  known
                                  (list (signature-of "Leaf")))
                            ((Ok found) found)
                            ((Err _) (panic "the signatures")))))
          (expect (enum-data known
                             signatures
                             (global "Tree")
                             (list "a")
                             (list
                              (expanded-Case (global "Leaf") (list) (list (note "leaf")) (at 2))
                              (expanded-Case (global "Node")
                                             (list (expanded-CaseField "left"
                                                                       (box-of
                                                                        (expanded-Variable "a" loc)
                                                                        3)
                                                                       (list)
                                                                       (at 3)))
                                             (list)
                                             (at 3)))
                             #f
                             (list)
                             loc)
                  (Ok (Data (global "Tree")
                            (list "a")
                            (list (DataCase (global "Leaf")
                                            0
                                            (list)
                                            (list (note "leaf") (note "signed"))
                                            (at 2))
                                  (DataCase (global "Node")
                                            1
                                            (list (DataField "left"
                                                             #f
                                                             (Con (global "Box")
                                                                  (list (Var (Written "a"))))
                                                             (list)
                                                             (at 3)))
                                            (list)
                                            (at 3)))
                            (EnumData)
                            #f
                            #f
                            (list)
                            loc)))))

      ;; A signature for the value `name`, of the type (Tree I64).
      (define (signature-of name)
        (derived-Signature (expanded-TopGlobal (global name))
                           (expanded-Scheme (list)
                                            (list)
                                            (expanded-Applied (global "Tree")
                                                              "Tree"
                                                              (list (i64-at 1))
                                                              loc)
                                            loc)
                           (list (note "signed"))
                           loc))))
   (else)))
