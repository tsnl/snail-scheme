;; What every pass shares: where a piece of source is, what a pass says
;; about it, how to sequence steps that can fail and steps that thread a
;; state, and the one hash that names things by their text. A pass
;; returns its output or the feedback that stopped it, so every pass is a
;; function of its input.
(define-library (snail compiler source)
  (export
   Loc
   beside
   Feedback
   fail
   result-let*
   map-results
   state-let*
   map-with-state
   result-state-let*
   map-results-with-state
   unchanged
   fnv-1a)
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

    ;; ---- Paths ----

    ;; The file `path` names when it is written in `file`, as an
    ;; `include-bytes` form and a `link-handle` form name theirs: a
    ;; relative path is in the directory that holds `file`, and an absolute
    ;; one is itself. A file named without a directory is in the current
    ;; one, so a relative path written there stays as written.
    (: beside (impl (Fn String String -> String)))
    (define (beside file path)
      (if (absolute? path)
          path
          (let ((chars (string->vector file)))
            (string-append (vector->string (subvector chars 0 (directory-end chars))) path))))

    (: absolute? (impl (Fn String -> Bool)))
    (define (absolute? path)
      (let ((chars (string->vector path)))
        (and (> (vector-length chars) 0) (char=? (vector-ref chars 0) #\/))))

    ;; The index just after the last `/` of a file's name, which ends the
    ;; name of its directory, or 0 when it has none.
    (: directory-end (impl (Fn (Vector Char) -> I64)))
    (define (directory-end chars)
      (let loop ((end (vector-length chars)))
        (cond ((= end 0) 0)
              ((char=? (vector-ref chars (- end 1)) #\/) end)
              (else (loop (- end 1))))))

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

    ;; ---- Threading a state ----

    ;; A pass that threads a state, such as the numbers it hands out,
    ;; writes each step to take the state first and return its value with
    ;; the new state, as `(Pair value state)`.
    ;;
    ;; `(state-let* ((name state step) ...) body ...)` evaluates each step
    ;; in order, with the scope of `let*`, binding `name` to its value and
    ;; `state` to the new state, which the steps after it and the body see.
    ;; Both names are the use's, the only ones stage 0's `match` binds.
    (define-syntax state-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Pair name state) (state-let* (more ...) body ...))))))

    ;; The value `step` makes of each item, in order, with the state each
    ;; step leaves handed to the next.
    (: map-with-state
       (All (A B S Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback S A -> (Pair B S)))
            (impl (Fn S Callback (List A) -> (Pair (List B) S)))))
    (define (map-with-state state step items)
      (let loop ((state state)
                 (items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Pair (reverse mapped) state))
          ((Cons item rest)
           (state-let* ((value state (step state item)))
             (loop state rest (Cons value mapped)))))))

    ;; `(result-state-let* ((name state step) ...) body ...)` is
    ;; `state-let*` for steps that can fail, each returning
    ;; `(Result (Pair value state) (List Feedback))`. The first failure is
    ;; the value of the whole form, and nothing after it runs; otherwise
    ;; the body's value is, and the body returns a Result as well. As in
    ;; `result-let*`, the `Err` clause binds the failure to `name`, so a
    ;; step is always named.
    (define-syntax result-state-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Ok (Pair name state)) (result-state-let* (more ...) body ...))
           ((Err name) (Err name))))))

    ;; The value `step` makes of each item, in order, with the state each
    ;; step leaves handed to the next, while each succeeds.
    (: map-results-with-state
       (All (A B S Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback S A -> (Result (Pair B S) (List Feedback))))
            (impl (Fn S Callback (List A) -> (Result (Pair (List B) S) (List Feedback))))))
    (define (map-results-with-state state step items)
      (let loop ((state state)
                 (items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Ok (Pair (reverse mapped) state)))
          ((Cons item rest)
           (result-state-let* ((value state (step state item)))
             (loop state rest (Cons value mapped)))))))

    ;; A step of `result-state-let*` that leaves the state as it is:
    ;; `result`'s value, or its failure, which drops the state, so the
    ;; state is one a step may copy.
    (: unchanged
       (All (T S)
            (requires (Copy S))
            (impl (Fn S (Result T (List Feedback)) -> (Result (Pair T S) (List Feedback))))))
    (define (unchanged state result)
      (result-let* ((value result))
        (Ok (Pair value state))))

    ;; ---- Hashes ----

    ;; FNV-1a over the code points, as an unsigned 32-bit value: a case's
    ;; TypeId hashes its schema, and a producer's key its program. Both
    ;; must be the old compiler's numbers, so this is its `fnv-1a`. The
    ;; product stays below 2^56, so it never overflows I64 on either host.
    (: fnv-1a (impl (Fn String -> I64)))
    (define (fnv-1a text)
      (fold-left (lambda (hash char)
                   (i64-and (* (i64-xor hash (char->integer char)) 16777619) 4294967295))
                 2166136261
                 (string->list text)))

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
        (test-beside)
        (test-fail)
        (test-result-let*)
        (test-map-results)
        (test-state-let*)
        (test-result-state-let*)
        (test-unchanged)
        (test-fnv-1a))

      (define (test-beside)
        (expect (beside "lib/sample/blob.sld" "data/blob.bin") "lib/sample/data/blob.bin")
        (expect (beside "/root/main.sld" "../x") "/root/../x")
        (expect (beside "dir/" "x") "dir/x")
        (expect (beside "main.sld" "data/x") "data/x")
        (expect (beside "" "x") "x")
        (expect (beside "lib/a.sld" "/abs/x") "/abs/x")
        (expect (beside "lib/a.sld" "") "lib/")
        (expect (beside "λ/é.sld" "😀") "λ/😀"))

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
        (expect (map-results halved (list 2 3 5 0)) (fail (Loc "t.sld" 1 3) "odd")))

      ;; A step whose state is a count: it pairs `item` with the count,
      ;; and counts one more.
      (define (counted count item)
        (Pair (Pair item count) (+ count 1)))

      ;; Each step sees the state the one before it left, and the body the
      ;; last one's; a map hands each item's state to the next.
      (define (test-state-let*)
        (expect (state-let* () 1) 1)
        (expect (state-let* ((a count (counted 5 "a"))
                             (b count (counted count "b")))
                  (list a b count))
                (list (Pair "a" 5) (Pair "b" 6) 7))
        (expect (map-with-state 5 counted (list "a" "b"))
                (Pair (list (Pair "a" 5) (Pair "b" 6)) 7))
        (expect (map-with-state 5 counted (list)) (Pair (list) 5)))

      ;; A step that can fail: an odd number, which leaves the count as it
      ;; is.
      (define (even count number)
        (if (= (remainder number 2) 0)
            (Ok (Pair number (+ count 1)))
            (fail (Loc "t.sld" 1 number) "odd")))

      ;; As `state-let*`, and the first failure is the answer: no step
      ;; after it runs, nor the body, nor a later item's step.
      (define (test-result-state-let*)
        (expect (result-state-let* () (Ok 1)) (Ok 1))
        (expect (result-state-let* ((a count (even 1 4))
                                    (b count (even count 6)))
                  (Ok (list a b count)))
                (Ok (list 4 6 3)))
        (expect (result-state-let* ((a count (even 1 4))
                                    (b count (even count 3))
                                    (c count (panic "a step after a failure ran")))
                  (panic "the body ran after a failure"))
                (fail (Loc "t.sld" 1 3) "odd"))
        (expect (map-results-with-state 0 even (list 2 4)) (Ok (Pair (list 2 4) 2)))
        (expect (map-results-with-state 0 even (list)) (Ok (Pair (list) 0)))
        (expect (map-results-with-state 0
                                        (lambda (count number)
                                          (if (= number 0)
                                              (panic "an item after a failure was stepped")
                                              (even count number)))
                                        (list 2 3 0))
                (fail (Loc "t.sld" 1 3) "odd")))

      ;; A step that leaves the state: the value with the state as it was,
      ;; or the failure.
      (define (test-unchanged)
        (expect (result-state-let* ((a count (unchanged 2 (Ok "a")))
                                    (b count (even count 4)))
                  (Ok (list a b count)))
                (Ok (list "a" 4 3)))
        (expect (unchanged 2 (fail (Loc "t.sld" 1 1) "no")) (fail (Loc "t.sld" 1 1) "no")))

      ;; The published FNV-1a values of "" and "a", and a code point past
      ;; a byte, which hashes as one step.
      (define (test-fnv-1a)
        (expect (fnv-1a "") 2166136261)
        (expect (fnv-1a "a") 3826002220)
        (expect (fnv-1a "λ")
                (i64-and (* (i64-xor 2166136261 955) 16777619) 4294967295)))))
   (else)))
