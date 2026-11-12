;; The state `bind` threads: the library's Numbering, (snail compiler names
;; numbering), and, while a copy of an expression is bound, the locals the
;; copy has renamed so far. Outside a copy every local keeps its number.
;; In a copy, each local the expression binds is a new one, numbered
;; afresh, and each reference to it names the new one; a local bound
;; around the copy keeps its number. Locals are unique in a library, so a
;; copy's renaming is one list, never shadowed.
(define-library (snail compiler bind state)
  (export
   Binding
   binding-from
   binder
   binders
   reference
   copying
   copy-done)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler names globals) Local)
   (only (snail compiler names numbering) Numbering fresh-local))
  (begin

    ;; ---- State ----

    ;; `renamed` is None outside a copy.
    (struct Binding
      ((numbering Numbering)
       (renamed (Option (List Renamed)))))

    ;; A local the copied expression binds, by its number, and the local
    ;; the copy binds in its place.
    (struct Renamed
      ((number I64)
       (copy Local)))

    ;; Binding with `numbering`, outside any copy.
    (: binding-from (impl (Fn Numbering -> Binding)))
    (define (binding-from numbering)
      (Binding numbering (None)))

    ;; ---- Locals ----

    ;; The local a binder binds: its own outside a copy, and in a copy a
    ;; new one, which the references inside the copy then name.
    (: binder (impl (Fn Binding Local -> (Pair Local Binding))))
    (define (binder state local)
      (match (::renamed state)
        ((None) (Pair local state))
        ((Some renamed)
         (state-let* ((copy numbering (fresh-local (::numbering state) (::name local))))
           (Pair copy (Binding numbering (Some (Cons (Renamed (::number local) copy) renamed))))))))

    (: binders (impl (Fn Binding (List Local) -> (Pair (List Local) Binding))))
    (define (binders state locals)
      (map-with-state state binder locals))

    ;; The local a reference names: the copy's, when the copy being bound
    ;; renamed it.
    (: reference (impl (Fn Binding Local -> Local)))
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
    (: copying (impl (Fn Binding -> Binding)))
    (define (copying state)
      (match (::renamed state)
        ((Some _) state)
        ((None) (Binding (::numbering state) (Some (Nil))))))

    ;; The state after a copy bound in `inner`, made from `outer`: the
    ;; numbers the copy used stay used, and the renaming is as it was.
    (: copy-done (impl (Fn Binding Binding -> Binding)))
    (define (copy-done outer inner)
      (Binding (::numbering inner) (::renamed outer)))

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

      (define (from next)
        (binding-from (Numbering (list "a") next)))

      (define (next-of state)
        (::next (::numbering state)))

      ;; Outside a copy, nothing is renamed or numbered.
      (define (test-outside)
        (let ((state (from 5)))
          (expect (binder state (Local "x" 2)) (Pair (Local "x" 2) state))
          (expect (reference state (Local "x" 2)) (Local "x" 2))
          (expect (state-let* ((a state (binder state (Local "a" 1)))
                               (b state (binder state (Local "b" 2))))
                    (Pair (list a b) (next-of state)))
                  (Pair (list (Local "a" 1) (Local "b" 2)) 5))))

      ;; In a copy, each binder takes the next number, and references to it
      ;; follow; a local bound around the copy keeps its number. Once the
      ;; copy is done, the numbers stay used and nothing is renamed.
      (define (test-copy)
        (let ((outer (from 5)))
          (state-let* ((bound inner (binders (copying outer) (list (Local "a" 1) (Local "b" 2)))))
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
        (state-let* ((a outer (binder (copying (from 10)) (Local "a" 1)))
                     (b inner (binder (copying outer) (Local "b" 2))))
          (expect (list a b) (list (Local "a" 10) (Local "b" 11)))
          (expect (reference inner (Local "a" 1)) (Local "a" 10))
          (let ((after (copy-done outer inner)))
            (expect (reference after (Local "a" 1)) (Local "a" 10))
            (expect (reference after (Local "b" 2)) (Local "b" 2))
            (expect (next-of after) 12))))))
   (else)))
