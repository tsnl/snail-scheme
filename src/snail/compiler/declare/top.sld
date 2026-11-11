;; The top level, in the old compiler's steps (`expand-top-level`,
;; src/snail/shell/compiler/expand.sld):
;;
;; 1. The scan finds the shape of each type and class the library
;;    declares: a type's parameters, a class's parameters and outputs.
;; 2. Every signature is converted, where nothing of the library is
;;    declared yet.
;; 3. Each declaration, in order, becomes its entity, seeing only the
;;    entities of those before it; the first problem in this step or the
;;    one before stops the library, since the bodies need every entity.
;;    Then the library's Drop instances say which of its types have one.
;; 4. Each body, in order, is declared, once every declaration is
;;    reached: a definition's value, a library's statement, each method of
;;    an instance and each default of an effect; then a program's body. A
;;    body that fails leaves the numbers as they were, and the bodies after
;;    it are declared all the same, so every body's problem is returned, in
;;    order.
;;
;; Whether the library's structs can be built, which the old compiler
;; checks between the last two steps, is still to come.
(define-library (snail compiler declare top)
  (export
   Walked
   declared-tops)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName)
   (prefix (snail compiler expand language) expanded-)
   (prefix (snail compiler bind language) bound-)
   (prefix (snail compiler derive language) derived-)
   (snail compiler declare language)
   (snail compiler declare offer)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare values)
   (snail compiler declare data)
   (snail compiler declare classes)
   (snail compiler declare effects)
   (snail compiler declare instances)
   (snail compiler declare lifecycle)
   (snail compiler declare expressions))
  (begin

    ;; ---- The top level ----

    ;; The library's tops declared, its program's body, if it is a program,
    ;; and the state the bodies leave: the next number, and what is known
    ;; once every declaration is reached, which the library offers.
    (struct Walked
      ((tops (List Top))
       (body (Option Expr))
       (state Declaring)))

    ;; `imported` holds what each library in the import closure offers.
    (: declared-tops
       (impl (Fn LibraryName
                 (List derived-Top)
                 (Option bound-Expr)
                 I64
                 (List Declarations)
                 ->
                 (Result Walked (List Feedback)))))
    (define (declared-tops library tops body first-unused imported)
      (let* ((known (Known library
                           (scanned-tops (Scanned empty-table empty-table) tops)
                           (Declarations library empty-table empty-table empty-table)
                           imported))
             (start (Declaring first-unused known)))
        (result-let* ((signatures (declared-signatures known tops))
                      (reached (reached-tops start signatures tops)))
          (let* ((items (::first reached))
                 (dropped (dropped-types library items))
                 (state (with-known (::second reached)
                                    (known-with-drops (::known (::second reached)) dropped))))
            (walked-bodies (items-bodies (Bodies (Nil) (Nil) state)
                                         signatures
                                         (with-dropped items dropped))
                           body)))))

    ;; ---- Scan ----

    ;; The shape of each type and class, inside an instance scope too.
    (: scanned-tops (impl (Fn Scanned (List derived-Top) -> Scanned)))
    (define (scanned-tops scanned tops)
      (fold-left scanned-top scanned tops))

    (: scanned-top (impl (Fn Scanned derived-Top -> Scanned)))
    (define (scanned-top scanned top)
      (match top
        ((derived-Struct global parameters _ _ _ _ _)
         (with-scanned-type scanned (ScannedType global parameters)))
        ((derived-Enum global parameters _ _ _ _)
         (with-scanned-type scanned (ScannedType global parameters)))
        ((derived-Class global parameters members _ _)
         (Scanned (::types scanned)
                  (by-name (::classes scanned)
                           (::name global)
                           (ScannedClass global parameters (output-names members)))))
        ((derived-InstanceScope _ inner _) (scanned-tops scanned inner))
        (_ scanned)))

    (: with-scanned-type (impl (Fn Scanned ScannedType -> Scanned)))
    (define (with-scanned-type scanned type)
      (Scanned (by-name (::types scanned) (::name (::global type)) type) (::classes scanned)))

    (: output-names (impl (Fn (List expanded-Member) -> (List String))))
    (define (output-names members)
      (concatenate (map (lambda (member)
                          (match member
                            ((expanded-AssociatedOutput label _) (list (::name label)))
                            ((expanded-MethodSignature _ _ _ _) (Nil))))
                        members)))

    ;; ---- Declarations ----

    ;; What a declaration leaves for the bodies: a top that is done, or one
    ;; with bodies still to declare.
    (enum Reached
      (Ready
       ((top Top)))
      (Defining
        ((global expanded-Global)
         (value bound-Expr)
         (loc Loc)))
      (Stating
       ((expr bound-Expr)))
      (Instancing
       ((declared DeclaredInstance)))
      (Effecting
       ((declared DeclaredEffect)))
      (Scoping
       ((sets (List expanded-Global))
        (items (List Reached))
        (loc Loc)))
      (Setting
       ((global expanded-Global)
        (members (List ReachedMember))
        (loc Loc))))

    (enum ReachedMember
      (MemberInstancing
       ((declared DeclaredInstance)))
      (MemberReady
       ((member SetMember))))

    (: reached-tops
       (impl (Fn Declaring
                 Signatures
                 (List derived-Top)
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (reached-tops state signatures tops)
      (declaring-let* ((items state
                              (declaring-map state
                                             (lambda (state top) (reached-top state signatures top))
                                             tops)))
        (Ok (Pair (concatenate items) state))))

    ;; A declaration's entity, and what is known once it is reached. A
    ;; signature, converted already, leaves nothing.
    (: reached-top
       (impl (Fn Declaring
                 Signatures
                 derived-Top
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (reached-top state signatures top)
      (let ((known (::known state)))
        (match top
          ((derived-LinkImport global path digest file loc)
           (ready state (Ok (LinkImport global path digest file loc))))
          ((derived-Define global value loc) (Ok (Pair (list (Defining global value loc)) state)))
          ((derived-Signature _ _ _ _) (Ok (Pair (Nil) state)))
          ((derived-Statement expr) (Ok (Pair (list (Stating expr)) state)))
          ((derived-Expose target symbol dynamic? loc)
           (ready state (Ok (Expose target symbol dynamic? loc))))
          ((derived-Struct global parameters fields move? annotations name-loc loc)
           (data-reached state
                         (struct-data known
                                      signatures
                                      global
                                      parameters
                                      fields
                                      move?
                                      annotations
                                      name-loc
                                      loc)))
          ((derived-Enum global parameters cases move? annotations loc)
           (data-reached state
                         (enum-data known
                                    signatures
                                    global
                                    parameters
                                    cases
                                    move?
                                    annotations
                                    loc)))
          ((derived-Alias global parameters annotations loc)
           (ready state (Ok (Alias global parameters annotations loc))))
          ((derived-Class global parameters members annotations loc)
           (class-reached state
                          (declared-class known
                                          signatures
                                          global
                                          parameters
                                          members
                                          annotations
                                          loc)))
          ((derived-TopInstance instance)
           (declaring-let* ((declared state (declared-instance state instance)))
             (Ok (Pair (list (Instancing declared)) state))))
          ((derived-InstanceSet global members loc)
           (declaring-let* ((reached state (declaring-map state reached-member members)))
             (Ok (Pair (list (Setting global reached loc)) state))))
          ((derived-InstanceScope sets inner loc)
           (declaring-let* ((items state (reached-tops state signatures inner)))
             (Ok (Pair (list (Scoping sets items loc)) state))))
          ((derived-Extern global module symbol type annotations loc)
           (ready state
                  (declared-extern known signatures global module symbol type annotations loc)))
          ((derived-Effect global operations defaults around-main? annotations loc)
           (effect-reached state
                           (declared-effect state
                                            signatures
                                            global
                                            operations
                                            defaults
                                            around-main?
                                            annotations
                                            loc)))
          ((derived-Primitive global type loc)
           (ready state (declared-primitive known global type loc))))))

    (: ready
       (impl (Fn Declaring
                 (Result Top (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (ready state top)
      (result-let* ((done top))
        (Ok (Pair (list (Ready done)) state))))

    (: data-reached
       (impl (Fn Declaring
                 (Result Data (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (data-reached state declared)
      (result-let* ((data declared))
        (Ok (Pair (list (Ready (TopData data)))
                  (with-known state (known-with-data (::known state) data))))))

    (: class-reached
       (impl (Fn Declaring
                 (Result Class (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (class-reached state declared)
      (result-let* ((class declared))
        (Ok (Pair (list (Ready (TopClass class)))
                  (with-known state (known-with-class (::known state) class))))))

    ;; An effect is known by its operations.
    (: effect-reached
       (impl (Fn Declaring
                 (Result (Pair DeclaredEffect Declaring) (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (effect-reached state declared)
      (declaring-let* ((pending state declared))
        (let ((effect (::effect pending)))
          (Ok (Pair (list (Effecting pending))
                    (with-known state
                                (known-with-effect (::known state)
                                                   (OfferedEffect (::global effect)
                                                                  (::operations effect)))))))))

    (: reached-member
       (impl (Fn Declaring
                 bound-SetMember
                 ->
                 (Result (Pair ReachedMember Declaring) (List Feedback)))))
    (define (reached-member state member)
      (match member
        ((bound-SetInstance instance)
         (declaring-let* ((declared state (declared-instance state instance)))
           (Ok (Pair (MemberInstancing declared) state))))
        ((bound-DynamicInstances class pairs loc)
         (declaring-let* ((dynamic state
                                   (unchanged state
                                              (declared-dynamic (::known state) class pairs loc))))
           (Ok (Pair (MemberReady dynamic) state))))))

    ;; ---- Drop instances ----

    ;; Which of the library's types its Drop instances are for, found once
    ;; every declaration is reached, where they may be written before
    ;; their type or after it. The old compiler makes a type owned as it
    ;; reaches the type's Drop instance, and every read of that fact comes
    ;; once the library is expanded: the checker's lifecycle plans
    ;; (`linear-fields` and `data-plan`, src/snail/shell/compiler/
    ;; capabilities.sld) and the passes after it. No declaration and no
    ;; body reads it, there or here, so saying it once every declaration
    ;; is reached gives each read the old answer. A Drop instance written
    ;; before its type, where the old compiler fails, is accepted.
    (: dropped-types (impl (Fn LibraryName (List Reached) -> (List expanded-Global))))
    (define (dropped-types library items)
      (concatenate (map (lambda (instance)
                          (match (drop-type library instance)
                            ((Some type) (list type))
                            ((None) (Nil))))
                        (reached-instances items))))

    (: reached-instances (impl (Fn (List Reached) -> (List Instance))))
    (define (reached-instances items)
      (concatenate (map (lambda (item)
                          (match item
                            ((Instancing declared) (list (::instance declared)))
                            ((Scoping _ inner _) (reached-instances inner))
                            ((Setting _ members _) (concatenate (map member-instances members)))
                            (_ (Nil))))
                        items)))

    (: member-instances (impl (Fn ReachedMember -> (List Instance))))
    (define (member-instances member)
      (match member
        ((MemberInstancing declared) (list (::instance declared)))
        ((MemberReady _) (Nil))))

    (: with-dropped (impl (Fn (List Reached) (List expanded-Global) -> (List Reached))))
    (define (with-dropped items dropped)
      (map (lambda (item)
             (match item
               ((Ready (TopData data)) (Ready (TopData (with-drops data dropped))))
               ((Scoping sets inner loc) (Scoping sets (with-dropped inner dropped) loc))
               (_ item)))
           items))

    ;; ---- Bodies ----

    ;; What the bodies have made so far: the tops, latest first; the
    ;; feedback of every body that failed, in order; and the state.
    (struct Bodies
      ((tops (List Top))
       (feedback (List Feedback))
       (state Declaring)))

    (: with-top (impl (Fn Bodies Top Declaring -> Bodies)))
    (define (with-top bodies top state)
      (Bodies (Cons top (::tops bodies)) (::feedback bodies) state))

    ;; A body that failed leaves the numbers as they were.
    (: with-feedback (impl (Fn Bodies (List Feedback) -> Bodies)))
    (define (with-feedback bodies feedback)
      (Bodies (::tops bodies) (append (::feedback bodies) feedback) (::state bodies)))

    (: with-state (impl (Fn Bodies Declaring -> Bodies)))
    (define (with-state bodies state)
      (Bodies (::tops bodies) (::feedback bodies) state))

    ;; The program's body, the last body, and then the whole library, or
    ;; every body's problems.
    (: walked-bodies (impl (Fn Bodies (Option bound-Expr) -> (Result Walked (List Feedback)))))
    (define (walked-bodies bodies body)
      (let ((tops (reverse (::tops bodies)))
            (state (::state bodies)))
        (match body
          ((Some expr)
           (match (declared-expr (::known state) expr)
             ((Ok declared) (finished (::feedback bodies) (Walked tops (Some declared) state)))
             ((Err feedback) (Err (append (::feedback bodies) feedback)))))
          ((None) (finished (::feedback bodies) (Walked tops (None) state))))))

    (: finished (impl (Fn (List Feedback) Walked -> (Result Walked (List Feedback)))))
    (define (finished feedback walked)
      (if (null? feedback) (Ok walked) (Err feedback)))

    (: items-bodies (impl (Fn Bodies Signatures (List Reached) -> Bodies)))
    (define (items-bodies bodies signatures items)
      (fold-left (lambda (bodies item) (item-bodies bodies signatures item)) bodies items))

    (: item-bodies (impl (Fn Bodies Signatures Reached -> Bodies)))
    (define (item-bodies bodies signatures item)
      (let ((known (::known (::state bodies))))
        (match item
          ((Ready top) (with-top bodies top (::state bodies)))
          ((Defining global value loc)
           (match (declared-expr known value)
             ((Ok declared)
              (with-top bodies (definition signatures global declared loc) (::state bodies)))
             ((Err feedback) (with-feedback bodies feedback))))
          ((Stating expr)
           (match (declared-expr known expr)
             ((Ok declared) (with-top bodies (Statement declared) (::state bodies)))
             ((Err feedback) (with-feedback bodies feedback))))
          ((Instancing declared)
           (let ((done (instance-bodies bodies declared)))
             (with-top (::second done) (TopInstance (::first done)) (::state (::second done)))))
          ((Effecting declared) (effect-bodies bodies declared))
          ((Scoping sets items loc)
           (let ((inner (items-bodies (Bodies (Nil) (::feedback bodies) (::state bodies))
                                      signatures
                                      items)))
             (Bodies (Cons (InstanceScope sets (reverse (::tops inner)) loc) (::tops bodies))
                     (::feedback inner)
                     (::state inner))))
          ((Setting global members loc) (set-bodies bodies global members loc)))))

    ;; Each method's value is a body of its own.
    (: instance-bodies (impl (Fn Bodies DeclaredInstance -> (Pair Instance Bodies))))
    (define (instance-bodies bodies declared)
      (let loop ((bodies bodies)
                 (methods (::methods declared))
                 (done (Nil)))
        (match methods
          ((Nil) (Pair (instance-with-methods (::instance declared) (reverse done)) bodies))
          ((Cons method rest)
           (match (declared-method (::known (::state bodies)) method)
             ((Ok value) (loop bodies rest (Cons value done)))
             ((Err feedback) (loop (with-feedback bodies feedback) rest done)))))))

    ;; Each default's value is a body of its own.
    (: effect-bodies (impl (Fn Bodies DeclaredEffect -> Bodies)))
    (define (effect-bodies bodies declared)
      (let loop ((bodies bodies)
                 (defaults (::defaults declared))
                 (done (Nil)))
        (match defaults
          ((Nil)
           (with-top bodies
                     (TopEffect (effect-with-defaults (::effect declared) (reverse done)))
                     (::state bodies)))
          ((Cons default rest)
           (match (declared-default (::state bodies) default)
             ((Ok (Pair value state)) (loop (with-state bodies state) rest (Cons value done)))
             ((Err feedback) (loop (with-feedback bodies feedback) rest done)))))))

    (: set-bodies
       (impl (Fn Bodies expanded-Global (List ReachedMember) Loc -> Bodies)))
    (define (set-bodies bodies global members loc)
      (let loop ((bodies bodies)
                 (members members)
                 (done (Nil)))
        (match members
          ((Nil) (with-top bodies (InstanceSet global (reverse done) loc) (::state bodies)))
          ((Cons (MemberInstancing declared) rest)
           (let ((instanced (instance-bodies bodies declared)))
             (loop (::second instanced) rest (Cons (SetInstance (::first instanced)) done))))
          ((Cons (MemberReady member) rest) (loop bodies rest (Cons member done))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-top)
    (import
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-top)
        (test-order)
        (test-drops)
        (test-bodies))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (expanded-Global main name 0))

      (define (i64-at line)
        (expanded-Applied (expanded-Global forms-library "I64" 0) "I64" (list) (at line)))

      (define i64 (Con (expanded-Global forms-library "I64" 0) (list)))

      (define (unit-at line)
        (bound-Literal (expanded-UnitValue) (at line)))

      (define (walk tops body)
        (declared-tops main tops body 10 (list)))

      (define (box-struct line)
        (derived-Struct (global "Box")
                        (list)
                        (list (expanded-Field "x" #f (i64-at line) (list) (at line)))
                        #f
                        (list)
                        (at line)
                        (at line)))

      ;; (typeclass (Show a) (: show (impl (Fn a -> I64))))
      (define show-class
        (derived-Class (global "Show")
                       (list "a")
                       (list (expanded-MethodSignature
                              (global "show")
                              (expanded-Scheme (list)
                                               (list)
                                               (expanded-Callable (expanded-Impl)
                                                                  (expanded-FnContract)
                                                                  (expanded-Arrow
                                                                   (list (expanded-Variable "a"
                                                                                            loc))
                                                                   (i64-at 2)
                                                                   (expanded-Effects (list) (None)))
                                                                  loc)
                                               loc)
                              (list)
                              loc))
                       (list)
                       loc))

      (define (show-instance line)
        (derived-TopInstance
         (bound-Instance (expanded-ClassGlobal (global "Show"))
                         (list)
                         (list (i64-at line))
                         (list)
                         (list)
                         (bound-Methods
                          (list (bound-InstanceMethod (expanded-MemberName (expanded-Label "show"
                                                                                           (at
                                                                                            line)))
                                                      (unit-at line))))
                         (at line))))

      ;; A declaration sees the entities of those before it: an instance
      ;; before its class finds no method there; and the first problem in
      ;; a declaration is the library's only one.
      (define (test-order)
        (expect (walk (list (show-instance 3) show-class) (None))
                (fail (at 3) "not a method of this class: show"))
        (match (walk (list show-class (show-instance 3)) (None))
          ((Ok walked)
           (expect (length (::tops walked)) 2)
           (expect (::next (::state walked)) 12)
           (match (list-ref (::tops walked) 1)
             ((TopInstance instance)
              (expect (::global instance) (expanded-Global main "Show" 10))
              (expect (::body instance)
                      (Methods (list (InstanceMethod (ClassMethod (global "show"))
                                                     (expanded-Global main "show" 11)
                                                     (Literal (expanded-UnitValue) (at 3))
                                                     (at 3))))))
             (other (expect other "an instance"))))
          (other (expect other "a class and its instance")))
        (expect (walk (list (box-struct 2)
                            (derived-Struct (global "Bad")
                                            (list)
                                            (list (expanded-Field "y"
                                                                  #f
                                                                  (expanded-Applied (global "Box")
                                                                                    "Box"
                                                                                    (list
                                                                                     (i64-at 4))
                                                                                    (at 4))
                                                                  (list)
                                                                  (at 4)))
                                            #f
                                            (list)
                                            (at 4)
                                            (at 4))
                            (derived-Define (global "x")
                                            (bound-Ann (unit-at 5) (i64-at 5) (at 5))
                                            (at 5)))
                      (None))
                (fail (at 4) "wrong number of type arguments: Box")))

      ;; A Drop instance written before its type makes it moved, in the
      ;; tree and in the offer.
      (define (test-drops)
        (let ((drop (derived-TopInstance
                     (bound-Instance (expanded-ClassGlobal drop-class)
                                     (list)
                                     (list (expanded-Row (expanded-Effects (list) (None)) loc)
                                           (expanded-Applied (global "Box") "Box" (list) loc))
                                     (list)
                                     (list)
                                     (bound-Dispatch (list) loc)
                                     loc))))
          (match (declared-tops main
                                (list drop (box-struct 2))
                                (None)
                                1
                                (list (Declarations (list "snail" "core" "base")
                                                    empty-table
                                                    (by-name empty-table
                                                             "Drop"
                                                             (Class drop-class
                                                                    (list (RowParameter "e")
                                                                          (TypeParameter "T"))
                                                                    (list)
                                                                    (list)
                                                                    (list)
                                                                    loc))
                                                    empty-table)))
            ((Ok walked)
             (match (list-ref (::tops walked) 1)
               ((TopData data) (expect (::drop? data) #t))
               (other (expect other "a struct")))
             (expect (map ::drop?
                          (concatenate
                           (table-values (::data (::declared (::known (::state walked)))))))
                     (list #t)))
            (other (expect other "a library with a Drop instance")))))

      ;; Every body's problem, in order, the program's body last; a body
      ;; that fails leaves the numbers as they were.
      (define (test-bodies)
        (let ((bad (lambda (line)
                     (bound-Ann (unit-at line)
                                (expanded-Applied (global "Box")
                                                  "Box"
                                                  (list (i64-at line))
                                                  (at line))
                                (at line)))))
          (expect (walk (list (box-struct 1)
                              (derived-Define (global "y") (bad 3) (at 3))
                              (derived-Define (global "z") (unit-at 4) (at 4))
                              (derived-Define (global "w") (bad 5) (at 5)))
                        (Some (bad 6)))
                  (Err (list (Feedback (at 3) "wrong number of type arguments: Box")
                             (Feedback (at 5) "wrong number of type arguments: Box")
                             (Feedback (at 6) "wrong number of type arguments: Box"))))
          (match (walk (list (derived-Define (global "z") (unit-at 4) (at 4))) (Some (unit-at 6)))
            ((Ok walked)
             (expect (::tops walked)
                     (list (Define (global "z")
                             (Literal (expanded-UnitValue) (at 4))
                             (None)
                             (list)
                             (at 4))))
             (expect (::body walked) (Some (Literal (expanded-UnitValue) (at 6))))
             (expect (::next (::state walked)) 10))
            (other (expect other "a program")))))))
   (else)))
