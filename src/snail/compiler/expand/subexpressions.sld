;; Query: every expression of an expanded library, each before the
;; expressions inside it, in the order written: the values of its
;; definitions, statements, instance methods and effect defaults, and a
;; program's body.
(define-library (snail compiler expand subexpressions)
  (export
   library-expressions)
  (import
   (snail core base)
   (snail compiler expand language))
  (begin

    ;; ---- Libraries ----

    (: library-expressions (impl (Fn Expanded -> (List Expr))))
    (define (library-expressions expanded)
      (match expanded
        ((Defined _ tops _ _) (tops-expressions tops))
        ((Program tops body _)
         (append (tops-expressions tops)
                 (match body
                   ((Some expr) (expressions expr))
                   ((None) (Nil)))))))

    (: tops-expressions (impl (Fn (List Top) -> (List Expr))))
    (define (tops-expressions tops)
      (concatenate (map top-expressions tops)))

    (: top-expressions (impl (Fn Top -> (List Expr))))
    (define (top-expressions top)
      (match top
        ((Define _ value _) (expressions value))
        ((Statement expr) (expressions expr))
        ((TopInstance instance) (instance-expressions instance))
        ((InstanceSet _ members _) (concatenate (map member-expressions members)))
        ((InstanceScope _ tops _) (tops-expressions tops))
        ((Effect _ _ defaults _ _ _)
         (concatenate (map (lambda (default) (expressions (::value default))) defaults)))
        (_ (Nil))))

    (: member-expressions (impl (Fn SetMember -> (List Expr))))
    (define (member-expressions member)
      (match member
        ((SetInstance instance) (instance-expressions instance))
        ((DynamicInstances _ _ _) (Nil))))

    (: instance-expressions (impl (Fn Instance -> (List Expr))))
    (define (instance-expressions instance)
      (match (::body instance)
        ((Methods methods)
         (concatenate (map (lambda (method) (expressions (::value method))) methods)))
        ((Dispatch _ _) (Nil))))

    ;; ---- Expressions ----

    (: expressions (impl (Fn Expr -> (List Expr))))
    (define (expressions expr)
      (Cons expr (concatenate (map expressions (children expr)))))

    ;; The expressions directly inside `expr`, in the order written.
    (: children (impl (Fn Expr -> (List Expr))))
    (define (children expr)
      (match expr
        ((PathApply _ record _) (list record))
        ((Lambda _ body _) (list body))
        ((ClosedLambda _ body _) (list body))
        ((Call callee arguments _) (Cons callee arguments))
        ((If test consequent alternative _) (list test consequent alternative))
        ((Seq first rest _) (list first rest))
        ((Let _ _ value body _) (list value body))
        ((LocalSignature _ body _) (list body))
        ((Match scrutinee clauses _) (Cons scrutinee (map ::body clauses)))
        ((Handle _ implementations body _)
         (append (map ::value implementations) (list body)))
        ((WithInstances _ body _) (list body))
        ((Ann value _ _) (list value))
        ((Convert value _ _) (list value))
        ((TryConvert value _ _) (list value))
        ((TypeTest value _ _) (list value))
        ((ArtifactFiles _ file prepend empty _) (list file prepend empty))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-subexpressions)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-subexpressions)
        (expect (length (library-expressions library)) 12)
        (expect (match (library-expressions library)
                  ((Cons (Lambda _ _ _) (Cons (Call _ _ _) (Cons (ArtifactFiles _ _ _ _ _) _))) #t)
                  (_ #f))
                #t))

      (define loc (Loc "t.sld" 1 1))

      (define a (list "a"))

      (define (global name)
        (Global a name 0))


      (define link (LinkedFile (list "data" "x.bin") (Loc "a/t.sld" 2 3) loc))

      (define files
        (ArtifactFiles "site"
                       (TopRef (TopGlobal (global "f")) loc)
                       link
                       (Literal (UnitValue) loc)
                       loc))

      ;; A library whose definition links a file inside a request for the
      ;; files of "site", twice, and whose program body asks again.
      (define library
        (Defined a
          (list (Define (global "x") (Lambda (list) (Call files (list files) loc) loc) loc)
                (InstanceScope (list)
                               (list
                                (Statement (Call (TopRef (TopGlobal (global "g")) loc) (list) loc)))
                               loc))
          1
          loc))
      ))
   (else)))
