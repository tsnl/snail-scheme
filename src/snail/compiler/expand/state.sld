;; The state an expansion threads: the next number it gives a local, a
;; macro or a mark, so that each is unique in the library being expanded.
;; Nothing else about a library changes while its bodies expand: the
;; scopes a name resolves in are handed to each step, and a local macro's
;; home travels in the frames that bind it.
(define-library (snail compiler expand state)
  (export
   Expanding
   expanding-let*
   expanding-map
   unchanged
   fresh)
  (import
   (snail core base)
   (snail compiler source))
  (begin

    ;; ---- Numbers ----

    (struct Expanding
      ((next I64)))

    ;; A number no local, macro or mark of the library has yet.
    (: fresh (impl (Fn Expanding -> (Result (Pair I64 Expanding) (List Feedback)))))
    (define (fresh state)
      (Ok (Pair (::next state) (Expanding (+ (::next state) 1)))))

    ;; ---- Sequencing ----

    ;; `(expanding-let* ((name state step) ...) body ...)` sequences steps
    ;; as `result-let*` does, for steps that take the state and return
    ;; their value with the new state: each binding names the value and the
    ;; new state, which the steps after it and the body see. The first
    ;; failure is the value of the whole form, and the body returns a
    ;; Result as well. As with `result-let*`, the `Err` clause binds the
    ;; failure to `name`, the one variable stage 0 lets this form bind, so
    ;; a step is always named.
    (define-syntax expanding-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Ok (Pair name state)) (expanding-let* (more ...) body ...))
           ((Err name) (Err name))))))

    ;; A step that leaves the state as it is, for a step of
    ;; `expanding-let*` that hands out no number: `result`'s value.
    (: unchanged
       (All (T)
            (impl (Fn Expanding
                      (Result T (List Feedback))
                      ->
                      (Result (Pair T Expanding) (List Feedback))))))
    (define (unchanged state result)
      (result-let* ((value result))
        (Ok (Pair value state))))

    ;; The value `step` makes of each item, in order, with the state each
    ;; step leaves handed to the next, while each succeeds.
    (: expanding-map
       (All (A B Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback Expanding A -> (Result (Pair B Expanding) (List Feedback))))
            (impl (Fn Expanding
                      Callback
                      (List A)
                      ->
                      (Result (Pair (List B) Expanding) (List Feedback))))))
    (define (expanding-map state step items)
      (let loop ((state state)
                 (items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Ok (Pair (reverse mapped) state)))
          ((Cons item rest)
           (expanding-let* ((value state (step state item)))
             (loop state rest (Cons value mapped)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-state)
    (import
     (snail stage0 testing))
    (begin
      (define (test-state)
        (test-fresh)
        (test-sequencing)
        (test-unchanged)
        (test-mapping))

      (define (test-fresh)
        (expect (fresh (Expanding 4)) (Ok (Pair 4 (Expanding 5)))))

      (define (halved state number)
        (if (= (remainder number 2) 0)
            (Ok (Pair (quotient number 2) state))
            (fail (Loc "t.sld" 1 number) "odd")))

      ;; Each step sees the state the one before it left, and the first
      ;; failure ends the form.
      (define (test-sequencing)
        (expect (expanding-let* () (Ok 1)) (Ok 1))
        (let ((state (Expanding 1)))
          (expect (expanding-let* ((a state (fresh state))
                                   (b state (fresh state))
                                   (c state (halved state 8)))
                    (Ok (list a b c (::next state))))
                  (Ok (list 1 2 4 3)))
          (expect (expanding-let* ((a state (fresh state))
                                   (b state (halved state 3))
                                   (c state (panic "a step after a failure ran")))
                    (panic "the body ran after a failure"))
                  (fail (Loc "t.sld" 1 3) "odd"))))

      (define (test-unchanged)
        (let ((state (Expanding 2)))
          (expect (expanding-let* ((a state (unchanged state (Ok "a")))
                                   (b state (fresh state)))
                    (Ok (Pair a b)))
                  (Ok (Pair "a" 2))))
        (expect (unchanged (Expanding 2) (fail (Loc "t.sld" 1 1) "no"))
                (fail (Loc "t.sld" 1 1) "no")))

      (define (numbered state item)
        (expanding-let* ((number state (fresh state)))
          (Ok (Pair (Pair item number) state))))

      (define (test-mapping)
        (expect (expanding-map (Expanding 5) numbered (list "a" "b"))
                (Ok (Pair (list (Pair "a" 5) (Pair "b" 6)) (Expanding 7))))
        (expect (expanding-map (Expanding 5) numbered (list)) (Ok (Pair (list) (Expanding 5))))
        (expect (expanding-map (Expanding 0) halved (list 2 3 5))
                (fail (Loc "t.sld" 1 3) "odd")))))
   (else)))
