;; The pass `declare`: a derived library, and what each library in its
;; import closure offers, become the library declared and what it offers
;; the declaration of its importers. Every written type is a type, every
;; declaration its entity and every label the member it names, as
;; (snail compiler declare language) says, in the old compiler's steps,
;; which (snail compiler declare top) takes: the scan, the signatures, the
;; declarations, each seeing only those before it, and the bodies.
(define-library (snail compiler declare pass)
  (export
   declare)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (prefix (snail compiler derive language) derived-)
   (snail compiler declare language)
   (snail compiler declare offer)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare top))
  (begin

    ;; ---- The pass ----

    ;; `imported` holds what each library in the import closure offers,
    ;; and, when the library derives an instance, what (snail shell wire)
    ;; and its closure offer, since a derived instance names wire's
    ;; classes. The library offers everything it declares, as known once
    ;; its bodies are declared.
    (: declare
       (impl (Fn derived-Derived (List Declarations) -> (Result DeclaredLibrary (List Feedback)))))
    (define (declare derived imported)
      (match derived
        ((derived-Defined name tops first-unused loc)
         (result-let* ((walked (declared-tops name tops first-unused imported)))
           (Ok (DeclaredLibrary
                (Defined name (::tops walked) (::next (::numbering (::state walked))) loc)
                (offered walked)))))
        ((derived-Program tops first-unused)
         (result-let* ((walked (declared-tops program-library tops first-unused imported)))
           (Ok (DeclaredLibrary (Program (::tops walked) (::next (::numbering (::state walked))))
                                (offered walked)))))))

    (: offered (impl (Fn Walked -> Declarations)))
    (define (offered walked)
      (::declared (::known (::state walked))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-declare)
    (import
     (snail core table)
     (prefix (snail compiler expand language) expanded-)
     (only (snail compiler names globals) Global TopGlobal)
     (only (snail compiler literals constant) UnitValue)
     (prefix (snail compiler bind language) bound-)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-declare)
        (test-libraries)
        (test-programs))

      (define loc (Loc "t.sld" 1 1))
      (define lib (list "lib"))

      (define i64-type
        (expanded-Applied (Global forms-library "I64" 0) "I64" (list) loc))

      ;; (define-library (lib) ... (struct Box (x I64)) (effect io (: read (impl (Fn -> I64)))))
      (define tops
        (list (derived-Struct (Global lib "Box" 0)
                              (list)
                              (list (expanded-Field "x" #f i64-type (list) loc))
                              #f
                              (list)
                              loc
                              loc)
              (derived-Effect (Global lib "io" 0)
                              (list (expanded-Operation (Global lib "read" 0)
                                                        #f
                                                        (expanded-Scheme (list)
                                                                         (list)
                                                                         (expanded-Callable
                                                                          (expanded-Impl)
                                                                          (expanded-FnContract)
                                                                          (expanded-Arrow (list)
                                                                                          i64-type
                                                                                          (expanded-Effects
                                                                                           (list)
                                                                                           (None)))
                                                                          loc)
                                                                         loc)
                                                        (list)
                                                        loc))
                              (list)
                              #f
                              (list)
                              loc)))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define box
        (Data (Global lib "Box" 0)
              (list)
              (list (DataCase (Global lib "Box" 0)
                              0
                              (list (DataField "x" #f i64 (list) loc))
                              (list)
                              loc))
              (StructData)
              #f
              #f
              (list)
              loc))

      (define read-op (Operation (Global lib "read" 0) #f (list) i64 (list) (list) loc))

      ;; A library's tops become its entities, which it offers by name.
      (define (test-libraries)
        (match (declare (derived-Defined lib tops 4 loc) (list))
          ((Ok declared)
           (expect (::declared declared)
                   (Defined lib
                     (list (TopData box)
                           (TopEffect (Effect (Global lib "io" 0)
                                              (list read-op)
                                              (list)
                                              #f
                                              (list)
                                              loc)))
                     4
                     loc))
           (let ((offer (::declarations declared)))
             (expect (::library offer) lib)
             (expect (table-ref (::data offer) "Box") (Some (list box)))
             (expect (table-ref (::effects offer) "io")
                     (Some (list (OfferedEffect (Global lib "io" 0) (list read-op)))))))
          (other (expect other "a declared library"))))

      ;; A program's statements are declared where they are written, as a
      ;; library's are.
      (define (test-programs)
        (expect (declare (derived-Program (list (derived-Statement
                                                 (bound-CaseId
                                                  (TopGlobal (Global (list "main")
                                                                     "f"
                                                                     0))
                                                  loc
                                                  loc)))
                                          1)
                         (list))
                (fail loc "not a constructor"))
        (match (declare
                (derived-Program (list (derived-Statement (bound-Literal (UnitValue) loc)))
                                 1)
                (list))
          ((Ok declared)
           (expect (::declared declared)
                   (Program (list (Statement (Literal (UnitValue) loc))) 1))
           (expect (::library (::declarations declared)) (list "main")))
          (other (expect other "a declared program"))))))
   (else)))
