;; Query: the members an instance of a class implements, each with its own
;; scheme, and the name a member goes by. A declared class's members are its
;; methods, as far as they are known where the instance is; a field class
;; `::label` has one, the reader of the field, whose own scheme is
;; `(Fn R -> T)`. `declare` names an instance's written methods by them, and
;; `dispatch` the methods it writes, so both name an implementation alike.
(define-library (snail compiler declare membership)
  (export
   member-schemes
   class-members
   member-name)
  (import
   (snail core base)
   (only (snail compiler expand language) ClassRef ClassGlobal FieldClass)
   (snail compiler declare language)
   (only (snail compiler declare schemes) field-reader-scheme))
  (begin

    ;; ---- Members ----

    ;; Each member of `class`, whose methods as known are `methods`, with
    ;; its own scheme, in the class's order.
    (: member-schemes (impl (Fn ClassRef (List Method) -> (List (Pair Member Scheme)))))
    (define (member-schemes class methods)
      (match class
        ((ClassGlobal _)
         (map (lambda (method) (Pair (ClassMethod (::global method)) (::scheme method))) methods))
        ((FieldClass label) (list (Pair (FieldReader label) field-reader-scheme)))))

    (: class-members (impl (Fn ClassRef (List Method) -> (List Member))))
    (define (class-members class methods)
      (map ::first (member-schemes class methods)))

    ;; The name a member goes by, in messages and in the Global of its
    ;; implementation: a method's own, or a field class's label.
    (: member-name (impl (Fn Member -> String)))
    (define (member-name member)
      (match member
        ((ClassMethod global) (::name global))
        ((FieldReader label) label)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-membership)
    (import
     (snail compiler source)
     (only (snail compiler expand language) Global)
     (only (snail compiler declare forms) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-membership)
        (let* ((loc (Loc "t.sld" 1 1))
               (unit-type (Con (Global forms-library "Unit" 0) (list)))
               (own (Scheme (list) (list) (list) unit-type))
               (show (Method (Global (list "main") "show" 0) own (list) loc)))
          (expect (member-schemes (ClassGlobal (Global (list "main") "Show" 0)) (list show))
                  (list (Pair (ClassMethod (Global (list "main") "show" 0)) own)))
          (expect (member-schemes (FieldClass "x") (list))
                  (list (Pair (FieldReader "x") field-reader-scheme)))
          (expect (class-members (FieldClass "x") (list show)) (list (FieldReader "x")))
          (expect (map member-name
                       (list (ClassMethod (Global (list "main") "show" 4)) (FieldReader "x")))
                  (list "show" "x"))))))
   (else)))
