;; Program-wide static evidence accompanies the shared IR. Expression and
;; definition records live in ir.sld throughout expansion, checking and copying.
(define-library (snail-scheme strict-core)
  (export make-program program? program-body program-globals program-classes program-instances
          make-class class? class-definition class-variables class-methods class-overload?
          make-instance instance? instance-class instance-types instance-members instance-scheme)
  (import (scheme base))
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
    (define-record-type <instance>
      (make-instance class types members scheme) instance?
      (class instance-class) (types instance-types) (members instance-members)
      (scheme instance-scheme))))
