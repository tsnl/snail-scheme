;; The pass `dispatch`: a declared library, what each library in its import
;; closure offers, and the instances of every library before it in the
;; program, become the library in which every instance has its methods, as
;; (snail compiler dispatch language) says. It walks the library's
;; declarations in the order written, as the old compiler declares them,
;; so an instance or a form sees each class of the library declared before
;; it, and a form the instances written or generated before it. An
;; instance written with a dispatch clause becomes the instance with the
;; methods (snail compiler dispatch clauses) writes, and a
;; `dynamic-instances` form the instances (snail compiler dispatch
;; families) generates, in its place in its set.
;;
;; A clause's domain problem, and any problem of a form, stops the library
;; with that problem alone, as the old compiler stops when it declares
;; that instance or form: nothing found before it is reported
;; (build/dispatch-probes/clause-d-before-y.sld and build/dispatch-design/
;; probes/dispatch-d-before-y.sld). A method's problem is that method's,
;; and the walk goes on, so the library fails with every method's problem,
;; in the order written, once the walk is done (build/dispatch-design/
;; probes/dispatch-per-method.sld), as the old compiler reports each
;; method body's problem.
(define-library (snail compiler dispatch pass)
  (export
   dispatch)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (only (snail compiler names globals) Global ClassRef)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare offer) Declarations)
   (snail compiler dispatch language)
   (snail compiler dispatch listing)
   (snail compiler dispatch known)
   (snail compiler names numbering)
   (snail compiler dispatch clauses)
   (snail compiler dispatch families))
  (begin

    ;; ---- The pass ----

    ;; `imported` holds what each library in the import closure offers,
    ;; and `earlier` the listing of each library before this one in the
    ;; program, in order, each library's instances in turn.
    (: dispatch
       (impl (Fn declared-Declared (List Declarations) (List Listed)
                 -> (Result Dispatched (List Feedback)))))
    (define (dispatch declared imported earlier)
      (match declared
        ((declared-Defined name tops first-unused loc)
         (result-let* ((walked (library-tops name tops first-unused imported earlier)))
           (Ok (Defined name (::first walked) (::next (::second walked)) loc))))
        ((declared-Program tops first-unused)
         (result-let* ((walked (library-tops program-library tops first-unused imported earlier)))
           (Ok (Program (::first walked) (::next (::second walked))))))))

    ;; ---- Walking ----

    ;; Where the walk is: the numbers it has handed out; the classes known
    ;; there; the earlier libraries' instances, and the library's own so
    ;; far, the latest first; and the methods' problems found so far, the
    ;; latest first.
    (struct Walk
      ((numbering Numbering)
       (classes Classes)
       (earlier (List Listed))
       (own (List Listed))
       (problems (List Feedback))))

    (: library-tops
       (impl (Fn LibraryName (List declared-Top) I64 (List Declarations) (List Listed)
                 -> (Result (Pair (List Top) Numbering) (List Feedback)))))
    (define (library-tops library tops first-unused imported earlier)
      (result-let* ((walked (walked-tops (Walk (Numbering library first-unused)
                                               (library-classes library imported tops)
                                               earlier
                                               (Nil)
                                               (Nil))
                                         (Nil)
                                         tops)))
        (match (::problems (::second walked))
          ((Nil) (Ok (Pair (::first walked) (::numbering (::second walked)))))
          (problems (Err (reverse problems))))))

    ;; `sets` are those of the instance scopes around `tops`.
    (: walked-tops
       (impl (Fn Walk (List Global) (List declared-Top)
                 -> (Result (Pair (List Top) Walk) (List Feedback)))))
    (define (walked-tops walk sets tops)
      (let loop ((walk walk)
                 (tops tops)
                 (walked (Nil)))
        (match tops
          ((Nil) (Ok (Pair (reverse walked) walk)))
          ((Cons top rest)
           (result-let* ((next (walked-top walk sets top)))
             (loop (::second next) rest (Cons (::first next) walked)))))))

    ;; A class is known from its declaration on; an instance gets its
    ;; methods, and a struct's fields and an instance are listed once
    ;; declared; a scope's and a set's are walked in place; any other
    ;; declaration is as it was.
    (: walked-top
       (impl (Fn Walk (List Global) declared-Top -> (Result (Pair Top Walk) (List Feedback)))))
    (define (walked-top walk sets top)
      (match top
        ((declared-TopClass class)
         (Ok (Pair (TopClass class)
                   (Walk (::numbering walk)
                         (classes-with-reached (::classes walk) class)
                         (::earlier walk)
                         (::own walk)
                         (::problems walk)))))
        ((declared-TopInstance instance)
         (result-let* ((written (walked-instance walk instance)))
           (Ok (listed-top (TopInstance (::first written)) (::second written)))))
        ((declared-InstanceSet global members loc)
         (result-let* ((written (walked-members walk global (Cons global sets) members)))
           (Ok (Pair (InstanceSet global (::first written) loc) (::second written)))))
        ((declared-InstanceScope own tops loc)
         (result-let* ((written (walked-tops walk (append own sets) tops)))
           (Ok (Pair (InstanceScope own (::first written) loc) (::second written)))))
        ((declared-TopData data) (Ok (listed-top (TopData data) walk)))
        ((declared-LinkImport global path digest file loc)
         (Ok (Pair (LinkImport global path digest file loc) walk)))
        ((declared-Define global value signature annotations loc)
         (Ok (Pair (Define global value signature annotations loc) walk)))
        ((declared-Statement expr) (Ok (Pair (Statement expr) walk)))
        ((declared-Expose target symbol dynamic? loc)
         (Ok (Pair (Expose target symbol dynamic? loc) walk)))
        ((declared-Alias global parameters annotations loc)
         (Ok (Pair (Alias global parameters annotations loc) walk)))
        ((declared-Extern global module symbol type annotations loc)
         (Ok (Pair (Extern global module symbol type annotations loc) walk)))
        ((declared-TopEffect effect) (Ok (Pair (TopEffect effect) walk)))
        ((declared-Primitive global type loc) (Ok (Pair (Primitive global type loc) walk)))))

    ;; `top` written, and the instances the listing finds in it listed.
    (: listed-top (impl (Fn Top Walk -> (Pair Top Walk))))
    (define (listed-top top walk)
      (Pair top (with-listed walk (tops-instances (list top)))))

    (: with-listed (impl (Fn Walk (List Listed) -> Walk)))
    (define (with-listed walk listed)
      (Walk (::numbering walk)
            (::classes walk)
            (::earlier walk)
            (append (reverse listed) (::own walk))
            (::problems walk)))

    ;; Each instance the set `set` holds, in place, those a form generates
    ;; in the form's; `active` is the set and the sets of the scopes around
    ;; it, which are active where its forms are.
    (: walked-members
       (impl (Fn Walk
                 Global
                 (List Global)
                 (List declared-SetMember)
                 ->
                 (Result (Pair (List Instance) Walk) (List Feedback)))))
    (define (walked-members walk set active members)
      (let loop ((walk walk)
                 (members members)
                 (walked (Nil)))
        (match members
          ((Nil) (Ok (Pair (concatenate (reverse walked)) walk)))
          ((Cons member rest)
           (result-let* ((next (walked-member walk active member)))
             (loop (with-listed (::second next)
                                (map (lambda (instance) (ListedInstance instance (Some set)))
                                     (::first next)))
                   rest
                   (Cons (::first next) walked)))))))

    (: walked-member
       (impl (Fn Walk (List Global) declared-SetMember
                 -> (Result (Pair (List Instance) Walk) (List Feedback)))))
    (define (walked-member walk active member)
      (match member
        ((declared-SetInstance instance)
         (result-let* ((written (walked-instance walk instance)))
           (Ok (Pair (list (::first written)) (::second written)))))
        ((declared-DynamicInstances class pairs loc)
         (result-let* ((generated (family-instances (::numbering walk)
                                                    (known-class (::classes walk) class)
                                                    class
                                                    pairs
                                                    (sources walk class active)
                                                    loc)))
           (Ok (Pair (::first generated)
                     (Walk (::second generated)
                           (::classes walk)
                           (::earlier walk)
                           (::own walk)
                           (::problems walk))))))))

    ;; The instances of `class` before the form, in the program's order,
    ;; active under `active`.
    (: sources (impl (Fn Walk ClassRef (List Global) -> (List Instance))))
    (define (sources walk class active)
      (concatenate (map (lambda (listed)
                          (match listed
                            ((ListedInstance instance _)
                             (if
                              (and (same-class? (::class instance) class) (active? active listed))
                              (list instance)
                              (Nil)))
                            ((FieldInstance _ _) (Nil))))
                        (append (::earlier walk) (reverse (::own walk))))))

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
                             (::earlier walk)
                             (::own walk)
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
     (snail core table)
     (only (snail compiler expand language) Dyn FnContract)
     (only (snail compiler names globals) ClassGlobal Label)
     (only (snail compiler literals constant) Integer)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-dispatch-pass)
        (test-per-method)
        (test-domain-first)
        (test-form-first)
        (test-class-later)
        (test-sets)
        (test-sources))

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
                             (list)
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
                          (list)
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
                            (list)
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
                           (list)
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
            (other (expect other "a scope holding a set of one dispatched instance")))))

      ;; ---- Forms ----

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define lib (list "lib"))

      (define (var name)
        (declared-Var (declared-Written name)))

      ;; (typeclass (Op e A B) (type Output) (: op (impl (Fn A B -> Output ! e)))) in `library`.
      (define (op-class library line)
        (declared-Class (Global library "Op" 0)
                        (list (declared-RowParameter "e")
                              (declared-TypeParameter "A")
                              (declared-TypeParameter "B"))
                        (list (declared-Output (Label "Output" (at line)) (list)))
                        (list (declared-Method (Global library "op" 0)
                                               (declared-Scheme (list)
                                                                (list)
                                                                (list)
                                                                (declared-Callable
                                                                 (Dyn)
                                                                 (FnContract)
                                                                 (declared-Arrow
                                                                  (list (var "A") (var "B"))
                                                                  (var "Output")
                                                                  (declared-Effects
                                                                   (list)
                                                                   (Some (var "e"))))))
                                               (list)
                                               (at line)))
                        (list)
                        (at line)))

      ;; `(instance (Op (!) type type) (type Output type) (define op ...))`
      ;; of `library`'s class.
      (define (op-source library serial type line)
        (declared-Instance (Global main "Op" serial)
                           (ClassGlobal (Global library "Op" 0))
                           (list)
                           (list (declared-Row (declared-Effects (list) (None))) type type)
                           (list type)
                           (list)
                           (list)
                           (declared-Methods
                            (list
                             (declared-InstanceMethod (declared-ClassMethod (Global library "op" 0))
                                                      (Global main "op" serial)
                                                      (declared-Literal (Integer 0) (at line))
                                                      (at line))))
                           (at line)))

      ;; A written instance, as `dispatch` keeps it.
      (define (written instance)
        (match (::body instance)
          ((declared-Methods methods) (with-methods instance methods))
          ((declared-Dispatch _ _) (with-methods instance (list)))))

      (define (form library line pairs)
        (declared-DynamicInstances (ClassGlobal (Global library "Op" 0)) pairs (at line)))

      (define (set name line members)
        (declared-InstanceSet (Global main name 0) members (at line)))

      ;; build/dispatch-design/probes/dispatch-d-before-y.sld: a form's
      ;; problem is the library's one problem, though a method's came
      ;; before it.
      (define (test-form-first)
        (expect (dispatch (library (list (declared-TopClass
                                          (class "ReadValue"
                                                 4
                                                 (list (Pair "read-value"
                                                             (signature (list (builtin "String"))
                                                                        t)))))
                                         (declared-TopInstance
                                          (clause "ReadValue" 1 6 (list (builtin "I64"))))
                                         (declared-TopClass (op-class main 8))
                                         (set "dynamic"
                                              11
                                              (list (form main 12 (list (list any-type i64)))))))
                          (list)
                          (list))
                (fail (at 12) "dynamic-instances domain entries are two concrete, non-Any types")))

      ;; A form's sources are the instances of its class before it, the
      ;; earlier libraries' first, active where it is: in no set, in its
      ;; own set, or in one a scope around its set activates.
      (define (test-sources)
        (let* ((earlier (list (ListedInstance (written (op-source lib 1 i64 1)) (None))))
               (other (set "other" 3 (list (declared-SetInstance (op-source lib 2 f64 3)))))
               (erased (lambda (pairs) (set "erased" 6 (list (form lib 7 pairs)))))
               (walked (lambda (scope pairs)
                         (dispatch (library (list other
                                                  (declared-InstanceScope
                                                   (list (Global main scope 0))
                                                   (list (erased pairs))
                                                   (at 5))))
                                   (list (Declarations lib
                                                       empty-table
                                                       (table-set empty-table
                                                                  "Op"
                                                                  (list (op-class lib 1)))
                                                       empty-table))
                                   earlier))))
          (expect (walked "ordinary" (list (list i64 i64) (list f64 f64)))
                  (fail (at 7) "dynamic-instances has no active source instance for a domain pair"))
          (match (walked "other" (list (list i64 i64) (list f64 f64)))
            ((Ok (Defined _
                   (Cons _
                         (Cons (InstanceScope _ (Cons (InstanceSet _ generated _) (Nil)) _) (Nil)))
                   next
                   _))
             (expect (map (lambda (instance) (::name (::global instance))) generated)
                     (list "dynamic" "dynamic" "dynamic" "dynamic" "dynamic"))
             (expect (::global (list-ref generated 0)) (Global main "dynamic" 20))
             (expect next 52))
            (found (expect found "five instances generated in the set erased")))))))
   (else)))
