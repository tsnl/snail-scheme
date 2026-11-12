;; Values: what a library's signatures say of the values they name, a
;; definition's body, and the values whose declarations write a type,
;; externs and primitives.
;;
;; Every signature is converted before any declaration, in the order
;; written, those under a top-level `with-instances` among them, and the
;; first problem stops the library, as the old compiler resolves its
;; signature table first (`with-signature`). So a signature sees only what
;; the scan knows of the library's own classes: every parameter a type.
;; The last signature written for a definition is the one it carries, as
;; the old table keeps the last; the annotations of every signature written
;; for a value of the library stay with that value, on the definition or
;; on the entity that declares it. A signature for a field function, or
;; for a value another library declares, is converted and leaves nothing,
;; since the old compiler records its annotations under a name no entity
;; has.
(define-library (snail compiler declare values)
  (export
   Signatures
   declared-signatures
   signed
   signature-annotations
   declared-definition
   declared-extern
   declared-primitive)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (prefix (snail compiler bind language) bound-)
   (prefix (snail compiler derive language) derived-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare equality)
   (only (snail compiler names globals) Global TopValue TopGlobal FieldFunction same-global?)
   (snail compiler declare requirements)
   (snail compiler declare callables)
   (snail compiler declare host)
   (snail compiler declare types)
   (snail compiler declare expressions))
  (begin

    ;; ---- Signatures ----

    ;; Each signature written for a Global of the library, in order, kept
    ;; by the Global's name.
    (struct Signatures
      ((written (Table (List WrittenSignature)))))

    (struct WrittenSignature
      ((target Global)
       (signed Signed)
       (annotations (List expanded-Annotation))))

    ;; The signatures among `tops`, each converted where nothing of the
    ;; library is declared yet and no requirement is in scope.
    (: declared-signatures
       (impl (Fn Known (List derived-Top) -> (Result Signatures (List Feedback)))))
    (define (declared-signatures known tops)
      (signatures-in known (Signatures empty-table) tops))

    (: signatures-in
       (impl (Fn Known Signatures (List derived-Top) -> (Result Signatures (List Feedback)))))
    (define (signatures-in known signatures tops)
      (match tops
        ((Nil) (Ok signatures))
        ((Cons top rest)
         (result-let* ((more (top-signatures known signatures top)))
           (signatures-in known more rest)))))

    (: top-signatures
       (impl (Fn Known Signatures derived-Top -> (Result Signatures (List Feedback)))))
    (define (top-signatures known signatures top)
      (match top
        ((derived-Signature target scheme annotations loc)
         (result-let* ((declared (declared-scheme (Scope known (Nil)) scheme)))
           (Ok (with-signature signatures target (Signed declared loc) annotations))))
        ((derived-InstanceScope _ inner _) (signatures-in known signatures inner))
        (_ (Ok signatures))))

    (: with-signature
       (impl (Fn Signatures TopValue Signed (List expanded-Annotation) -> Signatures)))
    (define (with-signature signatures target signed annotations)
      (match target
        ((TopGlobal global)
         (Signatures (by-name (::written signatures)
                              (::name global)
                              (WrittenSignature global signed annotations))))
        ((FieldFunction _ _ _) signatures)))

    (: written-for (impl (Fn Signatures Global -> (List WrittenSignature))))
    (define (written-for signatures global)
      (match (table-ref (::written signatures) (::name global))
        ((Some written) (filter (lambda (entry) (same-global? (::target entry) global)) written))
        ((None) (Nil))))

    ;; The last signature written for `global`, if any.
    (: signed (impl (Fn Signatures Global -> (Option Signed))))
    (define (signed signatures global)
      (match (reverse (written-for signatures global))
        ((Cons last _) (Some (::signed last)))
        ((Nil) (None))))

    ;; The annotations of every signature written for `global`, in order.
    (: signature-annotations (impl (Fn Signatures Global -> (List expanded-Annotation))))
    (define (signature-annotations signatures global)
      (concatenate (map ::annotations (written-for signatures global))))

    ;; ---- Definitions ----

    ;; A definition's body, declared once every declaration is reached:
    ;; first the requirements of its signature, the last written for it,
    ;; checked again at the signature, since each class of the library is
    ;; now known whole, which no class of its own was where the signature
    ;; was converted; then its value. The first problem stops the body, as
    ;; the old compiler's `check-signature` does before the definition's
    ;; value is expanded. Only a definition's signature is checked again:
    ;; one written for any other value was checked only where it was
    ;; converted.
    (: declared-definition
       (impl (Fn Known
                 Signatures
                 Global
                 bound-Expr
                 Loc
                 ->
                 (Result Top (List Feedback)))))
    (define (declared-definition known signatures global value loc)
      (let ((signature (signed signatures global)))
        (result-let* ((complete (signature-check known signature))
                      (declared (declared-expr known value)))
          (Ok (Define global declared signature (signature-annotations signatures global) loc)))))

    (: signature-check (impl (Fn Known (Option Signed) -> (Result Unit (List Feedback)))))
    (define (signature-check known signature)
      (match signature
        ((Some found)
         (checked (requirements-problem known (::requirements (::scheme found))) (::loc found)))
        ((None) (Ok (unit)))))

    ;; ---- Externs and primitives ----

    ;; An extern's type is a type, not a scheme, so it is held to no rule
    ;; of callables; it is executable code's, its arrow, as the old
    ;; compiler's `declare-extern` makes it, and what a host function may
    ;; take, refused at the type.
    (: declared-extern
       (impl (Fn Known
                 Signatures
                 Global
                 String
                 String
                 expanded-TypeExpr
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result Top (List Feedback)))))
    (define (declared-extern known signatures global module symbol type annotations loc)
      (result-let* ((declared (declared-type (Scope known (Nil)) type)))
        (let ((code (operational-type declared)))
          (result-let* ((staged (checked (host-problem code) (type-loc type))))
            (Ok (Extern global
                        module
                        symbol
                        code
                        (append annotations (signature-annotations signatures global))
                        loc))))))

    ;; A primitive's scheme is executable code's; `callable-once` stays the
    ;; compiler's own.
    (: declared-primitive
       (impl
        (Fn Known Global expanded-PrimitiveType Loc -> (Result Top (List Feedback)))))
    (define (declared-primitive known global type loc)
      (match type
        ((expanded-PrimitiveScheme scheme)
         (result-let* ((declared (declared-scheme (Scope known (Nil)) scheme)))
           (Ok (Primitive global (PrimitiveScheme (operational-scheme declared)) loc))))
        ((expanded-CallableOnce) (Ok (Primitive global (CallableOnce) loc)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-values)
    (import
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler names globals) Replacer ClassGlobal)
     (only (snail compiler literals constant) UnitValue)
     (snail stage0 testing))
    (begin
      (define (test-values)
        (test-signatures)
        (test-definitions)
        (test-externs)
        (test-primitives))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define (builtin name)
        (Global forms-library name 0))

      ;; (main) scans the class (Show a) with the output Out.
      (define known
        (Known main
               (Scanned empty-table
                        (by-name empty-table
                                 "Show"
                                 (ScannedClass (global "Show") (list "a") (list "Out"))))
               (Declarations main empty-table empty-table empty-table)
               (list)))

      (define (applied name line)
        (expanded-Applied (builtin name) name (list) (at line)))

      (define (written type line)
        (expanded-Scheme (list) (list) type (at line)))

      (define (note text)
        (expanded-Documentation text loc))

      (define (signature name type line notes)
        (derived-Signature (TopGlobal (global name)) (written type line) notes (at line)))

      (define i64 (Con (builtin "I64") (list)))

      ;; In order, under an instance scope too; the last for a Global wins,
      ;; and every one's annotations stay, in order. A field function's is
      ;; converted and kept nowhere.
      (define (test-signatures)
        (let* ((tops (list (signature "x" (applied "Bool" 2) 2 (list (note "first")))
                           (derived-InstanceScope
                            (list (global "set"))
                            (list (signature "x" (applied "I64" 3) 3 (list (note "second"))))
                            loc)
                           (derived-Signature
                            (FieldFunction (global "P") "x" (Replacer))
                            (written (applied "I64" 4) 4)
                            (list (note "field"))
                            (at 4))
                           (derived-Define (global "x")
                                           (bound-Literal (UnitValue) loc)
                                           loc)))
               (result (declared-signatures known tops)))
          (match result
            ((Ok signatures)
             (expect (signed signatures (global "x"))
                     (Some (Signed (Scheme (list) (list) (list) i64) (at 3))))
             (expect (signed signatures (global "y")) (None))
             (expect (signature-annotations signatures (global "x"))
                     (list (note "first") (note "second")))
             (expect (signature-annotations signatures (global "P")) (list)))
            (_ (expect result "the signatures")))
          ;; The first problem stops them.
          (expect (declared-signatures known
                                       (list (signature "x"
                                                        (expanded-Applied (builtin "Array")
                                                                          "Array"
                                                                          (list)
                                                                          (at 5))
                                                        5
                                                        (list))
                                             (signature "y"
                                                        (expanded-Applied (builtin "Vector")
                                                                          "Vector"
                                                                          (list)
                                                                          (at 6))
                                                        6
                                                        (list))))
                  (fail (at 5) "wrong number of type arguments: Array"))))

      ;; (main)'s class (Store e S), whose e is a row: by its scan where the
      ;; signatures are converted, and declared once the bodies are.
      (define store (global "Store"))

      (define store-scanned
        (Scanned empty-table
                 (by-name empty-table "Store" (ScannedClass store (list "e" "S") (list)))))

      (define store-known
        (Known main
               store-scanned
               (Declarations main empty-table empty-table empty-table)
               (list)))

      (define complete-known
        (Known main
               store-scanned
               (Declarations main
                             empty-table
                             (by-name empty-table
                                      "Store"
                                      (Class store
                                             (list (RowParameter "e") (TypeParameter "S"))
                                             (list)
                                             (list)
                                             (list)
                                             loc))
                             empty-table)
               (list)))

      ;; `(: f (All (S) (requires (Store row S)) I64))`, at line 2.
      (define (store-signatures row)
        (match (declared-signatures
                store-known
                (list (derived-Signature (TopGlobal (global "f"))
                                         (expanded-Scheme
                                          (list "S")
                                          (list (expanded-ClassRequirement
                                                 (ClassGlobal store)
                                                 (list row (expanded-Variable "S" loc))
                                                 (list)
                                                 (at 3)))
                                          (applied "I64" 3)
                                          (at 3))
                                         (list)
                                         (at 2))))
          ((Ok found) found)
          ((Err _) (panic "the signature"))))

      ;; Read off error-class-row-requires-row.sld: where the signatures
      ;; are converted the class is its scan, so its row is not checked;
      ;; the definition's body checks it again, at the signature, before
      ;; its value, which is then never looked at.
      (define (test-definitions)
        (let ((bad-value (bound-Ann (bound-Literal (UnitValue) (at 4))
                                    (expanded-Applied (builtin "Array") "Array" (list) (at 5))
                                    (at 4)))
              (closed (expanded-Row (expanded-Effects (list) (None)) loc)))
          (expect (declared-definition complete-known
                                       (store-signatures (applied "I64" 3))
                                       (global "f")
                                       bad-value
                                       (at 4))
                  (fail (at 2) "a constraint gives the class's row parameter e a row"))
          (expect (declared-definition complete-known
                                       (store-signatures closed)
                                       (global "f")
                                       bad-value
                                       (at 4))
                  (fail (at 5) "wrong number of type arguments: Array"))
          (expect (declared-definition complete-known
                                       (store-signatures closed)
                                       (global "f")
                                       (bound-Literal (UnitValue) (at 4))
                                       (at 4))
                  (Ok (Define (global "f")
                        (Literal (UnitValue) (at 4))
                        (signed (store-signatures closed) (global "f"))
                        (list)
                        (at 4))))
          ;; A definition with no signature has nothing to check again.
          (expect (declared-definition complete-known
                                       (store-signatures closed)
                                       (global "g")
                                       (bound-Literal (UnitValue) (at 6))
                                       (at 6))
                  (Ok (Define (global "g")
                        (Literal (UnitValue) (at 6))
                        (None)
                        (list)
                        (at 6))))))

      ;; An extern's type is its arrow, whatever callable it was written as,
      ;; with its annotations and its signatures'.
      (define (test-externs)
        (let* ((arrow (expanded-Arrow (list (applied "I64" 1))
                                      (applied "I64" 1)
                                      (expanded-Effects (list) (None))))
               (signatures (match (declared-signatures known
                                                       (list (signature "now"
                                                                        (applied "I64" 7)
                                                                        7
                                                                        (list (note "signed")))))
                             ((Ok found) found)
                             ((Err _) (panic "the signatures")))))
          (expect (declared-extern known
                                   signatures
                                   (global "now")
                                   "host"
                                   "now"
                                   (expanded-Callable (expanded-Impl)
                                                      (expanded-FnOnceContract)
                                                      arrow
                                                      loc)
                                   (list (note "own"))
                                   loc)
                  (Ok (Extern (global "now")
                              "host"
                              "now"
                              (Callable (expanded-Dyn)
                                        (expanded-FnContract)
                                        (Arrow (list i64) i64 (Effects (list) (None))))
                              (list (note "own") (note "signed"))
                              loc)))
          (expect (declared-extern known
                                   signatures
                                   (global "bad")
                                   "host"
                                   "bad"
                                   (expanded-Applied (builtin "Array") "Array" (list) (at 8))
                                   (list)
                                   loc)
                  (fail (at 8) "wrong number of type arguments: Array"))
          ;; A host function takes a buffer only last, refused at its type
          ;; (error-host-buffer-position.sld).
          (expect (declared-extern known
                                   signatures
                                   (global "greet")
                                   "host"
                                   "greet"
                                   (expanded-Callable (expanded-Impl)
                                                      (expanded-FnContract)
                                                      (expanded-Arrow (list (applied "String" 9)
                                                                            (applied "I64" 9))
                                                                      (applied "Unit" 9)
                                                                      (expanded-Effects (list)
                                                                                        (None)))
                                                      (at 10))
                                   (list)
                                   loc)
                  (fail (at 10)
                        "a host function can take a String or Bytes only as its last argument"))))

      ;; A primitive's scheme is operational; callable-once stays.
      (define (test-primitives)
        (let ((once (Global (list "prim") "once" 0))
              (code (expanded-Code
                     (expanded-Arrow (list) (applied "Unit" 1) (expanded-Effects (list) (None)))
                     loc)))
          (expect (declared-primitive known once (expanded-CallableOnce) loc)
                  (Ok (Primitive once (CallableOnce) loc)))
          (expect (declared-primitive known once (expanded-PrimitiveScheme (written code 1)) loc)
                  (Ok (Primitive once
                                 (PrimitiveScheme
                                  (Scheme (list)
                                          (list)
                                          (list)
                                          (Callable (expanded-Dyn)
                                                    (expanded-FnContract)
                                                    (Arrow (list)
                                                           (Con (builtin "Unit") (list))
                                                           (Effects (list) (None))))))
                                 loc)))))))
   (else)))
