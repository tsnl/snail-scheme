;; What an operation's type says, and what an effect's defaults may
;; implement, as the old compiler's `declare-operation-type`,
;; `snail-default` and `effect-defaults` (src/snail/shell/compiler/
;; expand.sld) check them. An operation is a function, whose arrow's effects
;; are a closed row, its latent effects, which its implementations may
;; perform where it is performed. Its own effect is implied, never written,
;; and it may not be latent too. A handler implements an operation once, at
;; one type, so the type quantifies nothing: an implementation checked at
;; one instance would serve callers at others, and a row variable would let
;; it perform what no caller is charged. A control operation's
;; implementation runs where its handler is, after the body has unwound to
;; it, so its type is total, and it has no default, since no handler is in
;; scope where a default runs to be handed the rest of the computation. An
;; operation has at most one default. Its scheme is operational, so a
;; callable or code there is the arrow it holds.
(define-library (snail compiler declare operations)
  (export
   OperationType
   operation-type
   default-problem
   defaults-problem)
  (import
   (snail core base)
   (snail compiler declare language)
   (snail compiler types type)
   (snail compiler types scheme)
   (snail compiler types equality)
   (only (snail compiler names globals) Global same-global?))
  (begin

    ;; ---- Operations ----

    (struct OperationType
      ((parameters (List Type))
       (result Type)
       (latent (List Global))))

    ;; The parameters, result and latent effects of an operation of the
    ;; effect `effect` whose operational scheme is `scheme`, a control
    ;; operation when `control?`; or the old compiler's refusal, in its
    ;; order: a type that is no function with a closed row, then one that
    ;; quantifies, then a control operation's latent effects, then its own
    ;; effect among them.
    (: operation-type (impl (Fn Global Bool Scheme -> (Result OperationType String))))
    (define (operation-type effect control? scheme)
      (match (closed-function (::type scheme))
        ((Some found)
         (cond ((not (and (null? (::variables scheme)) (null? (::requirements scheme))))
                (Err
                 "an operation's type cannot be polymorphic: a handler implements it once, at one type"))
               ((and control? (not (null? (::latent found))))
                (Err "a control operation has a total function type; its effect is implied"))
               ((any? (lambda (label) (same-global? label effect)) (::latent found))
                (Err "an operation's latent row cannot name its own effect"))
               (else (Ok found))))
        ((None) (Err "an operation has a function type with a closed row; its effect is implied"))))

    ;; A function's parameters, result and effects, when its row is closed.
    (: closed-function (impl (Fn Type -> (Option OperationType))))
    (define (closed-function type)
      (match type
        ((Callable _ _ arrow)
         (match (::tail (::effects arrow))
           ((None)
            (Some
             (OperationType (::parameters arrow) (::result arrow) (::labels (::effects arrow)))))
           ((Some _) (None))))
        (_ (None))))

    ;; ---- Defaults ----

    ;; Whether `operation`, which a default names, may have one.
    (: default-problem (impl (Fn Operation -> (Option String))))
    (define (default-problem operation)
      (if (::control? operation)
          (Some "a control operation has no default")
          (None)))

    ;; `operations` are those an effect's defaults implement, one for each
    ;; default, in order: none twice.
    (: defaults-problem (impl (Fn (List Global) -> (Option String))))
    (define (defaults-problem operations)
      (if (= (length operations) (length (delete-duplicates same-global? operations)))
          (None)
          (Some "an operation has at most one default")))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-operations)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-operations)
        (test-types)
        (test-defaults))

      (define i64 (Con (Global (list "snail" "core" "forms") "I64" 0) (list)))
      (define gen (Global (list "main") "Gen" 0))
      (define log (Global (list "main") "log" 0))

      (define (function effects)
        (Callable (Dyn) (FnContract) (Arrow (list i64) i64 effects)))

      (define (mono effects)
        (Scheme (list) (list) (list) (function effects)))

      (define closed "an operation has a function type with a closed row; its effect is implied")
      (define polymorphic
        "an operation's type cannot be polymorphic: a handler implements it once, at one type")
      (define total "a control operation has a total function type; its effect is implied")

      ;; Read off error-effect-operation-polymorphic.sld, its -row.sld and
      ;; error-control-latent-ctl.sld, each refusal in the old order.
      (define (test-types)
        (expect (operation-type gen #f (mono (Effects (list log) (None))))
                (Ok (OperationType (list i64) i64 (list log))))
        (expect (operation-type gen #t (mono (Effects (list) (None))))
                (Ok (OperationType (list i64) i64 (list))))
        (expect (operation-type gen #f (mono (Effects (list) (Some (Var (Written "e"))))))
                (Err closed))
        (expect (operation-type gen #f (Scheme (list) (list) (list) i64)) (Err closed))
        ;; The shape before the variables, the variables before the rest.
        (expect (operation-type gen
                                #t
                                (Scheme (list (Written "a")) (list) (list) (Var (Written "a"))))
                (Err closed))
        (expect (operation-type gen
                                #t
                                (Scheme (list (Written "a"))
                                        (list)
                                        (list)
                                        (function (Effects (list gen) (None)))))
                (Err polymorphic))
        (expect (operation-type gen
                                #f
                                (Scheme (list)
                                        (list (CallableRequirement (FnContract)
                                                                   (Var (CallableArgument 0))
                                                                   (Arrow (list)
                                                                          i64
                                                                          (Effects (list) (None)))))
                                        (list)
                                        (function (Effects (list) (None)))))
                (Err polymorphic))
        (expect (operation-type gen #t (mono (Effects (list gen log) (None)))) (Err total))
        (expect (operation-type gen #f (mono (Effects (list gen log) (None))))
                (Err "an operation's latent row cannot name its own effect")))

      ;; Read off error-control-default.sld: a control operation has none;
      ;; and no operation two.
      (define (test-defaults)
        (let* ((loc (Loc "t.sld" 1 1))
               (operation (lambda (name control?)
                            (Operation (Global (list "main") name 0)
                                       control?
                                       (list)
                                       i64
                                       (list)
                                       (list)
                                       loc))))
          (expect (default-problem (operation "next" #t))
                  (Some "a control operation has no default"))
          (expect (default-problem (operation "read" #f)) (None))
          (expect (defaults-problem (list gen log)) (None))
          (expect (defaults-problem (list)) (None))
          (expect (defaults-problem (list gen log (Global (list "main") "Gen" 0)))
                  (Some "an operation has at most one default"))
          (expect (defaults-problem (list gen (Global (list "main") "Gen" 1))) (None))))))
   (else)))
