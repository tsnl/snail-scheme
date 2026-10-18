;; Checked programs retain source, binding schemes, lexical scopes and static
;; class evidence. Expression typing results never become part of this record.
(define-library (lofi compiler checked)
  (export make-program program? program-body program-globals program-classes program-instances program-type program-scopes
          make-class class? class-definition class-variables class-methods class-overload?
          class-instance-cache set-class-instance-cache!
          make-instance instance? instance-class instance-types instance-members instance-scheme instance-row)
  (import
   (scheme base)
   (only (lofi compiler types) scheme-type))
  (begin

    ;; ---- Checked compilation roots ----

    (define-record-type <program>
      (make-program body globals classes instances type scopes) program?
      (body program-body)
      (globals program-globals)
      (classes program-classes)
      (instances program-instances)
      (type program-type)
      (scopes program-scopes))

    ;; ---- Static class evidence ----

    (define-record-type <class>
      (new-class definition variables methods overload? instance-cache) class?
      (definition class-definition)
      (variables class-variables)
      (methods class-methods)
      (overload? class-overload?)
      (instance-cache class-instance-cache set-class-instance-cache!))
    (define (make-class definition variables methods overload?)
      (new-class definition variables methods overload? #f))
    ;; Ordinary instances have a concrete head. An overload row has one complete
    ;; declared function scheme; its source row retains member identity and
    ;; location separately from runtime bindings.
    (define-record-type <instance>
      (make-instance class head members scheme row) instance?
      (class instance-class)
      (head instance-head)
      (members instance-members)
      (scheme instance-scheme)
      (row instance-row))
    (define (instance-types instance)
      (if (instance-scheme instance) (list (scheme-type (instance-scheme instance)))
          (instance-head instance)))))
