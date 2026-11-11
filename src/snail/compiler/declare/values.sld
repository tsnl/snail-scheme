;; Values: what a library's signatures say of the values they name, and
;; the values whose declarations write a type, externs and primitives.
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
   declared-extern
   declared-primitive
   definition)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (prefix (snail compiler derive language) derived-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality)
   (snail compiler declare callables)
   (snail compiler declare types))
  (begin

    ;; ---- Signatures ----

    ;; Each signature written for a Global of the library, in order, kept
    ;; by the Global's name.
    (struct Signatures
      ((written (Table (List WrittenSignature)))))

    (struct WrittenSignature
      ((target expanded-Global)
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
       (impl (Fn Signatures expanded-TopValue Signed (List expanded-Annotation) -> Signatures)))
    (define (with-signature signatures target signed annotations)
      (match target
        ((expanded-TopGlobal global)
         (Signatures (by-name (::written signatures)
                              (::name global)
                              (WrittenSignature global signed annotations))))
        ((expanded-FieldFunction _ _ _) signatures)))

    (: written-for (impl (Fn Signatures expanded-Global -> (List WrittenSignature))))
    (define (written-for signatures global)
      (match (table-ref (::written signatures) (::name global))
        ((Some written) (filter (lambda (entry) (same-global? (::target entry) global)) written))
        ((None) (Nil))))

    ;; The last signature written for `global`, if any.
    (: signed (impl (Fn Signatures expanded-Global -> (Option Signed))))
    (define (signed signatures global)
      (match (reverse (written-for signatures global))
        ((Cons last _) (Some (::signed last)))
        ((Nil) (None))))

    ;; The annotations of every signature written for `global`, in order.
    (: signature-annotations (impl (Fn Signatures expanded-Global -> (List expanded-Annotation))))
    (define (signature-annotations signatures global)
      (concatenate (map ::annotations (written-for signatures global))))

    ;; ---- Definitions ----

    ;; A definition whose value is declared, with what its signatures say.
    (: definition (impl (Fn Signatures expanded-Global Expr Loc -> Top)))
    (define (definition signatures global value loc)
      (Define global
        value
        (signed signatures global)
        (signature-annotations signatures global)
        loc))

    ;; ---- Externs and primitives ----

    ;; An extern's type is a type, not a scheme, so it is held to no rule
    ;; of callables; it is executable code's, its arrow, as the old
    ;; compiler's `declare-extern` makes it.
    (: declared-extern
       (impl (Fn Known
                 Signatures
                 expanded-Global
                 String
                 String
                 expanded-TypeExpr
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result Top (List Feedback)))))
    (define (declared-extern known signatures global module symbol type annotations loc)
      (result-let* ((declared (declared-type (Scope known (Nil)) type)))
        (Ok (Extern global
                    module
                    symbol
                    (operational-type declared)
                    (append annotations (signature-annotations signatures global))
                    loc))))

    ;; A primitive's scheme is executable code's; `callable-once` stays the
    ;; compiler's own.
    (: declared-primitive
       (impl
        (Fn Known expanded-Global expanded-PrimitiveType Loc -> (Result Top (List Feedback)))))
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
     (prefix (only (snail compiler bind language) Literal) bound-)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-values)
        (test-signatures)
        (test-externs)
        (test-primitives))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (expanded-Global main name 0))

      (define (builtin name)
        (expanded-Global forms-library name 0))

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
        (derived-Signature (expanded-TopGlobal (global name)) (written type line) notes (at line)))

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
                            (expanded-FieldFunction (global "P") "x" (expanded-Replacer))
                            (written (applied "I64" 4) 4)
                            (list (note "field"))
                            (at 4))
                           (derived-Define (global "x")
                                           (bound-Literal (expanded-UnitValue) loc)
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
                  (fail (at 8) "wrong number of type arguments: Array"))))

      ;; A primitive's scheme is operational; callable-once stays.
      (define (test-primitives)
        (let ((once (expanded-Global (list "prim") "once" 0))
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
