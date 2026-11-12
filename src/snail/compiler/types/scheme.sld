;; What a scheme is, as every pass from `declare` on holds it: a type
;; quantified over its variables, with the requirements whose evidence a
;; use supplies.
;;
;;   Scheme      ::= Scheme TypeVariable* Requirement* TypeVariable* Type
;;   Requirement ::= ClassRequirement ClassRef Type*
;;                 | CallableRequirement Contract Type Arrow
;;
;; The variables the scheme says `Copy` are apart from its requirements,
;; which have evidence, by position. A class requirement gives each of
;; its class's parameters, its outputs last, in the class's order. A
;; callable requirement is the compiler's, never an instance's. The order
;; a scheme quantifies its variables in is the one `declare` writes, as
;; (snail compiler declare language) states it.
(define-library (snail compiler types scheme)
  (export
   Scheme
   Requirement
   ClassRequirement
   CallableRequirement)
  (import
   (snail core base)
   (only (snail compiler names globals) ClassRef)
   (only (snail compiler types type) Type Arrow TypeVariable Contract))
  (begin

    ;; ---- Schemes ----

    (struct Scheme
      ((variables (List TypeVariable))
       (requirements (List Requirement))
       (copied (List TypeVariable))
       (type Type)))

    ;; A class at each of its parameters, its outputs last; or one of the
    ;; compiler's callable classes, at a receiver and an arrow, whose
    ;; evidence the compiler finds from the receiver's representation.
    (enum Requirement
      (ClassRequirement
       ((class ClassRef)
        (types (List Type))))
      (CallableRequirement
       ((contract Contract)
        (receiver Type)
        (arrow Arrow))))

    ))
