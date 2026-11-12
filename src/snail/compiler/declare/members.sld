;; Which member of a class or an effect a label names. A label is data: the
;; name it writes is compared with the name of each member, as the name is
;; held, never with text read out of a member's name. A member a macro's
;; template wrote, whose Global has a serial of its own, is named by no
;; label, as in the old compiler, which compares a label with the text
;; after the last colon of a member's unique name, and for such a member
;; that text holds the stamp of its macro's use. A method definition names
;; a declared class's method by its name, whether `expand` read the name
;; as a member's label or as a field path, so a path names none; it names
;; a field class's one method, which reads the field, by the path of
;; exactly that class's label.
(define-library (snail compiler declare members)
  (export
   named-member
   missing-member
   named-operation)
  (import
   (snail core base)
   (only (snail compiler expand language) MethodName MemberName PathName)
   (only (snail compiler names globals) Global)
   (snail compiler declare language)
   (snail compiler declare membership))
  (begin

    ;; ---- Methods ----

    ;; The member a method definition's name names among `members`, those
    ;; (snail compiler declare membership) says the class has, or the
    ;; old compiler's refusal, which spells the name as written.
    (: named-member (impl (Fn (List Member) MethodName -> (Result Member String))))
    (define (named-member members name)
      (match (find (lambda (member) (names-member? name member)) members)
        ((Some member) (Ok member))
        ((None) (Err (string-append "not a method of this class: " (written-name name))))))

    (: names-member? (impl (Fn MethodName Member -> Bool)))
    (define (names-member? name member)
      (match member
        ((ClassMethod global) (written-for? global (written-name name)))
        ((FieldReader label)
         (match name
           ((PathName (Cons only (Nil)) _) (string=? only label))
           (_ #f)))))

    (: written-name (impl (Fn MethodName -> String)))
    (define (written-name name)
      (match name
        ((MemberName label) (::name label))
        ((PathName _ label) (::name label))))

    ;; The first of the class's members that no definition implements, by
    ;; the name its message gives it.
    (: missing-member (impl (Fn (List Member) (List Member) -> (Option String))))
    (define (missing-member members implemented)
      (match (find (lambda (member)
                     (not (any? (lambda (other) (same-member? member other)) implemented)))
                   members)
        ((Some member) (Some (string-append "instance is missing a method: " (member-name member))))
        ((None) (None))))

    ;; ---- Operations ----

    ;; The operation of an effect a default or a handler's clause names
    ;; with `name`, or the old compiler's refusal.
    (: named-operation (impl (Fn (List Operation) String -> (Result Operation String))))
    (define (named-operation operations name)
      (match (find (lambda (operation) (written-for? (::global operation) name)) operations)
        ((Some operation) (Ok operation))
        ((None) (Err (string-append "not an operation of this effect: " name)))))

    ;; ---- Names ----

    ;; Whether a label written `name` can name the member `global`: one the
    ;; source wrote under that name, not one a macro's template wrote.
    (: written-for? (impl (Fn Global String -> Bool)))
    (define (written-for? global name)
      (and (= (::serial global) 0) (string=? (::name global) name)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-members)
    (import
     (snail compiler source)
     (only (snail compiler names globals) ClassGlobal FieldClass Label)
     (snail stage0 testing))
    (begin
      (define (test-members)
        (test-methods)
        (test-missing)
        (test-operations))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define unit-type (Con (Global (list "snail" "core" "forms") "Unit" 0) (list)))

      (define (method name serial)
        (Method (Global main name serial) (Scheme (list) (list) (list) unit-type) (list) loc))

      (define (member-name-of text)
        (MemberName (Label text loc)))

      (define show-members
        (class-members (ClassGlobal (Global main "Show" 0))
                       (list (method "show" 0) (method "width" 0) (method "hidden" 4))))

      ;; A declared class's method by its name, even one with a colon, and
      ;; never one a macro wrote, nor by a path; a field class's by the path
      ;; of its one label.
      (define (test-methods)
        (expect (named-member show-members (member-name-of "width"))
                (Ok (ClassMethod (Global main "width" 0))))
        (expect (named-member show-members (member-name-of "hidden"))
                (Err "not a method of this class: hidden"))
        (expect (named-member show-members (PathName (list "show") (Label "::show" loc)))
                (Err "not a method of this class: ::show"))
        (expect (named-member (class-members (ClassGlobal (Global main "C" 0))
                                             (list (method "a:b" 0)))
                              (member-name-of "a:b"))
                (Ok (ClassMethod (Global main "a:b" 0))))
        (let ((field (class-members (FieldClass "x") (list))))
          (expect field (list (FieldReader "x")))
          (expect (named-member field (PathName (list "x") (Label "::x" loc)))
                  (Ok (FieldReader "x")))
          (expect (named-member field (PathName (list "x" "y") (Label "::x::y" loc)))
                  (Err "not a method of this class: ::x::y"))
          (expect (named-member field (member-name-of "::x::"))
                  (Err "not a method of this class: ::x::"))
          (expect (named-member field (member-name-of "x")) (Err "not a method of this class: x"))))

      ;; The class's first member left unimplemented, in the class's order.
      (define (test-missing)
        (expect (missing-member show-members show-members) (None))
        (expect (missing-member show-members (list (ClassMethod (Global main "width" 0))))
                (Some "instance is missing a method: show"))
        (expect (missing-member (list (FieldReader "x")) (list))
                (Some "instance is missing a method: x"))
        (expect (missing-member (list) (list)) (None)))

      (define (operation name serial)
        (Operation (Global main name serial) #f (list) unit-type (list) (list) loc))

      (define (test-operations)
        (let ((operations (list (operation "read" 0) (operation "write" 2))))
          (expect (named-operation operations "read") (Ok (operation "read" 0)))
          (expect (named-operation operations "write")
                  (Err "not an operation of this effect: write"))
          (expect (named-operation operations "close")
                  (Err "not an operation of this effect: close"))))))
   (else)))
