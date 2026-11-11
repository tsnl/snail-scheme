;; Instances: an instance becomes its Instance, as the old compiler's
;; `declare-instance` (src/snail/shell/compiler/expand.sld) declares it,
;; in its order, the first problem stopping the declaration:
;;
;; - its requirements, over the variables its head leaves unbound, each in
;;   the scope of those before it, where nothing else is in scope;
;; - its head's types, in the scope of every requirement;
;; - its equations, which give each of the class's outputs exactly once,
;;   and then each output's type, in the class's order, in that scope;
;; - for a class with outputs, a head with its written parameters only;
;; - its Global, named for its class;
;; - its methods: a dispatch clause's types, where nothing is in scope; or
;;   each method definition, which names a member of the class and is
;;   given a Global for its implementation, named for the member; and then
;;   every member of the class implemented.
;;
;; The class is as known where the instance is: a class of the library's
;; own whose declaration comes later has its scanned shape, every
;; parameter a type, and no method, so every definition is refused, as in
;; the old compiler. Two definitions of one method are both kept, in
;; order, as the old compiler keeps them. A method's value is a body,
;; declared with the library's other bodies, once every declaration is
;; reached.
(define-library (snail compiler declare instances)
  (export
   DeclaredInstance
   PendingMethod
   declared-instance
   declared-dynamic
   declared-method
   instance-with-methods)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (prefix (snail compiler bind language) bound-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare requirements)
   (snail compiler declare heads)
   (snail compiler declare members)
   (snail compiler declare types)
   (snail compiler declare expressions))
  (begin

    ;; ---- Instances ----

    ;; An instance declared, its methods' values still to come, and what
    ;; each method's body needs: the member it implements, the Global of
    ;; its implementation, its value, and where its name is written.
    (struct DeclaredInstance
      ((instance Instance)
       (methods (List PendingMethod))))

    (struct PendingMethod
      ((member Member)
       (implementation expanded-Global)
       (value bound-Expr)
       (loc Loc)))

    (: declared-instance
       (impl (Fn Declaring
                 bound-Instance
                 ->
                 (Result (Pair DeclaredInstance Declaring) (List Feedback)))))
    (define (declared-instance state instance)
      (let* ((known (::known state))
             (shape (class-shape known (::class instance)))
             (loc (::loc instance)))
        (declaring-let* ((required state
                                   (unchanged state
                                              (declared-requirements (Scope known (Nil))
                                                                     (::variables instance)
                                                                     (::requirements instance))))
                         (types state
                                (unchanged state
                                           (declared-types (::scope required) (::types instance))))
                         (outputs state
                                  (unchanged state
                                             (instance-outputs (::scope required)
                                                               shape
                                                               (::equations instance)
                                                               loc)))
                         (head state
                               (unchanged state (checked (head-problem shape (length types)) loc)))
                         (global state (fresh-global state (class-name (::class instance))))
                         (body state (declared-body state instance)))
          (Ok (Pair (DeclaredInstance (Instance global
                                                (::class instance)
                                                (::variables required)
                                                types
                                                outputs
                                                (::requirements required)
                                                (::copied required)
                                                (::first body)
                                                loc)
                                      (::second body))
                    state)))))

    ;; An instance is named for its class: a declared class's name, or a
    ;; field class's label.
    (: class-name (impl (Fn expanded-ClassRef -> String)))
    (define (class-name class)
      (match class
        ((expanded-ClassGlobal global) (::name global))
        ((expanded-FieldClass label) label)))

    (: checked (impl (Fn (Option String) Loc -> (Result Bool (List Feedback)))))
    (define (checked problem loc)
      (match problem
        ((Some message) (fail loc message))
        ((None) (Ok #t))))

    ;; The type each equation gives its output, in the class's order, once
    ;; the equations give each output exactly once.
    (: instance-outputs
       (impl
        (Fn Scope ClassShape (List expanded-Equation) Loc -> (Result (List Type) (List Feedback)))))
    (define (instance-outputs scope shape equations loc)
      (result-let* ((given (checked (equations-given-problem shape equations) loc)))
        (map-results (lambda (equation)
                       (match equation
                         ((Some written) (declared-type scope (::type written)))
                         ((None) (panic "declare: each output has its equation"))))
                     (given-outputs shape equations))))

    ;; ---- Methods ----

    ;; The instance's body, and the methods whose values wait.
    (: declared-body
       (impl (Fn Declaring
                 bound-Instance
                 ->
                 (Result (Pair (Pair InstanceBody (List PendingMethod)) Declaring)
                         (List Feedback)))))
    (define (declared-body state instance)
      (match (::body instance)
        ((bound-Dispatch types loc)
         (declaring-let* ((declared state
                                    (unchanged state
                                               (declared-types (Scope (::known state) (Nil))
                                                               types))))
           (Ok (Pair (Pair (Dispatch declared loc) (Nil)) state))))
        ((bound-Methods methods)
         (let ((members (class-members (::class instance)
                                       (known-methods (::known state) (::class instance)))))
           (declaring-let* ((pending state
                                     (declaring-map state
                                                    (lambda (state method)
                                                      (pending-method state members method))
                                                    methods))
                            (complete state
                                      (unchanged state
                                                 (checked
                                                  (missing-member members (map ::member pending))
                                                  (::loc instance)))))
             (Ok (Pair (Pair (Methods (Nil)) pending) state)))))))

    ;; A declared class's methods as known where the instance is; a field
    ;; class has none of its own.
    (: known-methods (impl (Fn Known expanded-ClassRef -> (List Method))))
    (define (known-methods known class)
      (match class
        ((expanded-ClassGlobal global)
         (match (known-class known global)
           ((Some declared) (::methods declared))
           ((None) (Nil))))
        ((expanded-FieldClass _) (Nil))))

    ;; A definition's member, refused at its name, and its implementation's
    ;; Global.
    (: pending-method
       (impl (Fn Declaring
                 (List Member)
                 bound-InstanceMethod
                 ->
                 (Result (Pair PendingMethod Declaring) (List Feedback)))))
    (define (pending-method state members method)
      (let ((loc (method-loc (::name method))))
        (match (named-member members (::name method))
          ((Ok member)
           (declaring-let* ((implementation state (fresh-global state (member-name member))))
             (Ok (Pair (PendingMethod member implementation (::value method) loc) state))))
          ((Err message) (fail loc message)))))

    (: method-loc (impl (Fn expanded-MethodName -> Loc)))
    (define (method-loc name)
      (match name
        ((expanded-MemberName label) (::loc label))
        ((expanded-PathName _ label) (::loc label))))

    ;; ---- Method bodies ----

    ;; A method's value, a body of its own.
    (: declared-method (impl (Fn Known PendingMethod -> (Result InstanceMethod (List Feedback)))))
    (define (declared-method known pending)
      (result-let* ((value (declared-expr known (::value pending))))
        (Ok (InstanceMethod (::member pending) (::implementation pending) value (::loc pending)))))

    ;; The instance with its methods, once their bodies are declared; a
    ;; dispatch clause's methods are `dispatch`'s to write.
    (: instance-with-methods (impl (Fn Instance (List InstanceMethod) -> Instance)))
    (define (instance-with-methods instance methods)
      (match (::body instance)
        ((Dispatch _ _) instance)
        ((Methods _)
         (Instance (::global instance)
                   (::class instance)
                   (::variables instance)
                   (::types instance)
                   (::outputs instance)
                   (::requirements instance)
                   (::copied instance)
                   (Methods methods)
                   (::loc instance)))))

    ;; ---- Dynamic instances ----

    ;; `(dynamic-instances Class (type ...) ...)`: each pair's types, where
    ;; nothing is in scope. The instances it stands for are `dispatch`'s.
    (: declared-dynamic
       (impl (Fn Known
                 expanded-ClassRef
                 (List (List expanded-TypeExpr))
                 Loc
                 ->
                 (Result SetMember (List Feedback)))))
    (define (declared-dynamic known class pairs loc)
      (result-let* ((declared
                     (map-results (lambda (pair) (declared-types (Scope known (Nil)) pair)) pairs)))
        (Ok (DynamicInstances class declared loc))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-instances)
    (import
     (snail core table)
     (only (snail compiler expand language) Label)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-instances)
        (test-heads)
        (test-methods)
        (test-order)
        (test-dynamic))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))
      (define lib (list "lib"))

      (define (global library name)
        (expanded-Global library name 0))

      (define op (global lib "Op"))
      (define show (global lib "Show"))
      (define later (global main "Later"))

      (define (method library name)
        (Method (global library name) (Scheme (list) (list) (list) (Var (Written "a"))) (list) loc))

      ;; (lib) offers (Op A B) with the output Output and the method op, and
      ;; (Show a) with the methods show and width; (main) scans (Later a),
      ;; declared after the instances.
      (define known
        (Known main
               (Scanned empty-table
                        (by-name empty-table "Later" (ScannedClass later (list "a") (list))))
               (Declarations main empty-table empty-table empty-table)
               (list (Declarations lib
                                   empty-table
                                   (by-name (by-name empty-table
                                                     "Op"
                                                     (Class op
                                                            (list (TypeParameter "A")
                                                                  (TypeParameter "B"))
                                                            (list
                                                             (Output (Label "Output" loc) (list)))
                                                            (list (method lib "op"))
                                                            (list)
                                                            loc))
                                            "Show"
                                            (Class show
                                                   (list (TypeParameter "a"))
                                                   (list)
                                                   (list (method lib "show") (method lib "width"))
                                                   (list)
                                                   loc))
                                   empty-table))))

      (define (i64-at line)
        (expanded-Applied (expanded-Global forms-library "I64" 0) "I64" (list) (at line)))

      (define i64 (Con (expanded-Global forms-library "I64" 0) (list)))

      (define (unit-at line)
        (bound-Literal (expanded-UnitValue) (at line)))

      (define (definition name line)
        (bound-InstanceMethod (expanded-MemberName (Label name (at line))) (unit-at line)))

      (define (equation name type)
        (expanded-Equation (Label name loc) type))

      (define (instance class types equations methods)
        (bound-Instance (expanded-ClassGlobal class)
                        (list "t")
                        types
                        (list)
                        equations
                        (bound-Methods methods)
                        (at 9)))

      (define (declared state written)
        (match (declared-instance state written)
          ((Ok (Pair found next)) (Pair found (::next next)))
          ((Err feedback) (Err feedback))))

      ;; The head's types, then the outputs in the class's order; the
      ;; equations are counted before their types are converted, and the
      ;; head after.
      (define (test-heads)
        (let ((state (Declaring 5 known)))
          (match (declared state
                           (instance op
                             (list (expanded-Variable "t" loc) (i64-at 2))
                             (list (equation "Output" (i64-at 3)))
                             (list (definition "op" 4))))
            ((Pair found next)
             (expect next 7)
             (expect (::global (::instance found)) (expanded-Global main "Op" 5))
             (expect (::types (::instance found)) (list (Var (Written "t")) i64))
             (expect (::outputs (::instance found)) (list i64))
             (expect (::variables (::instance found)) (list (Written "t")))
             (expect (::methods found)
                     (list (PendingMethod (ClassMethod (global lib "op"))
                                          (expanded-Global main "op" 6)
                                          (unit-at 4)
                                          (at 4)))))
            (other (expect other "an instance")))
          (expect (declared-instance state
                                     (instance op
                                       (list (expanded-Variable "t" loc) (i64-at 2))
                                       (list (equation "Output" (i64-at 3))
                                             (equation "Output" (i64-at 3)))
                                       (list (definition "op" 4))))
                  (fail (at 9) "an instance defines each associated type exactly once"))
          (expect (declared-instance state
                                     (instance op
                                       (list (expanded-Variable "t" loc))
                                       (list (equation "Output"
                                                       (expanded-Applied
                                                        (expanded-Global forms-library "Array" 0)
                                                        "Array"
                                                        (list)
                                                        (at 5))))
                                       (list)))
                  (fail (at 5) "wrong number of type arguments: Array"))
          (expect (declared-instance state
                                     (instance op
                                       (list (expanded-Variable "t" loc))
                                       (list (equation "Output" (i64-at 3)))
                                       (list (definition "op" 4))))
                  (fail (at 9)
                        "instance head gives each declared class parameter; associated types belong in its body"))))

      ;; Each definition names a method, refused at its name; both of two
      ;; definitions of one method are kept; every method is implemented.
      (define (test-methods)
        (let ((state (Declaring 1 known)))
          (expect (declared-instance state
                                     (instance show
                                       (list (expanded-Variable "t" loc))
                                       (list)
                                       (list (definition "show" 2) (definition "size" 3))))
                  (fail (at 3) "not a method of this class: size"))
          (expect (declared-instance state
                                     (instance show
                                       (list (expanded-Variable "t" loc))
                                       (list)
                                       (list (definition "width" 2))))
                  (fail (at 9) "instance is missing a method: show"))
          (match (declared state
                           (instance show
                             (list (expanded-Variable "t" loc))
                             (list)
                             (list (definition "width" 2)
                                   (definition "show" 3)
                                   (definition "width" 4))))
            ((Pair found next)
             (expect (map ::implementation (::methods found))
                     (list (expanded-Global main "width" 2)
                           (expanded-Global main "show" 3)
                           (expanded-Global main "width" 4)))
             (expect next 5))
            (other (expect other "an instance")))))

      ;; A class of the library's own declared after the instance has no
      ;; method yet, so a definition is refused and none is missing; a field
      ;; class's one method is its label's path.
      (define (test-order)
        (let ((state (Declaring 1 known)))
          (expect (declared-instance state
                                     (instance later
                                       (list (expanded-Variable "t" loc))
                                       (list)
                                       (list (definition "m" 2))))
                  (fail (at 2) "not a method of this class: m"))
          (expect (::second (declared state
                                      (instance later
                                        (list (expanded-Variable "t" loc))
                                        (list)
                                        (list))))
                  2)
          (match (declared state
                           (bound-Instance (expanded-FieldClass "x")
                                           (list "r")
                                           (list (expanded-Variable "r" loc) (i64-at 2))
                                           (list)
                                           (list)
                                           (bound-Methods
                                            (list (bound-InstanceMethod
                                                   (expanded-PathName (list "x")
                                                                      (Label "::x" (at 3)))
                                                   (unit-at 3))))
                                           (at 9)))
            ((Pair found next)
             (expect (::global (::instance found)) (expanded-Global main "x" 1))
             (expect (map ::member (::methods found)) (list (FieldReader "x")))
             (expect (map ::implementation (::methods found)) (list (expanded-Global main "x" 2))))
            (other (expect other "a field instance")))))

      ;; A dispatch clause's types and a dynamic instance's pairs, converted.
      (define (test-dynamic)
        (match (declared (Declaring 1 known)
                         (bound-Instance (expanded-ClassGlobal show)
                                         (list)
                                         (list
                                          (expanded-Applied (expanded-Global forms-library "Any" 0)
                                                            "Any"
                                                            (list)
                                                            loc))
                                         (list)
                                         (list)
                                         (bound-Dispatch (list (i64-at 2)) (at 2))
                                         (at 9)))
          ((Pair found next)
           (expect (::body (::instance found)) (Dispatch (list i64) (at 2)))
           (expect (::methods found) (list))
           (expect next 2))
          (other (expect other "a dispatch instance")))
        (expect (declared-dynamic known
                                  (expanded-ClassGlobal show)
                                  (list (list (i64-at 1) (i64-at 1)))
                                  loc)
                (Ok (DynamicInstances (expanded-ClassGlobal show) (list (list i64 i64)) loc))))))
   (else)))
