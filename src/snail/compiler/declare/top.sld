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
;; 4. Each struct is checked to be one a program can build, in order; the
;;    first problem stops the library.
;; 5. Each body, in order, is declared, once every declaration is
;;    reached: a definition's signature checked again and then its value,
;;    a statement, each method of an instance and each default of an
;;    effect. A body that fails leaves the numbers as they were, and the
;;    bodies after it are declared all the same, so every body's problem
;;    is returned, in order.
(define-library (snail compiler declare top)
  (export
   Walked
   declared-tops)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (snail compiler names libraries)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler names globals) Global)
   (prefix (snail compiler bind language) bound-)
   (prefix (snail compiler derive language) derived-)
   (snail compiler declare language)
   (snail compiler declare offer)
   (only (snail compiler names numbering) Numbering)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare values)
   (snail compiler declare data)
   (snail compiler declare classes)
   (snail compiler declare effects)
   (snail compiler declare instances)
   (snail compiler declare lifecycle)
   (snail compiler declare buildable)
   (snail compiler declare expressions))
  (begin

    ;; ---- The top level ----

    ;; The library's tops declared, and the state the bodies leave: the
    ;; numbering, and what is known once every declaration is reached,
    ;; which the library offers.
    (struct Walked
      ((tops (List Top))
       (state Declaring)))

    ;; `imported` holds what each library in the import closure offers.
    ;; Once every declaration is reached and every struct can be built, the
    ;; library's types are marked on the items reached, and what the bodies
    ;; know of the library's own declarations is read again from those
    ;; items, as each declaration added its entity when it was reached,
    ;; starting from what was known before any. The library offers what the
    ;; bodies know, so the tree the bodies write and the offer agree.
    (: declared-tops
       (impl (Fn LibraryName
                 (List derived-Top)
                 I64
                 (List Declarations)
                 ->
                 (Result Walked (List Feedback)))))
    (define (declared-tops library tops first-unused imported)
      (let* ((known (Known library
                           (scanned-tops (Scanned empty-table empty-table) tops)
                           (Declarations library empty-table empty-table empty-table)
                           imported))
             (start (Declaring (Numbering library first-unused) known)))
        (result-let* ((signatures (declared-signatures known tops))
                      (reached (reached-tops start signatures tops))
                      (buildable (buildable-items (::known (::second reached)) (::first reached))))
          (let* ((items (with-dropped buildable (dropped-types buildable)))
                 (state (Declaring-known-set (::second reached)
                                             (fold-left known-with-item known items))))
            (walked-bodies (items-bodies (Bodies (Nil) (Nil) state) signatures items))))))

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
        ((global Global)
         (value bound-Expr)
         (loc Loc)))
      (Stating
       ((expr bound-Expr)))
      (Instancing
       ((declared DeclaredInstance)))
      (Effecting
       ((declared DeclaredEffect)))
      (Scoping
       ((sets (List Global))
        (items (List Reached))
        (loc Loc)))
      (Setting
       ((global Global)
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
      (result-state-let* ((items state
                                 (map-results-with-state state
                                                         (lambda (state top)
                                                           (reached-top state signatures top))
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
           (result-state-let* ((declared state
                                         (numbered state
                                                   (declared-instance (::numbering state)
                                                                      known
                                                                      instance
                                                                      #f))))
             (Ok (Pair (list (Instancing declared)) state))))
          ((derived-InstanceSet global members loc)
           (result-state-let* ((reached state
                                        (map-results-with-state state reached-member members)))
             (Ok (Pair (list (Setting global reached loc)) state))))
          ((derived-InstanceScope sets inner loc)
           (result-state-let* ((items state (reached-tops state signatures inner)))
             (Ok (Pair (list (Scoping sets items loc)) state))))
          ((derived-Extern global module symbol type annotations loc)
           (ready state
                  (declared-extern known signatures global module symbol type annotations loc)))
          ((derived-Effect global operations defaults around-main? annotations loc)
           (effect-reached state
                           (numbered state
                                     (declared-effect (::numbering state)
                                                      known
                                                      signatures
                                                      global
                                                      operations
                                                      defaults
                                                      around-main?
                                                      annotations
                                                      loc))))
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
        (entity-reached state (Ready (TopData data)))))

    (: class-reached
       (impl (Fn Declaring
                 (Result Class (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (class-reached state declared)
      (result-let* ((class declared))
        (entity-reached state (Ready (TopClass class)))))

    (: effect-reached
       (impl (Fn Declaring
                 (Result (Pair DeclaredEffect Declaring) (List Feedback))
                 ->
                 (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (effect-reached state declared)
      (result-state-let* ((pending state declared))
        (entity-reached state (Effecting pending))))

    (: entity-reached
       (impl (Fn Declaring Reached -> (Result (Pair (List Reached) Declaring) (List Feedback)))))
    (define (entity-reached state item)
      (Ok (Pair (list item) (Declaring-known-set state (known-with-item (::known state) item)))))

    ;; A part's step, which knows nothing new and changes the numbering
    ;; only, as a step of the walk.
    (: numbered
       (All (T)
            (impl (Fn Declaring
                      (Result (Pair T Numbering) (List Feedback))
                      ->
                      (Result (Pair T Declaring) (List Feedback))))))
    (define (numbered state step)
      (result-state-let* ((value numbering step))
        (Ok (Pair value (Declaring-numbering-set state numbering)))))

    ;; What is known once `item` is reached: the entity it holds, among the
    ;; library's own, and those an instance scope holds, in order. An
    ;; effect is known by its operations.
    (: known-with-item (impl (Fn Known Reached -> Known)))
    (define (known-with-item known item)
      (match item
        ((Ready (TopData data)) (known-with-data known data))
        ((Ready (TopClass class)) (known-with-class known class))
        ((Effecting declared)
         (let ((effect (::effect declared)))
           (known-with-effect known (OfferedEffect (::global effect) (::operations effect)))))
        ((Scoping _ inner _) (fold-left known-with-item known inner))
        (_ known)))

    (: reached-member
       (impl (Fn Declaring
                 bound-SetMember
                 ->
                 (Result (Pair ReachedMember Declaring) (List Feedback)))))
    (define (reached-member state member)
      (match member
        ((bound-SetInstance instance)
         (result-state-let* ((declared state
                                       (numbered state
                                                 (declared-instance (::numbering state)
                                                                    (::known state)
                                                                    instance
                                                                    #t))))
           (Ok (Pair (MemberInstancing declared) state))))
        ((bound-DynamicInstances class pairs loc)
         (result-let* ((dynamic (declared-dynamic (::known state) class pairs loc)))
           (Ok (Pair (MemberReady dynamic) state))))))

    ;; ---- Buildable structs ----

    ;; The items, once every struct among them can be built, each refused
    ;; where its name is written, in the order written; the first problem
    ;; stops the library, as the old compiler's `check-buildable-structs`
    ;; checks them once every declaration is reached and before any body.
    (: buildable-items
       (impl (Fn Known (List Reached) -> (Result (List Reached) (List Feedback)))))
    (define (buildable-items known items)
      (result-let* ((every (map-results (lambda (found)
                                          (checked (struct-problem known (::first found))
                                                   (::second found)))
                                        (reached-structs items))))
        (Ok items)))

    ;; Each struct among the items, inside an instance scope too, and where
    ;; its name is written, its one case's place.
    (: reached-structs (impl (Fn (List Reached) -> (List (Pair Data Loc)))))
    (define (reached-structs items)
      (concatenate (map (lambda (item)
                          (match item
                            ((Ready (TopData data))
                             (match (Pair (::kind data) (::cases data))
                               ((Pair (StructData) (Cons case (Nil)))
                                (list (Pair data (::loc case))))
                               (_ (Nil))))
                            ((Scoping _ inner _) (reached-structs inner))
                            (_ (Nil))))
                        items)))

    ;; ---- Drop instances ----

    ;; Which of the library's types its Drop instances are for, found once
    ;; every declaration is reached, where they may be written before
    ;; their type or after it. The old compiler makes a type owned as it
    ;; reaches the type's Drop instance, and every read of that fact comes
    ;; once the library is expanded: the checker's lifecycle plans
    ;; (`linear-fields` and `data-plan`, src/snail/shell/compiler/
    ;; capabilities.sld) and the passes after it. No declaration reads it,
    ;; there or here; a body asks only whether a type of another library
    ;; has a Drop instance (`owned`), which that library's offer says in
    ;; full. So saying it once every declaration is reached gives each read
    ;; the old answer. A Drop instance written before its type, where the
    ;; old compiler fails, is accepted. The mark is made once, on the
    ;; items, and the bodies and the offer read it there.
    (: dropped-types (impl (Fn (List Reached) -> (List Global))))
    (define (dropped-types items)
      (concatenate (map (lambda (instance)
                          (match (drop-type instance)
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

    (: with-dropped (impl (Fn (List Reached) (List Global) -> (List Reached))))
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

    (: with-numbering (impl (Fn Bodies Numbering -> Bodies)))
    (define (with-numbering bodies numbering)
      (Bodies (::tops bodies)
              (::feedback bodies)
              (Declaring-numbering-set (::state bodies) numbering)))

    ;; The whole library, or every body's problems.
    (: walked-bodies (impl (Fn Bodies -> (Result Walked (List Feedback)))))
    (define (walked-bodies bodies)
      (if (null? (::feedback bodies))
          (Ok (Walked (reverse (::tops bodies)) (::state bodies)))
          (Err (::feedback bodies))))

    (: items-bodies (impl (Fn Bodies Signatures (List Reached) -> Bodies)))
    (define (items-bodies bodies signatures items)
      (fold-left (lambda (bodies item) (item-bodies bodies signatures item)) bodies items))

    (: item-bodies (impl (Fn Bodies Signatures Reached -> Bodies)))
    (define (item-bodies bodies signatures item)
      (let ((known (::known (::state bodies))))
        (match item
          ((Ready top) (with-top bodies top (::state bodies)))
          ((Defining global value loc)
           (match (declared-definition known signatures global value loc)
             ((Ok top) (with-top bodies top (::state bodies)))
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
           (match (declared-default (::numbering (::state bodies))
                                    (::known (::state bodies))
                                    default)
             ((Ok (Pair value numbering))
              (loop (with-numbering bodies numbering) rest (Cons value done)))
             ((Err feedback) (loop (with-feedback bodies feedback) rest done)))))))

    (: set-bodies
       (impl (Fn Bodies Global (List ReachedMember) Loc -> Bodies)))
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
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler builtins base) drop-class)
     (only (snail compiler names globals) TopGlobal ClassGlobal Label)
     (only (snail compiler literals constant) UnitValue)
     (snail stage0 testing))
    (begin
      (define (test-top)
        (test-order)
        (test-drops)
        (test-buildable)
        (test-rows)
        (test-bodies))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define (i64-at line)
        (expanded-Applied (Global forms-library "I64" 0) "I64" (list) (at line)))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define (unit-at line)
        (bound-Literal (UnitValue) (at line)))

      (define (walk tops)
        (declared-tops main tops 10 (list)))

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
         (bound-Instance (ClassGlobal (global "Show"))
                         (list)
                         (list (i64-at line))
                         (list)
                         (list)
                         (bound-Methods
                          (list (bound-InstanceMethod (expanded-MemberName (Label "show"
                                                                                  (at
                                                                                   line)))
                                                      (unit-at line))))
                         (at line))))

      ;; A declaration sees the entities of those before it: an instance
      ;; before its class finds no method there; and the first problem in
      ;; a declaration is the library's only one.
      (define (test-order)
        (expect (walk (list (show-instance 3) show-class))
                (fail (at 3) "not a method of this class: show"))
        (match (walk (list show-class (show-instance 3)))
          ((Ok walked)
           (expect (length (::tops walked)) 2)
           (expect (::next (::numbering (::state walked))) 12)
           (match (list-ref (::tops walked) 1)
             ((TopInstance instance)
              (expect (::global instance) (Global main "Show" 10))
              (expect (::body instance)
                      (Methods (list (InstanceMethod (ClassMethod (global "show"))
                                                     (Global main "show" 11)
                                                     (Literal (UnitValue) (at 3))
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
                                            (at 5))))
                (fail (at 4) "wrong number of type arguments: Box")))

      ;; A Drop instance written before its type makes it moved, in the
      ;; tree and in the offer.
      (define (test-drops)
        (let ((drop (derived-TopInstance
                     (bound-Instance (ClassGlobal drop-class)
                                     (list)
                                     (list (expanded-Row (expanded-Effects (list) (None)) loc)
                                           (expanded-Applied (global "Box") "Box" (list) loc))
                                     (list)
                                     (list)
                                     (bound-Dispatch (list) loc)
                                     loc))))
          (match (declared-tops main
                                (list drop (box-struct 2))
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

      (define (bad-at line)
        (bound-Ann (unit-at line)
                   (expanded-Applied (global "Box") "Box" (list (i64-at line)) (at line))
                   (at line)))

      ;; `(struct NAME (next NAME))`, written at `line`.
      (define (self-struct name line)
        (derived-Struct (global name)
                        (list)
                        (list (expanded-Field "next"
                                              #f
                                              (expanded-Applied (global name) name (list) (at line))
                                              (list)
                                              (at line)))
                        #f
                        (list)
                        (at line)
                        (at (+ line 100))))

      ;; Once every declaration is reached, the first struct that can never
      ;; be built, at its name, stops the library before any body
      ;; (error-struct-contains-itself.sld); one inside an instance scope
      ;; is checked in its turn.
      (define (test-buildable)
        (expect (walk (list (box-struct 1)
                            (derived-Define (global "x") (bad-at 2) (at 2))
                            (self-struct "A" 3)
                            (self-struct "B" 4)))
                (fail (at 3)
                      "the struct A can never be built: each of its values would contain another"))
        (expect (walk (list (derived-InstanceScope (list (global "set"))
                                                   (list (box-struct 1) (self-struct "B" 4))
                                                   loc)
                            (self-struct "A" 5)))
                (fail (at 4)
                      "the struct B can never be built: each of its values would contain another")))

      ;; (typeclass (Store e S) (: fetch (impl (Fn S -> String ! e)))), at
      ;; `line`, whose e is a row once it is reached.
      (define (store-class line)
        (derived-Class (global "Store")
                       (list "e" "S")
                       (list (expanded-MethodSignature
                              (global "fetch")
                              (expanded-Scheme
                               (list)
                               (list)
                               (expanded-Callable (expanded-Impl)
                                                  (expanded-FnContract)
                                                  (expanded-Arrow
                                                   (list (expanded-Variable "S" loc))
                                                   (expanded-Applied (Global forms-library
                                                                             "String"
                                                                             0)
                                                                     "String"
                                                                     (list)
                                                                     loc)
                                                   (expanded-Effects
                                                    (list)
                                                    (Some (expanded-Variable "e" loc))))
                                                  loc)
                               (at line))
                              (list)
                              (at line)))
                       (list)
                       (at line)))

      ;; `(requires (Store I64 T))`, at `line`.
      (define (store-i64 line)
        (expanded-ClassRequirement (ClassGlobal (global "Store"))
                                   (list (i64-at line) (expanded-Variable "T" loc))
                                   (list)
                                   (at line)))

      ;; (typeclass (Uses S) (: use (All (T) (requires (Store I64 T)) I64))).
      (define (uses-class line)
        (derived-Class (global "Uses")
                       (list "S")
                       (list (expanded-MethodSignature (global "use")
                                                       (expanded-Scheme (list "T")
                                                                        (list (store-i64
                                                                               (+ line 50)))
                                                                        (i64-at line)
                                                                        (at line))
                                                       (list)
                                                       (at line)))
                       (list)
                       (at line)))

      ;; A requirement's rows are checked as far as its class's rows are
      ;; known where it is written (note 6 of the inventory). A
      ;; declaration's requirement sees the rows of a class declared before
      ;; it, refused at the requirement, and none of one declared after
      ;; (build/declare-probes/row-method-*.sld). A signature sees no row of
      ;; the library's own classes; a definition's is checked again, at the
      ;; signature, before its value, and the bodies after it are declared
      ;; all the same (error-class-row-requires-row.sld).
      (define (test-rows)
        (expect (walk (list (store-class 1) (uses-class 2)))
                (fail (at 52) "a constraint gives the class's row parameter e a row"))
        (expect (match (walk (list (uses-class 2) (store-class 3)))
                  ((Ok walked) (length (::tops walked)))
                  (other other))
                2)
        (let ((signature (derived-Signature (TopGlobal (global "f"))
                                            (expanded-Scheme (list "T")
                                                             (list (store-i64 5))
                                                             (i64-at 5)
                                                             (at 5))
                                            (list)
                                            (at 4))))
          (expect (walk (list (box-struct 1)
                              signature
                              (derived-Define (global "f") (bad-at 6) (at 6))
                              (store-class 7)
                              (derived-Define (global "g") (bad-at 8) (at 8))))
                  (Err
                   (list (Feedback (at 4) "a constraint gives the class's row parameter e a row")
                         (Feedback (at 8) "wrong number of type arguments: Box"))))))

      ;; Every body's problem, in order, a statement's where it is written
      ;; among the definitions, as the old compiler reports those of
      ;; `(ann 1 (Box I64))`, `(define y (ann 2 (Box I64)))` and `(ann 3
      ;; (Box I64))` written one to a line; a body that fails leaves the
      ;; numbers as they were.
      (define (test-bodies)
        (let ((bad (lambda (line)
                     (bound-Ann (unit-at line)
                                (expanded-Applied (global "Box")
                                                  "Box"
                                                  (list (i64-at line))
                                                  (at line))
                                (at line)))))
          (expect (walk (list (box-struct 4)
                              (derived-Statement (bad 7))
                              (derived-Define (global "y") (bad 8) (at 8))
                              (derived-Statement (bad 9))))
                  (Err (list (Feedback (at 7) "wrong number of type arguments: Box")
                             (Feedback (at 8) "wrong number of type arguments: Box")
                             (Feedback (at 9) "wrong number of type arguments: Box"))))
          (match (walk (list (derived-Statement (unit-at 3))
                             (derived-Define (global "z") (unit-at 4) (at 4))))
            ((Ok walked)
             (expect (::tops walked)
                     (list (Statement (Literal (UnitValue) (at 3)))
                           (Define (global "z")
                             (Literal (UnitValue) (at 4))
                             (None)
                             (list)
                             (at 4))))
             (expect (::next (::numbering (::state walked))) 10))
            (other (expect other "a program")))))))
   (else)))
