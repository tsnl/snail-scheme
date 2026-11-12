;; The numbers `dispatch` hands out: the next number no Global or local of
;; the library has, starting where the declared library's root says it
;; stopped. Each Global `dispatch` writes, a generated instance's and each
;; method implementation's, and each local of the lambdas it writes, takes
;; the next, so every number stays unique in the library.
(define-library (snail compiler dispatch state)
  (export
   Numbering
   numbering-let*
   numbering-map
   fresh-global
   fresh-local
   fresh-locals)
  (import
   (snail core base)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Global Local))
  (begin

    ;; ---- Numbers ----

    ;; The Globals are the library's, `library`.
    (struct Numbering
      ((library LibraryName)
       (next I64)))

    ;; A Global of the library no other has, named `name`.
    (: fresh-global (impl (Fn Numbering String -> (Pair Global Numbering))))
    (define (fresh-global state name)
      (Pair (Global (::library state) name (::next state))
            (Numbering (::library state) (+ (::next state) 1))))

    ;; A local no other of the library has, named `name`.
    (: fresh-local (impl (Fn Numbering String -> (Pair Local Numbering))))
    (define (fresh-local state name)
      (Pair (Local name (::next state)) (Numbering (::library state) (+ (::next state) 1))))

    ;; `count` such locals, in order.
    (: fresh-locals (impl (Fn Numbering String I64 -> (Pair (List Local) Numbering))))
    (define (fresh-locals state name count)
      (numbering-map state (lambda (state index) (fresh-local state name)) (iota count)))

    ;; ---- Sequencing ----

    ;; `(numbering-let* ((name state step) ...) body ...)` evaluates each
    ;; step in order, with the scope of `let*`. A step takes the state and
    ;; returns its value with the new state, as a Pair: each binding names
    ;; the value and the new state, which the steps after it and the body
    ;; see. Both names are the use's, the only ones stage 0's `match` binds.
    (define-syntax numbering-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Pair name state) (numbering-let* (more ...) body ...))))))

    ;; The value `step` makes of each item, in order, with the state each
    ;; step leaves handed to the next.
    (: numbering-map
       (All (A B Callback)
            (requires (Copy A)
                      (Copy B)
                      (Copy Callback)
                      (Fn Callback Numbering A -> (Pair B Numbering)))
            (impl (Fn Numbering Callback (List A) -> (Pair (List B) Numbering)))))
    (define (numbering-map state step items)
      (let loop ((state state)
                 (items items)
                 (mapped (Nil)))
        (match items
          ((Nil) (Pair (reverse mapped) state))
          ((Cons item rest)
           (numbering-let* ((value state (step state item)))
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
      ;; Globals and locals share the numbers, each once.
      (define (test-state)
        (let ((state (Numbering (list "main") 7)))
          (expect (numbering-let* ((implementation state (fresh-global state "show"))
                                   (parameters state (fresh-locals state "argument" 2))
                                   (selected state (fresh-local state "selected")))
                    (list implementation parameters selected (::next state)))
                  (list (Global (list "main") "show" 7)
                        (list (Local "argument" 8) (Local "argument" 9))
                        (Local "selected" 10)
                        11))))))
   (else)))
