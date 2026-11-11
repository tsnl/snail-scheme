;; What an instance's head and equations give its class, as the old
;; compiler's `declared-instance`, `instance-outputs`, `instance-program`
;; and `check-head-rows` (src/snail/shell/compiler/expand.sld) check them:
;;
;; - The equations give each of the class's outputs exactly once, and a
;;   class with outputs has its written parameters, and only those, in the
;;   head, since its outputs belong in the instance's body. The equations
;;   are checked before any of their types is converted, and the head's
;;   count once they are.
;; - Once its methods are declared, the head and outputs give each of the
;;   class's parameters.
;; - The head writes a row, `(! label ...)`, for each parameter known to be
;;   a row, and for no other, since an instance is chosen from ground
;;   types, where no row variable could be solved. A drop's or a clone's
;;   row performs no control effect. Each row is closed, or ends with the
;;   row of the instance's requirements: for a lifecycle class, those
;;   `(lifecycle)` reads; for a class with rows, the rows its requirements
;;   of row classes are given as variables, which its own rows end with,
;;   each such variable once at least. The arguments are checked in the
;;   class's order, outputs last, each argument's labels as it is reached,
;;   and then the requirements.
;;
;; The class is as known where the instance is: the rows of a class of the
;; library's own declared after it are not known, so none is checked.
(define-library (snail compiler declare heads)
  (export
   equations-given-problem
   head-problem
   parameters-problem
   head-rows-problem)
  (import
   (snail core base)
   (prefix (only (snail compiler expand language) Equation) expanded-)
   (only (snail compiler expand language) Global)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality)
   (snail compiler declare kinds)
   (snail compiler declare lifecycle))
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

    ;; `count` is how many types the head and the outputs give.
    (: parameters-problem (impl (Fn ClassShape I64 -> (Option String))))
    (define (parameters-problem shape count)
      (if (= count (+ (length (::parameters shape)) (length (::outputs shape))))
          (None)
          (Some (string-append (instance-noun shape)
                               " gives each of the class's parameters, as in "
                               (written-class shape)))))

    ;; ---- Rows ----

    ;; `head` is the instance's types, then its outputs, one for each of
    ;; the class's parameters; `variables` and `requirements` are the
    ;; instance's, its requirements with evidence. Only a class with rows,
    ;; whose head then gives row arguments, has its rows checked against
    ;; the requirements.
    (: head-rows-problem
       (impl (Fn Known
                 (Option Lifecycle)
                 ClassShape
                 (List Type)
                 (List TypeVariable)
                 (List Requirement)
                 ->
                 (Option String))))
    (define (head-rows-problem known lifecycle shape head variables requirements)
      (match (arguments-problem known lifecycle shape head)
        ((Some message) (Some message))
        ((None)
         (match lifecycle
           ((Some found) (lifecycle-requirements-problem found shape head variables requirements))
           ((None)
            (if (null? (row-arguments shape head))
                (None)
                (row-requirements-problem known shape head requirements)))))))

    (: arguments-problem
       (impl (Fn Known (Option Lifecycle) ClassShape (List Type) -> (Option String))))
    (define (arguments-problem known lifecycle shape head)
      (let loop ((pairs
                  (zip (append (::parameters shape) (map TypeParameter (::outputs shape))) head)))
        (match pairs
          ((Nil) (None))
          ((Cons pair rest)
           (match (argument-problem known lifecycle shape (::first pair) (::second pair))
             ((Some message) (Some message))
             ((None) (loop rest)))))))

    ;; A row for a row parameter, its labels checked; a type for any other.
    (: argument-problem
       (impl (Fn Known (Option Lifecycle) ClassShape ClassParameter Type -> (Option String))))
    (define (argument-problem known lifecycle shape parameter type)
      (match (Pair parameter type)
        ((Pair (RowParameter _) (Row effects)) (labels-problem known lifecycle (::labels effects)))
        ((Pair (TypeParameter name) (Row _))
         (Some (string-append (instance-noun shape)
                              " gives its type parameter "
                              name
                              " a row, not a type")))
        ((Pair (RowParameter _) _) (Some (row-usage lifecycle shape)))
        ((Pair (TypeParameter _) _) (None))))

    ;; The first label a drop or a clone may not perform, in the row's
    ;; order; an instance of any other class may perform each.
    (: labels-problem (impl (Fn Known (Option Lifecycle) (List Global) -> (Option String))))
    (define (labels-problem known lifecycle labels)
      (match (Pair lifecycle labels)
        ((Pair (Some found) (Cons label rest))
         (match (control-problem known found label)
           ((Some message) (Some message))
           ((None) (labels-problem known lifecycle rest))))
        (_ (None))))

    ;; Each variable the instance's rows end with is one its requirements
    ;; give a row class's row, and each such variable is one its rows end
    ;; with.
    (: row-requirements-problem
       (impl (Fn Known ClassShape (List Type) (List Requirement) -> (Option String))))
    (define (row-requirements-problem known shape head requirements)
      (let ((tails (concatenate (map row-variable (row-arguments shape head))))
            (required (concatenate (map (lambda (requirement) (required-rows known requirement))
                                        requirements))))
        (if (and (every? (lambda (row) (variable-among? row tails)) required)
                 (every? (lambda (tail) (variable-among? tail required)) tails))
            (None)
            (Some (row-usage (None) shape)))))

    ;; The variables a requirement gives its class's row parameters, where
    ;; it gives a variable rather than a closed row.
    (: required-rows (impl (Fn Known Requirement -> (List TypeVariable))))
    (define (required-rows known requirement)
      (match requirement
        ((ClassRequirement class types)
         (concatenate (map (lambda (type)
                             (match type
                               ((Var variable) (list variable))
                               (_ (Nil))))
                           (row-arguments (class-shape known class) types))))
        ((CallableRequirement _ _ _) (Nil))))

    ;; The refusal of a row the head writes otherwise than its class's rows
    ;; ask.
    (: row-usage (impl (Fn (Option Lifecycle) ClassShape -> String)))
    (define (row-usage lifecycle shape)
      (match lifecycle
        ((Some _) (lifecycle-usage shape))
        ((None)
         (string-append (instance-noun shape)
                        "'s rows are closed, (! label ...), or end with the row e its"
                        " requirements give a row class, as (! label ... e) with (requires ("
                        (::name shape)
                        " e A))"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-heads)
    (import
     (snail core table)
     (snail compiler source)
     (only (snail compiler expand language) Label ClassGlobal FieldClass FnContract)
     (prefix (only (snail compiler expand language) Variable) expanded-)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-heads)
        (test-equations)
        (test-counts)
        (test-arguments)
        (test-row-requirements)
        (test-lifecycle-rows))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))

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

      ;; Only a class with outputs counts its head there; every class
      ;; counts its head and outputs once its methods are declared
      ;; (error-class-row-arity.sld).
      (define (test-counts)
        (expect (head-problem op 3) (None))
        (expect (head-problem op 4)
                (Some
                 "instance head gives each declared class parameter; associated types belong in its body"))
        (expect (head-problem show 2) (None))
        (expect (parameters-problem op 4) (None))
        (expect (parameters-problem show 1) (None))
        (expect (parameters-problem store 1)
                (Some "a Store instance gives each of the class's parameters, as in (Store e S)"))
        (expect (parameters-problem op 3)
                (Some
                 "a Op instance gives each of the class's parameters, as in (Op e A B Output)")))

      ;; (main)'s (Store e S), whose e is a row, and the effect Gen, with a
      ;; control operation; (main)'s Drop, standing for the base class.
      (define store (ClassShape "Store" (list (RowParameter "e") (TypeParameter "S")) (list)))
      (define drop-shape (ClassShape "Drop" (list (RowParameter "e") (TypeParameter "T")) (list)))
      (define store-global (Global main "Store" 0))
      (define gen (Global main "Gen" 0))
      (define io (Global main "io" 0))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main
                             empty-table
                             (by-name empty-table
                                      "Store"
                                      (Class store-global
                                             (::parameters store)
                                             (list)
                                             (list)
                                             (list)
                                             loc))
                             (by-name empty-table
                                      "Gen"
                                      (OfferedEffect gen
                                                     (list (Operation (Global main "next" 0)
                                                                      #t
                                                                      (list)
                                                                      (Con (Global forms-library
                                                                                   "Unit"
                                                                                   0)
                                                                           (list))
                                                                      (list)
                                                                      (list)
                                                                      loc)))))
               (list)))

      (define (var name)
        (Var (Written name)))

      (define (row labels tail)
        (Row (Effects labels tail)))

      (define loud (Con (Global main "Loud" 0) (list)))

      (define (store-of types)
        (ClassRequirement (ClassGlobal store-global) types))

      (define usage
        "a Store instance's rows are closed, (! label ...), or end with the row e its requirements give a row class, as (! label ... e) with (requires (Store e A))")

      (define (store-rows head requirements)
        (head-rows-problem known (None) store head (list (Written "e") (Written "A")) requirements))

      ;; Read off error-class-row-usage.sld: a row for each row parameter,
      ;; a type for every other, in the class's order; a drop's labels as
      ;; they are reached, an ordinary instance's never.
      (define (test-arguments)
        (expect (store-rows (list (row (list io) (None)) loud) (list)) (None))
        (expect (store-rows (list (row (list gen) (None)) loud) (list)) (None))
        (expect (store-rows (list (var "e") loud) (list)) (Some usage))
        (expect (store-rows (list loud (row (list) (None))) (list)) (Some usage))
        (expect (head-rows-problem known
                                   (None)
                                   show
                                   (list (row (list) (None)))
                                   (list)
                                   (list))
                (Some "a Show instance gives its type parameter a a row, not a type"))
        (expect (head-rows-problem known
                                   (None)
                                   op
                                   (list (row (list) (None)) loud loud (row (list) (None)))
                                   (list)
                                   (list))
                (Some "a Op instance gives its type parameter Output a row, not a type"))
        (expect (head-rows-problem known
                                   (Some (Dropping))
                                   drop-shape
                                   (list (row (list io gen) (None)) loud)
                                   (list)
                                   (list))
                (Some "a drop cannot perform the control effect Gen"))
        ;; A label of the row before a later argument's kind.
        (expect (head-rows-problem known
                                   (Some (Dropping))
                                   drop-shape
                                   (list (row (list gen) (None)) (row (list) (None)))
                                   (list)
                                   (list))
                (Some "a drop cannot perform the control effect Gen"))
        ;; The arguments before the requirements.
        (expect (head-rows-problem known
                                   (Some (Dropping))
                                   drop-shape
                                   (list (var "e") loud)
                                   (list)
                                   (list (ClassRequirement (ClassGlobal store-global) (list))))
                (Some
                 "a Drop instance's row is closed, (! label ...), or ends with the row e of its requirements (Drop e A), as (! label ... e)")))

      ;; Read off error-class-row-usage.sld: each row variable once among
      ;; the head's rows and the rows the requirements of row classes give.
      (define (test-row-requirements)
        (let ((ending (row (list io) (Some (var "e")))))
          (expect (store-rows (list ending loud) (list (store-of (list (var "e") (var "A")))))
                  (None))
          (expect (store-rows (list ending loud) (list)) (Some usage))
          (expect (store-rows (list ending loud) (list (store-of (list (var "f") (var "A")))))
                  (Some usage))
          (expect (store-rows (list (row (list) (None)) loud)
                              (list (store-of (list (var "e") (var "A")))))
                  (Some usage))
          (expect (store-rows (list (row (list) (None)) loud)
                              (list (store-of (list (row (list) (None)) (var "A")))))
                  (None))
          ;; A requirement of a class with no rows gives none.
          (expect (store-rows (list (row (list) (None)) loud)
                              (list (ClassRequirement (FieldClass "x") (list (var "e") (var "A")))
                                    (CallableRequirement (FnContract)
                                                         (var "e")
                                                         (Arrow (list)
                                                                loud
                                                                (Effects (list) (None))))))
                  (None))
          ;; A class with no rows has no such rule.
          (expect (head-rows-problem known
                                     (None)
                                     show
                                     (list loud)
                                     (list)
                                     (list (store-of (list (var "e") (var "A")))))
                  (None))))

      ;; A lifecycle instance's requirements, once its arguments pass.
      (define (test-lifecycle-rows)
        (expect (head-rows-problem known
                                   (Some (Dropping))
                                   drop-shape
                                   (list (row (list io) (Some (var "e"))) loud)
                                   (list (Written "e"))
                                   (list))
                (Some
                 "a Drop instance's row is closed, (! label ...), or ends with the row e of its requirements (Drop e A), as (! label ... e)"))
        (expect (head-rows-problem known
                                   (Some (Dropping))
                                   drop-shape
                                   (list (row (list io) (None)) loud)
                                   (list)
                                   (list))
                (None)))))
   (else)))
