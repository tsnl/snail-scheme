;; Effects: an effect becomes its Effect, as the old compiler's
;; `declare-effect` (src/snail/shell/compiler/expand.sld) declares it.
;; Each operation's scheme is converted in order, where no requirement is
;; in scope, and is executable code's; an operation is then its type's
;; parameters, result and latent effects, without its own effect. Then
;; each default entry, in order, names an operation of the effect, and its
;; implementation is given a Global of its own, named for the operation.
;; The first problem stops the declaration. A default's value is a body,
;; declared with the library's other bodies, once every declaration is
;; reached: a lambda, as written, or a function's name, which becomes the
;; lambda that calls it with the operation's arguments, each a local of
;; its own, as the old compiler's `eta-expand` writes it.
(define-library (snail compiler declare effects)
  (export
   DeclaredEffect
   PendingDefault
   declared-effect
   declared-default
   effect-with-defaults)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (prefix (snail compiler bind language) bound-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare state)
   (snail compiler declare callables)
   (snail compiler declare operations)
   (snail compiler declare members)
   (snail compiler declare types)
   (snail compiler declare values)
   (snail compiler declare expressions))
  (begin

    ;; ---- Effects ----

    ;; An effect declared, its defaults still to come, and what each
    ;; default's body needs: the operation it implements, the Global of its
    ;; implementation, its value, and its entry's place.
    (struct DeclaredEffect
      ((effect Effect)
       (defaults (List PendingDefault))))

    (struct PendingDefault
      ((operation Operation)
       (implementation expanded-Global)
       (value bound-Expr)
       (loc Loc)))

    (: declared-effect
       (impl (Fn Declaring
                 Signatures
                 expanded-Global
                 (List expanded-Operation)
                 (List bound-Default)
                 Bool
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result (Pair DeclaredEffect Declaring) (List Feedback)))))
    (define (declared-effect state
                             signatures
                             global
                             operations
                             defaults
                             around-main?
                             annotations
                             loc)
      (declaring-let* ((declared state
                                 (unchanged state
                                            (map-results (lambda (operation)
                                                           (declared-operation (::known state)
                                                                               signatures
                                                                               operation))
                                                         operations)))
                       (pending state
                                (declaring-map state
                                               (lambda (state default)
                                                 (pending-default state declared default))
                                               defaults)))
        (Ok
         (Pair (DeclaredEffect (Effect global declared (Nil) around-main? annotations loc) pending)
               state))))

    ;; ---- Operations ----

    ;; What the operation's type says, refused at the type.
    (: declared-operation
       (impl (Fn Known Signatures expanded-Operation -> (Result Operation (List Feedback)))))
    (define (declared-operation known signatures operation)
      (let ((written (::scheme operation)))
        (result-let* ((scheme (declared-scheme (Scope known (Nil)) written)))
          (match (operation-type (operational-scheme scheme))
            ((Ok type)
             (Ok (Operation (::global operation)
                            (::control? operation)
                            (::parameters type)
                            (::result type)
                            (::latent type)
                            (append (::annotations operation)
                                    (signature-annotations signatures (::global operation)))
                            (::loc operation))))
            ((Err message) (fail (::loc written) message))))))

    ;; ---- Defaults ----

    ;; A default's operation, refused at the label that names it, and its
    ;; implementation's Global.
    (: pending-default
       (impl (Fn Declaring
                 (List Operation)
                 bound-Default
                 ->
                 (Result (Pair PendingDefault Declaring) (List Feedback)))))
    (define (pending-default state operations default)
      (let ((label (::label default)))
        (match (named-operation operations (::name label))
          ((Ok operation)
           (declaring-let* ((implementation state
                                            (fresh-global state (::name (::global operation)))))
             (Ok (Pair (PendingDefault operation implementation (::value default) (::loc default))
                       state))))
          ((Err message) (fail (::loc label) message)))))

    ;; ---- Default bodies ----

    (: declared-default
       (impl (Fn Declaring PendingDefault -> (Result (Pair Default Declaring) (List Feedback)))))
    (define (declared-default state pending)
      (let ((operation (::operation pending))
            (loc (::loc pending)))
        (declaring-let* ((value state
                                (unchanged state (declared-expr (::known state) (::value pending))))
                         (function state
                                   (default-function state
                                     value
                                     (length (::parameters operation))
                                     loc)))
          (Ok
           (Pair (Default (::global operation) (::implementation pending) function loc) state)))))

    ;; `expand` leaves a default a Lambda, a ClosedLambda or a name.
    (: default-function
       (impl (Fn Declaring Expr I64 Loc -> (Result (Pair Expr Declaring) (List Feedback)))))
    (define (default-function state value arity loc)
      (match value
        ((LocalRef _ _) (calling state value arity loc))
        ((TopRef _ _) (calling state value arity loc))
        (_ (Ok (Pair value state)))))

    ;; `(lambda (argument ...) (function argument ...))`, at the entry.
    (: calling (impl (Fn Declaring Expr I64 Loc -> (Result (Pair Expr Declaring) (List Feedback)))))
    (define (calling state function arity loc)
      (declaring-let* ((arguments state
                                  (declaring-map state
                                                 (lambda (state index)
                                                   (fresh-local state "argument"))
                                                 (iota arity))))
        (Ok (Pair (Lambda arguments
                          (Call function
                                (map (lambda (argument) (LocalRef argument loc)) arguments)
                                loc)
                          loc)
                  state))))

    (: effect-with-defaults (impl (Fn Effect (List Default) -> Effect)))
    (define (effect-with-defaults effect defaults)
      (Effect (::global effect)
              (::operations effect)
              defaults
              (::around-main? effect)
              (::annotations effect)
              (::loc effect)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-effects)
    (import
     (snail core table)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-effects)
        (test-operations)
        (test-defaults)
        (test-default-bodies))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (expanded-Global main name 0))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main empty-table empty-table empty-table)
               (list)))

      (define no-signatures
        (match (declared-signatures known (list))
          ((Ok signatures) signatures)
          ((Err _) (panic "no signatures"))))

      (define (i64-at line)
        (expanded-Applied (expanded-Global forms-library "I64" 0) "I64" (list) (at line)))

      (define i64 (Con (expanded-Global forms-library "I64" 0) (list)))

      (define log (global "log"))

      (define (operation name control? type line)
        (expanded-Operation (global name)
                            control?
                            (expanded-Scheme (list) (list) type (at line))
                            (list)
                            (at line)))

      (define (function parameters effects)
        (expanded-Callable (expanded-Impl)
                           (expanded-FnContract)
                           (expanded-Arrow parameters (i64-at 1) effects)
                           loc))

      (define read-op
        (operation "read" #f (function (list) (expanded-Effects (list log) (None))) 2))
      (define jump-op
        (operation "jump" #t (function (list (i64-at 1)) (expanded-Effects (list) (None))) 3))

      (define (state-from next)
        (Declaring next known))

      (define (unit-at line)
        (bound-Literal (expanded-UnitValue) (at line)))

      (define (default name line)
        (bound-Default (expanded-Label name (at line)) (unit-at line) (at line)))

      (define declared-read (Operation (global "read") #f (list) i64 (list log) (list) (at 2)))
      (define declared-jump (Operation (global "jump") #t (list i64) i64 (list) (list) (at 3)))

      ;; An operation is its type's parameters, result and latent effects;
      ;; a type that is no function with a closed row is refused at it.
      (define (test-operations)
        (expect (declared-effect (state-from 4)
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list)
                                 #t
                                 (list)
                                 loc)
                (Ok (Pair (DeclaredEffect (Effect (global "io")
                                                  (list declared-read declared-jump)
                                                  (list)
                                                  #t
                                                  (list)
                                                  loc)
                                          (list))
                          (state-from 4))))
        (expect (declared-effect (state-from 4)
                                 no-signatures
                                 (global "io")
                                 (list read-op (operation "bad" #f (i64-at 5) 5))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 5)
                      "an operation has a function type with a closed row; its effect is implied"))
        (expect (declared-effect (state-from 4)
                                 no-signatures
                                 (global "io")
                                 (list (operation "open"
                                                  #f
                                                  (function (list)
                                                            (expanded-Effects
                                                             (list)
                                                             (Some (expanded-Variable "e" loc))))
                                                  6))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 6)
                      "an operation has a function type with a closed row; its effect is implied")))

      ;; Each default names an operation, refused at its label, and takes
      ;; the next number for its implementation, named for the operation.
      (define (test-defaults)
        (expect (declared-effect (state-from 4)
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list (default "read" 7) (default "jump" 8))
                                 #f
                                 (list)
                                 loc)
                (Ok (Pair (DeclaredEffect (Effect (global "io")
                                                  (list declared-read declared-jump)
                                                  (list)
                                                  #f
                                                  (list)
                                                  loc)
                                          (list (PendingDefault declared-read
                                                                (expanded-Global main "read" 4)
                                                                (unit-at 7)
                                                                (at 7))
                                                (PendingDefault declared-jump
                                                                (expanded-Global main "jump" 5)
                                                                (unit-at 8)
                                                                (at 8))))
                          (state-from 6))))
        (expect (declared-effect (state-from 4)
                                 no-signatures
                                 (global "io")
                                 (list read-op)
                                 (list (default "read" 7) (default "write" 9))
                                 #f
                                 (list)
                                 loc)
                (fail (at 9) "not an operation of this effect: write")))

      ;; A lambda stays as written; a name is called with a local of its
      ;; own for each of the operation's parameters, numbered in turn.
      (define (test-default-bodies)
        (let ((lambda-value (bound-Lambda (list) (unit-at 7) (at 7)))
              (name (bound-TopRef (expanded-TopGlobal (global "jump-twice")) (at 8))))
          (expect (declared-default (state-from 6)
                                    (PendingDefault declared-read
                                                    (expanded-Global main "read" 4)
                                                    lambda-value
                                                    (at 7)))
                  (Ok (Pair (Default (global "read")
                              (expanded-Global main "read" 4)
                              (Lambda (list) (Literal (expanded-UnitValue) (at 7)) (at 7))
                              (at 7))
                            (state-from 6))))
          (expect (declared-default (state-from 6)
                                    (PendingDefault declared-jump
                                                    (expanded-Global main "jump" 5)
                                                    name
                                                    (at 9)))
                  (Ok (Pair (Default (global "jump")
                              (expanded-Global main "jump" 5)
                              (Lambda (list (expanded-Local "argument" 6))
                                      (Call
                                       (TopRef (expanded-TopGlobal (global "jump-twice")) (at 8))
                                       (list (LocalRef (expanded-Local "argument" 6) (at 9)))
                                       (at 9))
                                      (at 9))
                              (at 9))
                            (state-from 7))))))))
   (else)))
