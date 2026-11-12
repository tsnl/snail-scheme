;; Effects: an effect becomes its Effect, as the old compiler's
;; `declare-effect` (src/snail/shell/compiler/expand.sld) declares it.
;; Each operation's scheme is converted in order, where no requirement is
;; in scope, and is executable code's; an operation is then its type's
;; parameters, result and latent effects, without its own effect, or its
;; type is refused at the type. Then each default entry, in order, names an
;; operation of the effect, refused at its label, which may have a default,
;; refused at the entry, and its implementation is given a Global of its
;; own, named for the operation. Then no operation has two defaults,
;; refused at the effect. The first problem stops the declaration, in that
;; order (`declare-effect`). A default's value is a body,
;; declared with the library's other bodies, once every declaration is
;; reached: a lambda, as written, or a function's name, which becomes the
;; lambda that calls it with the operation's arguments, each a local of
;; its own, as the old compiler's `eta-expand` writes it. What is known
;; where the effect is is read, and only the numbering is threaded.
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
   (only (snail compiler names globals) Global)
   (prefix (snail compiler bind language) bound-)
   (snail compiler declare language)
   (snail compiler types type)
   (snail compiler declare known)
   (only (snail compiler names numbering) Numbering fresh-global fresh-locals)
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
       (implementation Global)
       (value bound-Expr)
       (loc Loc)))

    (: declared-effect
       (impl (Fn Numbering
                 Known
                 Signatures
                 Global
                 (List expanded-Operation)
                 (List bound-Default)
                 Bool
                 (List expanded-Annotation)
                 Loc
                 ->
                 (Result (Pair DeclaredEffect Numbering) (List Feedback)))))
    (define (declared-effect numbering
                             known
                             signatures
                             global
                             operations
                             defaults
                             around-main?
                             annotations
                             loc)
      (result-state-let* ((declared numbering
                                    (unchanged numbering
                                               (map-results (lambda (operation)
                                                              (declared-operation known
                                                                                  signatures
                                                                                  global
                                                                                  operation))
                                                            operations)))
                          (pending numbering
                                   (map-results-with-state numbering
                                                           (lambda (numbering default)
                                                             (pending-default numbering
                                                                              declared
                                                                              default))
                                                           defaults))
                          (once numbering
                                (unchanged numbering
                                           (checked (defaults-problem
                                                      (map (lambda (default)
                                                             (::global (::operation default)))
                                                           pending))
                                                    loc))))
        (Ok
         (Pair (DeclaredEffect (Effect global declared (Nil) around-main? annotations loc) pending)
               numbering))))

    ;; ---- Operations ----

    ;; What the type of an operation of the effect `effect` says, refused
    ;; at the type.
    (: declared-operation
       (impl (Fn Known
                 Signatures
                 Global
                 expanded-Operation
                 ->
                 (Result Operation (List Feedback)))))
    (define (declared-operation known signatures effect operation)
      (let ((written (::scheme operation)))
        (result-let* ((scheme (declared-scheme (Scope known (Nil)) written)))
          (match (operation-type effect (::control? operation) (operational-scheme scheme))
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

    ;; A default's operation, refused at the label that names it, or, when
    ;; the operation may have no default, at the entry; and its
    ;; implementation's Global.
    (: pending-default
       (impl (Fn Numbering
                 (List Operation)
                 bound-Default
                 ->
                 (Result (Pair PendingDefault Numbering) (List Feedback)))))
    (define (pending-default numbering operations default)
      (let ((label (::label default))
            (loc (::loc default)))
        (match (named-operation operations (::name label))
          ((Ok operation)
           (result-state-let* ((allowed numbering
                                        (unchanged numbering
                                                   (checked (default-problem operation) loc)))
                               (implementation numbering
                                               (Ok (fresh-global numbering
                                                                 (::name (::global operation))))))
             (Ok (Pair (PendingDefault operation implementation (::value default) loc)
                       numbering))))
          ((Err message) (fail (::loc label) message)))))

    ;; ---- Default bodies ----

    (: declared-default
       (impl (Fn Numbering Known PendingDefault
                 -> (Result (Pair Default Numbering) (List Feedback)))))
    (define (declared-default numbering known pending)
      (let ((operation (::operation pending))
            (loc (::loc pending)))
        (result-let* ((value (declared-expr known (::value pending))))
          (state-let* ((function numbering
                                 (default-function numbering
                                   value
                                   (length (::parameters operation))
                                   loc)))
            (Ok (Pair (Default (::global operation) (::implementation pending) function loc)
                      numbering))))))

    ;; `expand` leaves a default a Lambda, a ClosedLambda or a name.
    (: default-function (impl (Fn Numbering Expr I64 Loc -> (Pair Expr Numbering))))
    (define (default-function numbering value arity loc)
      (match value
        ((LocalRef _ _) (calling numbering value arity loc))
        ((TopRef _ _) (calling numbering value arity loc))
        (_ (Pair value numbering))))

    ;; `(lambda (argument ...) (function argument ...))`, at the entry.
    (: calling (impl (Fn Numbering Expr I64 Loc -> (Pair Expr Numbering))))
    (define (calling numbering function arity loc)
      (state-let* ((arguments numbering (fresh-locals numbering "argument" arity)))
        (Pair (Lambda arguments
                      (Call function
                            (map (lambda (argument) (LocalRef argument loc)) arguments)
                            loc)
                      loc)
              numbering)))

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
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler names globals) Local TopGlobal Label)
     (only (snail compiler literals constant) UnitValue)
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
        (Global main name 0))

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
        (expanded-Applied (Global forms-library "I64" 0) "I64" (list) (at line)))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define log (global "log"))

      (define (operation name control? type line)
        (expanded-Operation (global name)
                            control?
                            (expanded-Scheme (list) (list) type (at line))
                            (list)
                            (at line)))

      (define (function parameters effects)
        (expanded-Callable (Impl)
                           (FnContract)
                           (expanded-Arrow parameters (i64-at 1) effects)
                           loc))

      (define read-op
        (operation "read" #f (function (list) (expanded-Effects (list log) (None))) 2))
      (define jump-op
        (operation "jump" #t (function (list (i64-at 1)) (expanded-Effects (list) (None))) 3))
      (define send-op
        (operation "send" #f (function (list (i64-at 1)) (expanded-Effects (list) (None))) 3))

      (define (numbered next)
        (Numbering main next))

      (define (unit-at line)
        (bound-Literal (UnitValue) (at line)))

      (define (default name line)
        (bound-Default (Label name (at line)) (unit-at line) (at line)))

      (define declared-read (Operation (global "read") #f (list) i64 (list log) (list) (at 2)))
      (define declared-jump (Operation (global "jump") #t (list i64) i64 (list) (list) (at 3)))
      (define declared-send (Operation (global "send") #f (list i64) i64 (list) (list) (at 3)))

      ;; An operation is its type's parameters, result and latent effects;
      ;; a type that is no function with a closed row is refused at it.
      (define (test-operations)
        (expect (declared-effect (numbered 4)
                                 known
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
                          (numbered 4))))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op (operation "bad" #f (i64-at 5) 5))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 5)
                      "an operation has a function type with a closed row; its effect is implied"))
        (expect (declared-effect (numbered 4)
                                 known
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
                      "an operation has a function type with a closed row; its effect is implied"))
        ;; The rest of the operation's rules, each at the type, the first
        ;; operation's problem before the second's.
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list (expanded-Operation (global "pick")
                                                           #f
                                                           (expanded-Scheme
                                                            (list "A")
                                                            (list)
                                                            (function (list)
                                                                      (expanded-Effects (list)
                                                                                        (None)))
                                                            (at 10))
                                                           (list)
                                                           (at 10))
                                       (operation "own"
                                                  #f
                                                  (function (list)
                                                            (expanded-Effects (list (global "io"))
                                                                              (None)))
                                                  11))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 10)
                      "an operation's type cannot be polymorphic: a handler implements it once, at one type"))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op
                                       (operation "own"
                                                  #f
                                                  (function (list)
                                                            (expanded-Effects (list (global "io"))
                                                                              (None)))
                                                  11))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 11) "an operation's latent row cannot name its own effect"))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "Gen")
                                 (list (operation "yield"
                                                  #t
                                                  (function (list)
                                                            (expanded-Effects (list log) (None)))
                                                  12))
                                 (list)
                                 #f
                                 (list)
                                 loc)
                (fail (at 12)
                      "a control operation has a total function type; its effect is implied")))

      ;; Each default names an operation, refused at its label, and takes
      ;; the next number for its implementation, named for the operation.
      (define (test-defaults)
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op send-op)
                                 (list (default "read" 7) (default "send" 8))
                                 #f
                                 (list)
                                 loc)
                (Ok (Pair (DeclaredEffect (Effect (global "io")
                                                  (list declared-read declared-send)
                                                  (list)
                                                  #f
                                                  (list)
                                                  loc)
                                          (list (PendingDefault declared-read
                                                                (Global main "read" 4)
                                                                (unit-at 7)
                                                                (at 7))
                                                (PendingDefault declared-send
                                                                (Global main "send" 5)
                                                                (unit-at 8)
                                                                (at 8))))
                          (numbered 6))))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op)
                                 (list (default "read" 7) (default "write" 9))
                                 #f
                                 (list)
                                 loc)
                (fail (at 9) "not an operation of this effect: write"))
        ;; A control operation's default is refused at its entry, after
        ;; its label names it (error-control-default.sld); an entry with
        ;; no operation before it is refused first.
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list (bound-Default (Label "jump" (at 7))
                                                      (unit-at 8)
                                                      (at 8))
                                       (default "write" 9))
                                 #f
                                 (list)
                                 loc)
                (fail (at 8) "a control operation has no default"))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list (default "write" 9) (default "jump" 8))
                                 #f
                                 (list)
                                 loc)
                (fail (at 9) "not an operation of this effect: write"))
        ;; Two defaults of one operation are refused at the effect, once
        ;; every entry is read.
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list (default "read" 7) (default "read" 8) (default "write" 9))
                                 #f
                                 (list)
                                 (at 6))
                (fail (at 9) "not an operation of this effect: write"))
        (expect (declared-effect (numbered 4)
                                 known
                                 no-signatures
                                 (global "io")
                                 (list read-op jump-op)
                                 (list (default "read" 7) (default "read" 8))
                                 #f
                                 (list)
                                 (at 6))
                (fail (at 6) "an operation has at most one default")))

      ;; A lambda stays as written; a name is called with a local of its
      ;; own for each of the operation's parameters, numbered in turn.
      (define (test-default-bodies)
        (let ((lambda-value (bound-Lambda (list) (unit-at 7) (at 7)))
              (name (bound-TopRef (TopGlobal (global "send-twice")) (at 8))))
          (expect (declared-default (numbered 6)
                                    known
                                    (PendingDefault declared-read
                                                    (Global main "read" 4)
                                                    lambda-value
                                                    (at 7)))
                  (Ok (Pair (Default (global "read")
                              (Global main "read" 4)
                              (Lambda (list) (Literal (UnitValue) (at 7)) (at 7))
                              (at 7))
                            (numbered 6))))
          (expect (declared-default (numbered 6)
                                    known
                                    (PendingDefault declared-send
                                                    (Global main "send" 5)
                                                    name
                                                    (at 9)))
                  (Ok (Pair (Default (global "send")
                              (Global main "send" 5)
                              (Lambda (list (Local "argument" 6))
                                      (Call
                                       (TopRef (TopGlobal (global "send-twice")) (at 8))
                                       (list (LocalRef (Local "argument" 6) (at 9)))
                                       (at 9))
                                      (at 9))
                              (at 9))
                            (numbered 7))))))))
   (else)))
