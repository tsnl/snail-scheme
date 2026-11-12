;; The pass `dispatch`: a declared library, and what each library in its
;; import closure offers, become the library in which every instance has
;; its methods, as (snail compiler dispatch language) says. It walks the
;; library's declarations in the order written, as the old compiler
;; declares them, so an instance sees each class of the library declared
;; before it, and an instance written with a dispatch clause becomes the
;; instance with the methods (snail compiler dispatch clauses) writes.
;;
;; A clause's domain problem stops the library with that problem alone, as
;; the old compiler stops when it declares that instance: nothing found
;; before it is reported (build/dispatch-probes/clause-d-before-y.sld). A
;; method's problem is that method's, and the walk goes on, so the library
;; fails with every method's problem, in the order written, once the walk
;; is done (build/dispatch-design/probes/dispatch-per-method.sld), as the
;; old compiler reports each method body's problem.
(define-library (snail compiler dispatch pass)
  (export
   dispatch)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare offer) Declarations)
   (snail compiler dispatch language)
   (snail compiler dispatch known)
   (snail compiler dispatch state)
   (snail compiler dispatch clauses))
  (begin

    ;; ---- The pass ----

    ;; `imported` holds what each library in the import closure offers.
    ;; A program's Globals are of the library ("main"), as `declare`
    ;; numbers them.
    (: dispatch
       (impl (Fn declared-Declared (List Declarations) -> (Result Dispatched (List Feedback)))))
    (define (dispatch declared imported)
      (match declared
        ((declared-Defined name tops first-unused loc)
         (result-let* ((walked (library-tops name tops first-unused imported)))
           (Ok (Defined name (::first walked) (::next (::second walked)) loc))))
        ((declared-Program tops body first-unused)
         (result-let* ((walked (library-tops (list "main") tops first-unused imported)))
           (Ok (Program (::first walked) body (::next (::second walked))))))))

    ;; ---- Walking ----

    ;; Where the walk is: the numbers it has handed out, the classes known
    ;; there, and the methods' problems found so far, the latest first.
    (struct Walk
      ((numbering Numbering)
       (classes Classes)
       (problems (List Feedback))))

    (: library-tops
       (impl (Fn LibraryName (List declared-Top) I64 (List Declarations)
                 -> (Result (Pair (List Top) Numbering) (List Feedback)))))
    (define (library-tops library tops first-unused imported)
      (result-let* ((walked (walked-tops (Walk (Numbering library first-unused)
                                               (library-classes library imported tops)
                                               (Nil))
                                         tops)))
        (match (::problems (::second walked))
          ((Nil) (Ok (Pair (::first walked) (::numbering (::second walked)))))
          (problems (Err (reverse problems))))))

    (: walked-tops
       (impl (Fn Walk (List declared-Top) -> (Result (Pair (List Top) Walk) (List Feedback)))))
    (define (walked-tops walk tops)
      (let loop ((walk walk)
                 (tops tops)
                 (walked (Nil)))
        (match tops
          ((Nil) (Ok (Pair (reverse walked) walk)))
          ((Cons top rest)
           (result-let* ((next (walked-top walk top)))
             (loop (::second next) rest (Cons (::first next) walked)))))))

    ;; A class is known from its declaration on; an instance gets its
    ;; methods; a scope's and a set's are walked in place; any other
    ;; declaration is as it was.
    (: walked-top (impl (Fn Walk declared-Top -> (Result (Pair Top Walk) (List Feedback)))))
    (define (walked-top walk top)
      (match top
        ((declared-TopClass class)
         (Ok (Pair (TopClass class)
                   (Walk (::numbering walk)
                         (classes-with-reached (::classes walk) class)
                         (::problems walk)))))
        ((declared-TopInstance instance)
         (result-let* ((written (walked-instance walk instance)))
           (Ok (Pair (TopInstance (::first written)) (::second written)))))
        ((declared-InstanceSet global members loc)
         (result-let* ((written (walked-members walk members)))
           (Ok (Pair (InstanceSet global (::first written) loc) (::second written)))))
        ((declared-InstanceScope sets tops loc)
         (result-let* ((written (walked-tops walk tops)))
           (Ok (Pair (InstanceScope sets (::first written) loc) (::second written)))))
        ((declared-LinkImport global path digest file loc)
         (Ok (Pair (LinkImport global path digest file loc) walk)))
        ((declared-Define global value signature annotations loc)
         (Ok (Pair (Define global value signature annotations loc) walk)))
        ((declared-Statement expr) (Ok (Pair (Statement expr) walk)))
        ((declared-Expose target symbol dynamic? loc)
         (Ok (Pair (Expose target symbol dynamic? loc) walk)))
        ((declared-TopData data) (Ok (Pair (TopData data) walk)))
        ((declared-Alias global parameters annotations loc)
         (Ok (Pair (Alias global parameters annotations loc) walk)))
        ((declared-Extern global module symbol type annotations loc)
         (Ok (Pair (Extern global module symbol type annotations loc) walk)))
        ((declared-TopEffect effect) (Ok (Pair (TopEffect effect) walk)))
        ((declared-Primitive global type loc) (Ok (Pair (Primitive global type loc) walk)))))

    ;; Each instance a set holds, in place.
    (: walked-members
       (impl (Fn Walk
                 (List declared-SetMember)
                 ->
                 (Result (Pair (List Instance) Walk) (List Feedback)))))
    (define (walked-members walk members)
      (let loop ((walk walk)
                 (members members)
                 (walked (Nil)))
        (match members
          ((Nil) (Ok (Pair (reverse walked) walk)))
          ((Cons (declared-SetInstance instance) rest)
           (result-let* ((next (walked-instance walk instance)))
             (loop (::second next) rest (Cons (::first next) walked))))
          ;; TEMPORARY until the next slice writes generated instances:
          ;; a `dynamic-instances` form is refused here, and no program
          ;; reaches this pass yet.
          ((Cons (declared-DynamicInstances _ _ loc) _)
           (fail loc "dispatch: dynamic-instances forms are not written yet")))))

    ;; ---- Instances ----

    ;; An instance written with methods keeps them; one written with a
    ;; dispatch clause gets those the clause stands for, its class as
    ;; known where it is written.
    (: walked-instance
       (impl (Fn Walk declared-Instance -> (Result (Pair Instance Walk) (List Feedback)))))
    (define (walked-instance walk instance)
      (match (::body instance)
        ((declared-Methods methods) (Ok (Pair (with-methods instance methods) walk)))
        ((declared-Dispatch targets _)
         (result-let* ((written (clause-methods (::numbering walk)
                                                (known-class (::classes walk) (::class instance))
                                                instance
                                                targets)))
           (let ((clause (::first written)))
             (Ok (Pair (with-methods instance (::methods clause))
                       (Walk (::second written)
                             (::classes walk)
                             (append (reverse (::problems clause)) (::problems walk))))))))))

    (: with-methods (impl (Fn declared-Instance (List declared-InstanceMethod) -> Instance)))
    (define (with-methods instance methods)
      (Instance (::global instance)
                (::class instance)
                (::variables instance)
                (::types instance)
                (::outputs instance)
                (::requirements instance)
                (::copied instance)
                methods
                (::loc instance)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-dispatch-pass)
    (import
     (only (snail compiler expand language) Global ClassGlobal Dyn FnContract)
     (only (snail compiler declare forms) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-dispatch-pass)
        (test-per-method)
        (test-domain-first)
        (test-class-later)
        (test-sets))

      (define main (list "main"))

      (define (at line)
        (Loc "probe.sld" line 1))

      (define (builtin name)
        (declared-Con (Global forms-library name 0) (list)))

      (define any-type (builtin "Any"))
      (define t (declared-Var (declared-Written "T")))

      ;; `(typeclass (Name T) (: method (impl (Fn parameter ... -> result))) ...)`
      ;; at `line`, each method's own scheme its operational one.
      (define (class name line methods)
        (declared-Class (Global main name 0)
                        (list (declared-TypeParameter "T"))
                        (list)
                        (map (lambda (method)
                               (declared-Method (Global main (::first method) 0)
                                                (declared-Scheme (list)
                                                                 (list)
                                                                 (list)
                                                                 (declared-Callable
                                                                  (Dyn)
                                                                  (FnContract)
                                                                  (declared-Arrow
                                                                   (::first (::second method))
                                                                   (::second (::second method))
                                                                   (declared-Effects (list)
                                                                                     (None)))))
                                                (list)
                                                (at line)))
                             methods)
                        (list)
                        (at line)))

      ;; `(instance (Name Any) (dispatch target ...))` at `line`.
      (define (clause name serial line targets)
        (declared-Instance (Global main name serial)
                           (ClassGlobal (Global main name 0))
                           (list)
                           (list any-type)
                           (list)
                           (list)
                           (list)
                           (declared-Dispatch targets (at (+ line 1)))
                           (at line)))

      (define (signature parameters result)
        (Pair parameters result))

      (define (library tops)
        (declared-Defined main tops 20 (at 0)))

      (define (problems result)
        (match result
          ((Err feedback) feedback)
          ((Ok _) (list))))

      ;; build/dispatch-design/probes/dispatch-per-method.sld: both of
      ;; Two's methods are refused, then ReadValue's, in the order written.
      (define (test-per-method)
        (let ((needs-argument "each dispatched method needs an argument of its erased class type"))
          (expect (problems
                   (dispatch (library (list (declared-TopClass
                                             (class "Two"
                                                    4
                                                    (list (Pair "one"
                                                                (signature (list (builtin "String"))
                                                                           t))
                                                          (Pair "two"
                                                                (signature (list (builtin "String"))
                                                                           t)))))
                                            (declared-TopInstance
                                             (clause "Two" 1 7 (list (builtin "I64"))))
                                            (declared-TopClass
                                             (class "ReadValue"
                                                    9
                                                    (list (Pair "read-value"
                                                                (signature
                                                                 (list (declared-Con
                                                                        (Global (list "snail"
                                                                                      "core"
                                                                                      "base")
                                                                                "List"
                                                                                0)
                                                                        (list t)))
                                                                 (builtin "String"))))))
                                            (declared-TopInstance
                                             (clause "ReadValue" 2 11 (list (builtin "String"))))))
                             (list)))
                  (list (Feedback (at 7) needs-argument)
                        (Feedback (at 7) needs-argument)
                        (Feedback (at 11)
                                  "dispatch needs the erased class type as a whole parameter or result")))))

      ;; build/dispatch-probes/clause-d-before-y.sld: a domain's problem
      ;; is the library's one problem, though a method's came before it.
      (define (test-domain-first)
        (expect (dispatch (library (list (declared-TopClass
                                          (class "ReadValue"
                                                 4
                                                 (list (Pair "read-value"
                                                             (signature (list (builtin "String"))
                                                                        t)))))
                                         (declared-TopInstance
                                          (clause "ReadValue" 1 6 (list (builtin "I64"))))
                                         (declared-TopClass
                                          (class "Other"
                                                 8
                                                 (list (Pair "other"
                                                             (signature (list t)
                                                                        (builtin "I64"))))))
                                         (declared-TopInstance (clause "Other" 2 10 (list)))))
                          (list))
                (fail (at 10) "dispatch needs at least one concrete type")))

      ;; build/dispatch-design/probes/class-later-dispatch.sld: the class
      ;; is declared after the instance, so it has no member there, and the
      ;; instance no method; the numbers are as they were.
      (define (test-class-later)
        (let ((late (class "Late" 6 (list (Pair "late" (signature (list t) (builtin "I64")))))))
          (expect (dispatch (library (list (declared-TopInstance
                                            (clause "Late" 1 4 (list (builtin "I64"))))
                                           (declared-TopClass late)))
                            (list))
                  (Ok (Defined main
                        (list (TopInstance (Instance (Global main "Late" 1)
                                                     (ClassGlobal (Global main "Late" 0))
                                                     (list)
                                                     (list any-type)
                                                     (list)
                                                     (list)
                                                     (list)
                                                     (list)
                                                     (at 4)))
                              (TopClass late))
                        20
                        (at 0))))))

      ;; A clause instance in a set and in a scope gets its methods there,
      ;; numbered from the library's first unused number on.
      (define (test-sets)
        (let ((show (class "Show" 1 (list (Pair "show" (signature (list t) (builtin "String")))))))
          (match (dispatch (library (list (declared-TopClass show)
                                          (declared-InstanceScope
                                           (list)
                                           (list (declared-InstanceSet
                                                  (Global main "shows" 0)
                                                  (list (declared-SetInstance
                                                         (clause "Show"
                                                                 1
                                                                 3
                                                                 (list (builtin "I64")))))
                                                  (at 3)))
                                           (at 2))))
                           (list))
            ((Ok (Defined _
                   (Cons _
                         (Cons
                          (InstanceScope _ (Cons (InstanceSet _ (Cons instance (Nil)) _) (Nil)) _)
                          (Nil)))
                   next
                   _))
             (expect (map ::implementation (::methods instance)) (list (Global main "show" 20)))
             (expect next 23))
            (other (expect other "a scope holding a set of one dispatched instance")))))))
   (else)))
