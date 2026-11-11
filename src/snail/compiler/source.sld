;; What every pass shares: where a piece of source is, what a pass says
;; about it, and how to sequence steps that can fail. A pass
;; returns its output or the feedback that stopped it, so every pass is a
;; function of its input.
(define-library (snail compiler source)
  (export
   Loc
   Feedback
   fail
   result-let*
   map-results)
  (import
   (snail core base))
  (begin

    ;; ---- Locations ----

    ;; Lines and columns count from 1, and a column counts Unicode scalars.
    ;; Line 0 is the file as a whole, for feedback about no one place in it.
    (struct Loc
      ((file String)
       (line I64)
       (column I64)))

    ;; ---- Feedback ----

    ;; What a pass says about a place in the source. A pass that fails
    ;; returns at least one.
    (struct Feedback
      ((loc Loc)
       (message String)))

    ;; The failure that says `message` about `loc`, and nothing else.
    (: fail (All (T) (impl (Fn Loc String -> (Result T (List Feedback))))))
    (define (fail loc message)
      (Err (list (Feedback loc message))))

    ;; ---- Sequencing ----

    ;; `(result-let* ((name step) ...) body ...)` evaluates each step in
    ;; order, with the scope of `let*`, while each returns `(Ok value)`,
    ;; binding `name` to the value. The first `(Err failure)` is the value
    ;; of the whole form, and nothing after it runs; otherwise the body's
    ;; value is, and the body returns a Result as well.
    ;;
    ;; The `Err` clause binds the failure to `name` too. Stage 0's `match`
    ;; (host/chibi/snail/stage0/forms.sld) binds only the pattern variables
    ;; a macro's use wrote, not ones its template introduces, so `name` is
    ;; the one variable this form can bind there. A step's name is
    ;; therefore an identifier, never `_`.
    (define-syntax result-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name step) more ...) body ...)
         (match step
           ((Ok name) (result-let* (more ...) body ...))
           ((Err name) (Err name))))))

    ;; The value `step` makes of each item, in order, while each is
    ;; `(Ok value)`. The first failure is the answer, and no item after it
    ;; is stepped.
    (: map-results
       (All (A B Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback A -> (Result B (List Feedback))))
            (impl (Fn Callback (List A) -> (Result (List B) (List Feedback))))))
    (define (map-results step items)
      (let loop ((items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Ok (reverse mapped)))
          ((Cons item rest)
           (result-let* ((value (step item)))
             (loop rest (Cons value mapped)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-source)
    (import
     (snail stage0 testing))
    (begin
      (define (test-source)
        (test-fail)
        (test-result-let*)
        (test-map-results))

      (define (test-fail)
        (expect (fail (Loc "t.sld" 2 3) "a message")
                (Err (list (Feedback (Loc "t.sld" 2 3) "a message")))))

      ;; Each step sees the names before it, and the first failure is the
      ;; answer: no step after it runs, nor the body.
      (define (test-result-let*)
        (expect (result-let* () (Ok 1)) (Ok 1))
        (expect (result-let* ((a (Ok 1))
                              (b (Ok (+ a 1))))
                  (Ok (list a b)))
                (Ok (list 1 2)))
        (expect (result-let* ((a (Ok 1))
                              (b (fail (Loc "t.sld" 1 a) "first"))
                              (c (panic "a step after a failure ran")))
                  (panic "the body ran after a failure"))
                (fail (Loc "t.sld" 1 1) "first"))
        (expect (result-let* ((a (Err "any failure")))
                  (Ok a))
                (Err "any failure")))

      ;; Items are stepped in order, and none after the first failure.
      (define (test-map-results)
        (define (halved number)
          (cond ((= number 0) (panic "an item after a failure was stepped"))
                ((= (remainder number 2) 0) (Ok (quotient number 2)))
                (else (fail (Loc "t.sld" 1 number) "odd"))))
        (expect (map-results halved (list)) (Ok (list)))
        (expect (map-results halved (list 4 2 8)) (Ok (list 2 1 4)))
        (expect (map-results halved (list 2 3 5 0)) (fail (Loc "t.sld" 1 3) "odd")))))
   (else)))
