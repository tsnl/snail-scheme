;; The state `declare` threads through a library's declarations and
;; bodies: the next number no Global or local of the library has, and what
;; is known of types, classes and effects there. The numbers start where
;; the derived library's root says it stopped, and name each Global
;; `declare` writes, an instance's, a method implementation's and a
;; default's, and each local of the lambda a default written as a name
;; becomes. What is known grows as each declaration is reached: in the old
;; compiler a declaration sees only those before it, so the pass reaches
;; them in order and each part is handed what is known then. Nothing else
;; changes as the pass goes: the signatures, read before any declaration,
;; are handed to each step that needs them.
(define-library (snail compiler declare state)
  (export
   Declaring
   declaring-let*
   declaring-map
   checked
   unchanged
   fresh-global
   fresh-local
   with-known)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler expand language) Global Local)
   (snail compiler declare known))
  (begin

    ;; ---- State ----

    (struct Declaring
      ((next I64)
       (known Known)))

    ;; A Global of the library no other has: named `name`, as the entity it
    ;; implements or stands for is, with a serial of its own.
    (: fresh-global
       (impl (Fn Declaring String -> (Result (Pair Global Declaring) (List Feedback)))))
    (define (fresh-global state name)
      (Ok (Pair (Global (::library (::known state)) name (::next state))
                (Declaring (+ (::next state) 1) (::known state)))))

    ;; A local no other of the library has, named `name`.
    (: fresh-local (impl (Fn Declaring String -> (Result (Pair Local Declaring) (List Feedback)))))
    (define (fresh-local state name)
      (Ok (Pair (Local name (::next state)) (Declaring (+ (::next state) 1) (::known state)))))

    ;; The state once a declaration is reached, which `known` now knows.
    (: with-known (impl (Fn Declaring Known -> Declaring)))
    (define (with-known state known)
      (Declaring (::next state) known))

    ;; ---- Sequencing ----

    ;; `(declaring-let* ((name state step) ...) body ...)` sequences steps
    ;; that take the state and return their value with the new state, as
    ;; `expanding-let*` does: each binding names the value and the new
    ;; state, which the steps after it and the body see, and the first
    ;; failure is the value of the whole form. The `Err` clause binds the
    ;; failure to `name`, the one variable stage 0 lets this form bind, so a
    ;; step is always named.
    (define-syntax declaring-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Ok (Pair name state)) (declaring-let* (more ...) body ...))
           ((Err name) (Err name))))))

    ;; A rule's answer as a step: the problem it found, placed at `loc`, or
    ;; none, which lets the steps after it run.
    (: checked (impl (Fn (Option String) Loc -> (Result Unit (List Feedback)))))
    (define (checked problem loc)
      (match problem
        ((Some message) (fail loc message))
        ((None) (Ok (unit)))))

    ;; A step of `declaring-let*` that leaves the state as it is.
    (: unchanged
       (All (T)
            (impl (Fn Declaring
                      (Result T (List Feedback))
                      ->
                      (Result (Pair T Declaring) (List Feedback))))))
    (define (unchanged state result)
      (result-let* ((value result))
        (Ok (Pair value state))))

    ;; The value `step` makes of each item, in order, with the state each
    ;; step leaves handed to the next, while each succeeds.
    (: declaring-map
       (All (A B Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback Declaring A -> (Result (Pair B Declaring) (List Feedback))))
            (impl (Fn Declaring
                      Callback
                      (List A)
                      ->
                      (Result (Pair (List B) Declaring) (List Feedback))))))
    (define (declaring-map state step items)
      (let loop ((state state)
                 (items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Ok (Pair (reverse mapped) state)))
          ((Cons item rest)
           (declaring-let* ((value state (step state item)))
             (loop state rest (Cons value mapped)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-state)
    (import
     (snail core table)
     (snail compiler declare offer)
     (snail stage0 testing))
    (begin
      (define (test-state)
        (test-fresh)
        (test-sequencing))

      (define main (list "main"))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main empty-table empty-table empty-table)
               (list)))

      ;; Globals and locals share the numbers, each once.
      (define (test-fresh)
        (let ((state (Declaring 7 known)))
          (expect (declaring-let* ((instance state (fresh-global state "Show"))
                                   (local state (fresh-local state "argument")))
                    (Ok (list instance local (::next state))))
                  (Ok (list (Global main "Show" 7) (Local "argument" 8) 9)))))

      (define (odd state number)
        (if (= (remainder number 2) 1)
            (Ok (Pair number state))
            (fail (Loc "t.sld" 1 number) "even")))

      ;; Each step sees the state the one before left; the first failure
      ;; ends the form and the map.
      (define (test-sequencing)
        (let ((state (Declaring 1 known)))
          (expect (declaring-let* ((a state (fresh-global state "a"))
                                   (b state (odd state 4))
                                   (c state (panic "a step after a failure ran")))
                    (panic "the body ran after a failure"))
                  (fail (Loc "t.sld" 1 4) "even"))
          (expect (declaring-let* ((a state (unchanged state (Ok 3))))
                    (Ok (Pair a (::next state))))
                  (Ok (Pair 3 1)))
          (expect (checked (None) (Loc "t.sld" 1 5)) (Ok (unit)))
          (expect (checked (Some "odd") (Loc "t.sld" 1 5)) (fail (Loc "t.sld" 1 5) "odd"))
          (expect (declaring-map state odd (list 1 3)) (Ok (Pair (list 1 3) state)))
          (expect (declaring-map state odd (list 1 2 4)) (fail (Loc "t.sld" 1 2) "even"))))))
   (else)))
