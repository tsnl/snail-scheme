;; The state `bind` threads: the next number no local or serial of the
;; library has, and, while a copy of an expression is bound, the locals
;; the copy has renamed so far. Outside a copy every local keeps its
;; number. In a copy, each local the expression binds is a new one,
;; numbered from the state, and each reference to it names the new one; a
;; local bound around the copy keeps its number. Locals are unique in a
;; library, so a copy's renaming is one list, never shadowed.
(define-library (snail compiler bind state)
  (export
   Numbering
   numbering-from
   numbering-let*
   numbering-map
   binder
   binders
   reference
   copying
   copy-done)
  (import
   (snail core base)
   (only (snail compiler expand language) Local))
  (begin

    ;; ---- Numbers ----

    ;; `renamed` is None outside a copy.
    (struct Numbering
      ((next I64)
       (renamed (Option (List Renamed)))))

    ;; A local the copied expression binds, by its number, and the local
    ;; the copy binds in its place.
    (struct Renamed
      ((number I64)
       (copy Local)))

    ;; Numbering from `next`, outside any copy.
    (: numbering-from (impl (Fn I64 -> Numbering)))
    (define (numbering-from next)
      (Numbering next (None)))

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

    ;; ---- Locals ----

    ;; The local a binder binds: its own outside a copy, and in a copy a
    ;; new one, which the references inside the copy then name.
    (: binder (impl (Fn Numbering Local -> (Pair Local Numbering))))
    (define (binder state local)
      (match (::renamed state)
        ((None) (Pair local state))
        ((Some renamed)
         (let ((copy (Local (::name local) (::next state))))
           (Pair copy
                 (Numbering (+ (::next state) 1)
                            (Some (Cons (Renamed (::number local) copy) renamed))))))))

    (: binders (impl (Fn Numbering (List Local) -> (Pair (List Local) Numbering))))
    (define (binders state locals)
      (numbering-map state binder locals))

    ;; The local a reference names: the copy's, when the copy being bound
    ;; renamed it.
    (: reference (impl (Fn Numbering Local -> Local)))
    (define (reference state local)
      (match (::renamed state)
        ((None) local)
        ((Some renamed)
         (match (find (lambda (entry) (= (::number entry) (::number local))) renamed)
           ((Some entry) (::copy entry))
           ((None) local)))))

    ;; ---- Copies ----

    ;; The state to bind a copy in. A copy made inside a copy renames on
    ;; top of the renaming around it, so a reference to a local the outer
    ;; copy renamed names the outer copy's.
    (: copying (impl (Fn Numbering -> Numbering)))
    (define (copying state)
      (match (::renamed state)
        ((Some _) state)
        ((None) (Numbering (::next state) (Some (Nil))))))

    ;; The state after a copy bound in `inner`, made from `outer`: the
    ;; numbers the copy used stay used, and the renaming is as it was.
    (: copy-done (impl (Fn Numbering Numbering -> Numbering)))
    (define (copy-done outer inner)
      (Numbering (::next inner) (::renamed outer)))

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
        (test-outside)
        (test-copy)
        (test-nested))

      (define (next-of state)
        (::next state))

      ;; Outside a copy, nothing is renamed or numbered.
      (define (test-outside)
        (let ((state (numbering-from 5)))
          (expect (binder state (Local "x" 2)) (Pair (Local "x" 2) state))
          (expect (reference state (Local "x" 2)) (Local "x" 2))
          (expect (numbering-let* ((a state (binder state (Local "a" 1)))
                                   (b state (binder state (Local "b" 2))))
                    (Pair (list a b) (next-of state)))
                  (Pair (list (Local "a" 1) (Local "b" 2)) 5))))

      ;; In a copy, each binder takes the next number, and references to it
      ;; follow; a local bound around the copy keeps its number. Once the
      ;; copy is done, the numbers stay used and nothing is renamed.
      (define (test-copy)
        (let ((outer (numbering-from 5)))
          (numbering-let* ((bound inner
                                  (binders (copying outer) (list (Local "a" 1) (Local "b" 2)))))
            (expect bound (list (Local "a" 5) (Local "b" 6)))
            (expect (reference inner (Local "b" 2)) (Local "b" 6))
            (expect (reference inner (Local "around" 0)) (Local "around" 0))
            (let ((after (copy-done outer inner)))
              (expect (next-of after) 7)
              (expect (reference after (Local "b" 2)) (Local "b" 2))
              (expect (binder after (Local "c" 3)) (Pair (Local "c" 3) after))))))

      ;; A copy inside a copy sees the outer copy's renaming and adds its
      ;; own; when it is done, the outer copy's renaming is as it was.
      (define (test-nested)
        (numbering-let* ((a outer (binder (copying (numbering-from 10)) (Local "a" 1)))
                         (b inner (binder (copying outer) (Local "b" 2))))
          (expect (list a b) (list (Local "a" 10) (Local "b" 11)))
          (expect (reference inner (Local "a" 1)) (Local "a" 10))
          (let ((after (copy-done outer inner)))
            (expect (reference after (Local "a" 1)) (Local "a" 10))
            (expect (reference after (Local "b" 2)) (Local "b" 2))
            (expect (next-of after) 12))))))
   (else)))
