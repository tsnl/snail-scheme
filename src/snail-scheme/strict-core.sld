;; Program-wide static evidence accompanies the shared IR. Expression and
;; definition records live in ir.sld throughout expansion, checking and copying.
(define-library (snail-scheme strict-core)
  (export make-program program? program-body program-globals program-classes program-instances
          make-class class? class-definition class-variables class-methods class-overload?
          make-instance instance? instance-class instance-types instance-members instance-scheme instance-row)
  (import (scheme base) (only (snail-scheme strict-types) scheme-type))
  (begin

    ;; ---- Checked compilation roots ----

    (define-record-type <program>
      (make-program body globals classes instances) program?
      (body program-body) (globals program-globals)
      (classes program-classes) (instances program-instances))

    ;; ---- Static class evidence ----

    (define-record-type <class>
      (make-class definition variables methods overload?) class?
      (definition class-definition) (variables class-variables) (methods class-methods)
      (overload? class-overload?))
    ;; Ordinary instances have a concrete head. An overload row has one complete
    ;; declared function scheme; its source row retains member identity and
    ;; location separately from runtime bindings.
    (define-record-type <instance>
      (make-instance class head members scheme row) instance?
      (class instance-class) (head instance-head) (members instance-members)
      (scheme instance-scheme) (row instance-row))
    (define (instance-types instance)
      (if (instance-scheme instance) (list (scheme-type (instance-scheme instance)))
          (instance-head instance)))))
