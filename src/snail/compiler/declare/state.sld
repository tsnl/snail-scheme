;; The state `declare` threads through a library's declarations and
;; bodies: the library's Numbering, (snail compiler names numbering), and
;; what is known of types, classes and effects there. The numbering starts
;; where the derived library's root says it stopped, and names each Global
;; `declare` writes, an instance's, a method implementation's and a
;; default's, and each local of the lambda a default written as a name
;; becomes. What is known grows as each declaration is reached: in the old
;; compiler a declaration sees only those before it, so the pass reaches
;; them in order and each part is handed what is known then, and threads
;; only the numbering. Nothing else changes as the pass goes: the
;; signatures, read before any declaration, are handed to each step that
;; needs them.
(define-library (snail compiler declare state)
  (export
   Declaring
   Declaring-numbering-set
   Declaring-known-set
   checked)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler names numbering) Numbering)
   (snail compiler declare known))
  (begin

    ;; ---- State ----

    (struct Declaring
      ((numbering Numbering)
       (known Known)))

    ;; ---- Rules ----

    ;; A rule's answer as a step: the problem it found, placed at `loc`, or
    ;; none, which lets the steps after it run.
    (: checked (impl (Fn (Option String) Loc -> (Result Unit (List Feedback)))))
    (define (checked problem loc)
      (match problem
        ((Some message) (fail loc message))
        ((None) (Ok (unit)))))

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
        (expect (checked (None) (Loc "t.sld" 1 5)) (Ok (unit)))
        (expect (checked (Some "odd") (Loc "t.sld" 1 5)) (fail (Loc "t.sld" 1 5) "odd")))))
   (else)))
