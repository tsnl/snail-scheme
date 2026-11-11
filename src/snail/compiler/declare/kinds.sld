;; The kind of each of a class's written parameters: a row when a method's
;; type ends a row with it, as `e` in `(: fetch-object (impl (Fn S String
;; -> String ! e)))`, and a type otherwise, as the old compiler's
;; `class-rows` (src/snail/shell/compiler/expand.sld) finds a row's kind
;; from its use. It looks at each method's own type, operational already,
;; and not at its requirements, so a row written only in the arrow of an
;; `impl` parameter, which becomes a callable requirement, makes no row.
(define-library (snail compiler declare kinds)
  (export
   class-parameters
   row-names)
  (import
   (snail core base)
   (snail compiler declare language))
  (begin

    ;; ---- Parameters ----

    ;; Each of `parameters` with its kind, in order, given the types of the
    ;; class's methods.
    (: class-parameters (impl (Fn (List String) (List Type) -> (List ClassParameter))))
    (define (class-parameters parameters types)
      (let ((rows (concatenate (map row-names types))))
        (map (lambda (name) (if (member? name rows) (RowParameter name) (TypeParameter name)))
             parameters)))

    ;; ---- Rows ----

    ;; The variables a type ends a row with: a function's effects, and a
    ;; row as a type argument, followed through a tail that is a row
    ;; itself, as an alias's argument may write it.
    (: row-names (impl (Fn Type -> (List String))))
    (define (row-names type)
      (match type
        ((Callable _ _ arrow) (arrow-row-names arrow))
        ((Code arrow) (arrow-row-names arrow))
        ((Con _ arguments) (concatenate (map row-names arguments)))
        ((Row effects) (effects-row-names effects))
        ((Var _) (Nil))))

    (: arrow-row-names (impl (Fn Arrow -> (List String))))
    (define (arrow-row-names arrow)
      (append (concatenate (map row-names (::parameters arrow)))
              (append (row-names (::result arrow)) (effects-row-names (::effects arrow)))))

    (: effects-row-names (impl (Fn Effects -> (List String))))
    (define (effects-row-names effects)
      (match (::tail effects)
        ((Some (Var (Written name))) (list name))
        ((Some tail) (row-names tail))
        ((None) (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-kinds)
    (import
     (only (snail compiler expand language) Global Impl Dyn FnContract FnMutContract)
     (snail stage0 testing))
    (begin
      (define (test-kinds)
        (test-rows)
        (test-parameters))

      (define text-type (Con (Global (list "snail" "core" "forms") "String" 0) (list)))
      (define io (Global (list "main") "io" 0))

      (define (var name)
        (Var (Written name)))

      (define (ending tail)
        (Effects (list io) tail))

      (define (fetch parameter effects)
        (Callable (Dyn) (FnContract) (Arrow (list parameter text-type) text-type effects)))

      ;; A function's row, a row argument, a row a callable within holds,
      ;; and a row's tail written as a row; never a variable as a type.
      (define (test-rows)
        (expect (row-names (fetch (var "S") (ending (Some (var "e"))))) (list "e"))
        (expect (row-names (fetch (var "S") (ending (None)))) (list))
        (expect (row-names (Con io (list (Row (ending (Some (var "r")))) (var "S")))) (list "r"))
        (expect (row-names (Code (Arrow (list (Callable (Impl)
                                                        (FnMutContract)
                                                        (Arrow (list)
                                                               text-type
                                                               (ending (Some (var "a"))))))
                                        (var "b")
                                        (ending (Some (var "c"))))))
                (list "a" "c"))
        (expect (row-names (Row (ending (Some (Row (ending (Some (var "e")))))))) (list "e"))
        (expect (row-names (Row (ending (Some (Var (Associated 0 "Out")))))) (list)))

      ;; Written order, each parameter's kind from every method's type.
      (define (test-parameters)
        (expect (class-parameters (list "e" "S")
                                  (list (fetch (var "S") (ending (None)))
                                        (fetch (var "S") (ending (Some (var "e"))))))
                (list (RowParameter "e") (TypeParameter "S")))
        (expect (class-parameters (list "a") (list)) (list (TypeParameter "a"))))))
   (else)))
