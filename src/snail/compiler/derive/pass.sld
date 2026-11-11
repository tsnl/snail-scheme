;; The pass `derive`: a bound library, and the offers of the implicit
;; libraries, become the library derived. Each `deriving` clause is what it
;; asks for: Move is said on its type, and Serialize and Deserialize are
;; instances, built by (snail compiler derive instances) of the names the
;; implicit libraries offer and placed right after their declaration,
;; where the old expander scans the instances it writes as syntax. Nothing
;; resolves in the library's own scope. A name the implicit libraries do
;; not offer is a problem, reported as the old expander reports it: the
;; first problem of an instance's head alone, since it ends the library's
;; declarations, and otherwise the problem of each instance's body.
(define-library (snail compiler derive pass)
  (export
   derive)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler expand offer) Offered)
   (prefix (snail compiler bind language) bound-)
   (snail compiler derive language)
   (snail compiler derive implicit)
   (snail compiler derive instances))
  (begin

    ;; ---- The pass ----

    ;; `offers` are the implicit libraries', (snail core primitive) and
    ;; (snail shell wire), in that order, as far as they are loaded.
    (: derive (impl (Fn bound-Bound (List Offered) -> (Result Derived (List Feedback)))))
    (define (derive bound offers)
      (let ((names (wire-names offers)))
        (match bound
          ((bound-Defined name tops first-unused loc)
           (result-let* ((walked (derived-tops names tops first-unused)))
             (Ok (Defined name (::tops walked) (::next walked) loc))))
          ((bound-Program tops body first-unused)
           (result-let* ((walked (derived-tops names tops first-unused)))
             (Ok (Program (::tops walked) body (::next walked))))))))

    ;; The tops derived, and the first number they leave unused.
    (struct Walked
      ((tops (List Top))
       (next I64)))

    ;; What the walk has found so far: the next number, and the problems,
    ;; latest first.
    (struct Walk
      ((next I64)
       (problems (List Problem))))

    (: derived-tops
       (impl (Fn WireNames (List bound-Top) I64 -> (Result Walked (List Feedback)))))
    (define (derived-tops names tops first-unused)
      (let ((walked (walked-tops names (Walk first-unused (Nil)) tops)))
        (match (reported (reverse (::problems (::second walked))))
          ((Nil) (Ok (Walked (::first walked) (::next (::second walked)))))
          (problems (Err problems)))))

    ;; The old expander declares every instance before it expands any
    ;; body, and a problem in a declaration ends them: the first head
    ;; problem is the only one. Otherwise each body's problem is, in order.
    (: reported (impl (Fn (List Problem) -> (List Feedback))))
    (define (reported problems)
      (match (find (lambda (problem)
                     (match problem
                       ((HeadProblem _) #t)
                       ((BodyProblem _) #f)))
                   problems)
        ((Some (HeadProblem feedback)) (list feedback))
        (_ (concatenate (map (lambda (problem)
                               (match problem
                                 ((HeadProblem feedback) (list feedback))
                                 ((BodyProblem feedback) feedback)))
                             problems)))))

    ;; ---- Declarations ----

    (: walked-tops
       (impl (Fn WireNames Walk (List bound-Top) -> (Pair (List Top) Walk))))
    (define (walked-tops names walk tops)
      (let loop ((tops tops)
                 (walk walk)
                 (done (Nil)))
        (match tops
          ((Nil) (Pair (concatenate (reverse done)) walk))
          ((Cons top rest)
           (let ((walked (walked-top names walk top)))
             (loop rest (::second walked) (Cons (::first walked) done)))))))

    ;; Each declaration as it was, but that a struct or an enum says
    ;; whether it derives Move and is followed by the instances it derives,
    ;; and an instance scope's declarations are walked in turn.
    (: walked-top (impl (Fn WireNames Walk bound-Top -> (Pair (List Top) Walk))))
    (define (walked-top names walk top)
      (match top
        ((bound-Struct global parameters fields derivations annotations name-loc loc)
         (with-instances names
                         walk
                         (Struct global
                                 parameters
                                 fields
                                 (derives-move? derivations)
                                 annotations
                                 name-loc
                                 loc)
                         (DerivedType global
                                      parameters
                                      (list (Constructor global (length fields) name-loc))
                                      loc)
                         derivations))
        ((bound-Enum global parameters cases derivations annotations loc)
         (with-instances names
                         walk
                         (Enum global parameters cases (derives-move? derivations) annotations loc)
                         (DerivedType global
                                      parameters
                                      (map (lambda (case)
                                             (Constructor (::global case)
                                                          (length (::fields case))
                                                          (::loc case)))
                                           cases)
                                      loc)
                         derivations))
        ((bound-InstanceScope sets tops loc)
         (let ((walked (walked-tops names walk tops)))
           (Pair (list (InstanceScope sets (::first walked) loc)) (::second walked))))
        ((bound-LinkImport global path digest file loc)
         (Pair (list (LinkImport global path digest file loc)) walk))
        ((bound-Define global value loc) (Pair (list (Define global value loc)) walk))
        ((bound-Signature target scheme annotations loc)
         (Pair (list (Signature target scheme annotations loc)) walk))
        ((bound-Statement expr) (Pair (list (Statement expr)) walk))
        ((bound-Expose target symbol dynamic? loc)
         (Pair (list (Expose target symbol dynamic? loc)) walk))
        ((bound-Alias global parameters annotations loc)
         (Pair (list (Alias global parameters annotations loc)) walk))
        ((bound-Class global parameters members annotations loc)
         (Pair (list (Class global parameters members annotations loc)) walk))
        ((bound-TopInstance instance) (Pair (list (TopInstance instance)) walk))
        ((bound-InstanceSet global members loc) (Pair (list (InstanceSet global members loc)) walk))
        ((bound-Extern global module symbol type annotations loc)
         (Pair (list (Extern global module symbol type annotations loc)) walk))
        ((bound-Effect global operations defaults around-main? annotations loc)
         (Pair (list (Effect global operations defaults around-main? annotations loc)) walk))
        ((bound-Primitive global type loc) (Pair (list (Primitive global type loc)) walk))))

    ;; Whether a clause names Move.
    (: derives-move? (impl (Fn (List expanded-Derivation) -> Bool)))
    (define (derives-move? derivations)
      (any? (lambda (derivation)
              (match derivation
                ((expanded-DeriveMove _) #t)
                (_ #f)))
            derivations))

    ;; ---- Instances ----

    ;; `declaration`, then the instance of each class its clauses name
    ;; that has one, in order.
    (: with-instances
       (impl
        (Fn WireNames Walk Top DerivedType (List expanded-Derivation) -> (Pair (List Top) Walk))))
    (define (with-instances names walk declaration derived derivations)
      (let loop ((derivations derivations)
                 (walk walk)
                 (instances (Nil)))
        (match derivations
          ((Nil) (Pair (Cons declaration (reverse instances)) walk))
          ((Cons derivation rest)
           (match (derived-instance names derived derivation (::next walk))
             ((None) (loop rest walk instances))
             ((Some (Ok (Pair instance next)))
              (loop rest (Walk next (::problems walk)) (Cons (TopInstance instance) instances)))
             ((Some (Err problem))
              (loop rest (Walk (::next walk) (Cons problem (::problems walk))) instances)))))))

    ;; The instance a clause asks for, if any.
    (: derived-instance
       (impl (Fn WireNames DerivedType expanded-Derivation I64
                 -> (Option (Result (Pair bound-Instance I64) Problem)))))
    (define (derived-instance names derived derivation next)
      (match derivation
        ((expanded-DeriveMove _) (None))
        ((expanded-DeriveSerialize _) (Some (serialize-instance names derived next)))
        ((expanded-DeriveDeserialize _) (Some (deserialize-instance names derived next)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-derive)
    (import
     (snail core table)
     (only (snail compiler expand offer) Offer Export TopScope Value ClassName)
     (snail stage0 testing))
    (begin
      (define (test-derive)
        (test-placement)
        (test-problems))

      (define (at line)
        (Loc "a.sld" line 1))

      (define a (list "a"))

      (define (global name)
        (expanded-Global a name 0))

      (define wire (list "snail" "shell" "wire"))

      (define (offer-of library names)
        (Offered library
                 (Offer (map (lambda (name)
                               (Export name
                                       (if (string=? name "Serialize")
                                           (ClassName (expanded-Global library name 0))
                                           (Value (expanded-TopGlobal (expanded-Global library
                                                                                       name
                                                                                       0))))))
                             names)
                        (TopScope empty-table empty-table))))

      (define primitive (offer-of (list "prim") (list "unit" "panic")))

      (define full-wire
        (offer-of wire (list "Serialize" "encode" "encode-case-id")))

      (define (point derivations line)
        (bound-Struct (global "Point")
                      (list)
                      (list)
                      derivations
                      (list)
                      (at line)
                      (at line)))

      ;; The instances follow their declaration, inside an instance scope
      ;; too, numbered from Bound's first unused number; Move makes no
      ;; instance and is said on the type, and a declaration without
      ;; clauses is as it was.
      (define (test-placement)
        (let* ((statement (bound-Statement (bound-Literal (expanded-UnitValue) (at 9))))
               (derived (derive (bound-Defined a
                                               (list (bound-InstanceScope
                                                      (list)
                                                      (list
                                                       (point (list (expanded-DeriveMove (at 2))
                                                                    (expanded-DeriveSerialize
                                                                     (at 2)))
                                                              2))
                                                      (at 1))
                                                     statement
                                                     (point (list) 3))
                                               5
                                               (at 1))
                                (list primitive full-wire))))
          (match derived
            ((Ok (Defined _
                   (Cons (InstanceScope _
                                        (Cons (Struct _ _ _ #t _ _ _)
                                              (Cons (TopInstance instance) (Nil)))
                                        _)
                         (Cons (Statement _) (Cons (Struct _ _ _ #f _ _ _) (Nil))))
                   7
                   _))
             (expect (::types instance)
                     (list (expanded-Applied (global "Point") "Point" (list) (at 2)))))
            (other (expect other "a scope holding Point and its instance, then the rest")))))

      ;; The first head problem alone; else each body's, in order.
      (define (test-problems)
        (let ((body-only (offer-of wire (list "Serialize" "encode")))
              (library (lambda (derivations)
                         (bound-Program (list (point derivations 2) (point derivations 4))
                                        (None)
                                        0))))
          (expect (derive (library (list (expanded-DeriveSerialize (at 2))))
                          (list primitive body-only))
                  (Err (list (Feedback (at 2) "unbound identifier encode-case-id")
                             (Feedback (at 4) "unbound identifier encode-case-id"))))
          (expect (derive (library (list (expanded-DeriveSerialize (at 2))
                                         (expanded-DeriveDeserialize (at 2))))
                          (list primitive body-only))
                  (Err
                   (list (Feedback (at 2) "instance of something that is not a typeclass"))))))))
   (else)))
