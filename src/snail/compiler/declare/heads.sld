;; What an instance's head and equations give its class, as the old
;; compiler's `declared-instance` and `instance-outputs`
;; (src/snail/shell/compiler/expand.sld) check them: the equations give
;; each of the class's outputs exactly once, and a class with outputs has
;; its written parameters, and only those, in the head, since its outputs
;; belong in the instance's body. The equations are checked before any of
;; their types is converted, and the head's count once they are.
(define-library (snail compiler declare heads)
  (export
   equations-given-problem
   head-problem)
  (import
   (snail core base)
   (prefix (only (snail compiler expand language) Equation) expanded-)
   (snail compiler declare known))
  (begin

    ;; ---- Equations ----

    ;; As many equations as the class has outputs, no two naming the same
    ;; output, and each naming one of the class's.
    (: equations-given-problem
       (impl (Fn ClassShape (List expanded-Equation) -> (Option String))))
    (define (equations-given-problem shape equations)
      (let ((names (map (lambda (equation) (::name (::label equation))) equations)))
        (if (and (= (length names) (length (::outputs shape)))
                 (= (length names) (length (delete-duplicates string=? names)))
                 (every? (lambda (name) (member? name (::outputs shape))) names))
            (None)
            (Some "an instance defines each associated type exactly once"))))

    ;; ---- Heads ----

    ;; `count` is how many types the head writes.
    (: head-problem (impl (Fn ClassShape I64 -> (Option String))))
    (define (head-problem shape count)
      (if (and (not (null? (::outputs shape))) (not (= count (length (::parameters shape)))))
          (Some
           "instance head gives each declared class parameter; associated types belong in its body")
          (None)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-heads)
    (import
     (snail compiler source)
     (only (snail compiler expand language) Label)
     (prefix (only (snail compiler expand language) Variable) expanded-)
     (snail compiler declare language)
     (snail stage0 testing))
    (begin
      (define (test-heads)
        (test-equations)
        (test-counts))

      (define loc (Loc "t.sld" 1 1))

      (define (equation name)
        (expanded-Equation (Label name loc) (expanded-Variable "t" loc)))

      ;; (Op e A B) with the output Output; (Show a) with none.
      (define op
        (ClassShape "Op"
                    (list (RowParameter "e") (TypeParameter "A") (TypeParameter "B"))
                    (list "Output")))
      (define show (ClassShape "Show" (list (TypeParameter "a")) (list)))

      (define once "an instance defines each associated type exactly once")

      ;; Read off error-associated-duplicate.sld and -missing.sld.
      (define (test-equations)
        (expect (equations-given-problem op (list (equation "Output"))) (None))
        (expect (equations-given-problem op (list (equation "Output") (equation "Output")))
                (Some once))
        (expect (equations-given-problem op (list)) (Some once))
        (expect (equations-given-problem op (list (equation "Input"))) (Some once))
        (expect (equations-given-problem show (list)) (None)))

      ;; Only a class with outputs counts its head here.
      (define (test-counts)
        (expect (head-problem op 3) (None))
        (expect (head-problem op 4)
                (Some
                 "instance head gives each declared class parameter; associated types belong in its body"))
        (expect (head-problem show 2) (None)))))
   (else)))
