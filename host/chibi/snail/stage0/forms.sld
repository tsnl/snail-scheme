;; Snail-Core's typed forms for the Chibi host, erased to R7RS: signatures and
;; aliases disappear, struct values are vectors whose first slot is their
;; constructor procedure, so `match` can test it with `eq?`, and a control
;; effect escapes to its handler. Chibi's (snail core base) re-exports these;
;; Snail-Core itself never loads this library.
(define-library (snail stage0 forms)
  (export
   define
   :
   type
   ann
   type-convert
   struct
   enum
   match
   effect
   handle
   ref
   ref-get
   ref-set!
   field-of
   ●)
  (import
   (rename (scheme base) (define scheme-define))
   (scheme cxr)
   (only (chibi) er-macro-transformer)
   (srfi 69))
  (begin

    ;; ---- Erased declarations ----

    (define-syntax :
      (syntax-rules ()
        ((_ . anything) (begin))))

    ;; An alias's name is bound, so libraries can export it.
    (define-syntax type
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((name (head-name (cadr form))))
           `(,(rename 'scheme-define) ,name ',name)))))

    (define-syntax ann
      (syntax-rules ()
        ((_ expression type) expression)))

    ;; Without static types, every value is already dynamic.
    (define-syntax type-convert
      (syntax-rules ()
        ((_ expression type) expression)))

    ;; ---- Mutable cells ----

    ;; A cell is a one-slot vector; cells are never matched as structs.
    (scheme-define (ref value)
      (vector value))

    (scheme-define (ref-get cell)
      (vector-ref cell 0))

    (scheme-define (ref-set! cell value)
      (vector-set! cell 0 value))

    ;; ---- Structs and enum cases ----

    ;; `(struct (Name T ...) ((field type) ...))` defines the constructor `Name`,
    ;; accessors `Name-field` and pure replacements `Name-field-set`. A field
    ;; written `(field mut type)` gets `Name-field-set!` and
    ;; `Name-field-replace!` instead, which change the vector in place, and its
    ;; struct gets no pure replacements, as Snail-Core's own expander decides.
    (scheme-define (head-name head)
      (if (pair? head) (car head) head))

    ;; Annotations affect compiler metadata only. Stage 0 erases the optional
    ;; trailing list before counting an enum's cases or a case's fields.
    (scheme-define (without-annotations parts)
      (let ((backwards (reverse parts)))
        (if (and (pair? backwards) (pair? (car backwards))
                 (eq? (caar backwards) 'annotations))
            (reverse (cdr backwards))
            parts)))

    (scheme-define (joined-name . parts)
      (string->symbol
       (apply string-append
              (map (lambda (part) (if (symbol? part) (symbol->string part) part))
                   parts))))

    (scheme-define (mutable-field? field)
      (and (pair? (cdr field)) (eq? (cadr field) 'mut) (pair? (cddr field))))

    (scheme-define (any-mutable? fields)
      (and (pair? fields)
           (or (mutable-field? (car fields)) (any-mutable? (cdr fields)))))

    (scheme-define (field-definitions name field index pure? rename)
      (let ((define* (rename 'scheme-define))
            (vector-ref* (rename 'vector-ref))
            (vector-set* (rename 'vector-set!))
            (field-name (car field)))
        (cons `(,define* (,(joined-name name "-" field-name) value)
                 (,vector-ref* value ,index))
              (cond ((mutable-field? field)
                     (list `(,define* (,(joined-name name "-" field-name "-set!")
                                       value
                                       content)
                              (,vector-set* value ,index content))
                           `(,define* (,(joined-name name "-" field-name "-replace!")
                                       value
                                       content)
                              (,(rename 'let) ((old (,vector-ref* value ,index)))
                               (,vector-set* value ,index content)
                               old))))
                    (pure?
                     (list `(,define* (,(joined-name name "-" field-name "-set")
                                       value
                                       replacement)
                              (,(rename 'let) ((copy (,(rename 'vector-copy) value)))
                               (,vector-set* copy ,index replacement)
                               copy))))
                    (else '())))))

    (scheme-define (record-definitions name fields struct? rename)
      (let ((pure? (and struct? (not (any-mutable? fields)))))
        (let loop ((fields fields) (index 1) (out '()))
          (if (null? fields)
              out
              (loop (cdr fields)
                    (+ index 1)
                    (append out
                            (field-definitions name
                                               (car fields)
                                               index
                                               pure?
                                               rename)))))))

    (scheme-define (constructor-definition name fields rename)
      (let ((parameters (map car fields)))
        `(,(rename 'scheme-define)
          (,name ,@parameters)
          (,(rename 'vector) ,name ,@parameters))))

    (define-syntax struct
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((name (head-name (cadr form)))
               (fields (let ((body (without-annotations (cddr form))))
                         (if (pair? body) (car body) '()))))
           `(,(rename 'begin)
             ,(constructor-definition name fields rename)
             (,(rename 'register-fields!) ,name ',(map car fields))
             ,@(record-definitions name fields #t rename))))))

    ;; ---- Field paths ----

    ;; Record declarations register labels beside their constructor. The
    ;; projection macro below quotes each label, so it needs no generated
    ;; binding or typeclass dispatcher per field.

    (scheme-define struct-fields (make-hash-table eq?))

    (scheme-define (register-fields! constructor fields)
      (hash-table-set! struct-fields constructor fields))

    (scheme-define (field-of value label)
      (let loop ((fields (hash-table-ref struct-fields
                                         (vector-ref value 0)
                                         (lambda () (error "not a struct" value))))
                 (index 1))
        (cond ((null? fields) (error "no such field" label value))
              ((eq? (car fields) label) (vector-ref value index))
              (else (loop (cdr fields) (+ index 1))))))

    ;; The enum's name is bound too, so libraries can export it.
    (define-syntax enum
      (er-macro-transformer
       (lambda (form rename compare)
         `(,(rename 'begin)
           (,(rename 'scheme-define) ,(head-name (cadr form)) ',(head-name (cadr form)))
           ,@(apply append
                    (map (lambda (case)
                           (let* ((body (without-annotations (cdr case)))
                                  (fields (if (pair? body) (car body) '())))
                             (cons (constructor-definition (car case) fields rename)
                                   (record-definitions (car case) fields #f rename))))
                         (without-annotations (cddr form))))))))

    ;; Field labels are syntax, and a pointer is followed only while another
    ;; label remains. A registered zero-field record is not a Ref cell.
    (scheme-define (field-referent value)
      (if (and (vector? value) (= (vector-length value) 1)
               (not (hash-table-exists? struct-fields (vector-ref value 0))))
          (field-referent (vector-ref value 0))
          value))

    (define-syntax ●
      (syntax-rules ()
        ((_ value label) (field-of (field-referent value) (quote label)))
        ((_ value label next ...) (● (● value label) next ...))))

    ;; ---- Pattern matching ----

    ;; Patterns are `_`, variables, literals, `'datum`, `(Constructor pattern ...)`,
    ;; and the list patterns `(Cons head tail)` and `(Nil)`. Each clause becomes
    ;; a `cond` test over paths into the scrutinee and a `let` of the paths its
    ;; variables name, so matching allocates nothing.
    (scheme-define (pattern-test pattern path rename compare)
      (cond ((symbol? pattern) #t)
            ((and (pair? pattern) (compare (car pattern) (rename 'quote)))
             `(,(rename 'equal?) ,path ,pattern))
            ((and (pair? pattern) (eq? (car pattern) 'Nil)) `(,(rename 'null?) ,path))
            ((and (pair? pattern) (eq? (car pattern) 'Cons))
             `(,(rename 'and) (,(rename 'pair?) ,path)
               ,(pattern-test (cadr pattern) `(,(rename 'car) ,path) rename compare)
               ,(pattern-test (caddr pattern) `(,(rename 'cdr) ,path) rename compare)))
            ((pair? pattern)
             `(,(rename 'and)
               (,(rename 'vector?) ,path)
               (,(rename 'eq?) (,(rename 'vector-ref) ,path 0) ,(car pattern))
               ,@(field-tests (cdr pattern) path 1 rename compare)))
            (else `(,(rename 'equal?) ,path ,pattern))))

    (scheme-define (field-tests patterns path index rename compare)
      (if (null? patterns)
          '()
          (cons (pattern-test (car patterns)
                              `(,(rename 'vector-ref) ,path ,index)
                              rename
                              compare)
                (field-tests (cdr patterns) path (+ index 1) rename compare))))

    ;; The (variable path) bindings of a pattern.
    (scheme-define (pattern-bindings pattern path rename compare)
      (cond ((and (symbol? pattern) (compare pattern (rename '_))) '())
            ((symbol? pattern) (list (list pattern path)))
            ((and (pair? pattern) (compare (car pattern) (rename 'quote))) '())
            ((and (pair? pattern) (eq? (car pattern) 'Nil)) '())
            ((and (pair? pattern) (eq? (car pattern) 'Cons))
             (append
              (pattern-bindings (cadr pattern) `(,(rename 'car) ,path) rename compare)
              (pattern-bindings (caddr pattern)
                                `(,(rename 'cdr) ,path)
                                rename
                                compare)))
            ((pair? pattern) (field-bindings (cdr pattern) path 1 rename compare))
            (else '())))

    (scheme-define (field-bindings patterns path index rename compare)
      (if (null? patterns)
          '()
          (append
           (pattern-bindings (car patterns)
                             `(,(rename 'vector-ref) ,path ,index)
                             rename
                             compare)
           (field-bindings (cdr patterns) path (+ index 1) rename compare))))

    (define-syntax match
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((value (rename 'scrutinee)))
           `(,(rename 'let) ((,value ,(cadr form)))
             (,(rename 'cond)
              ,@(map (lambda (clause)
                       `(,(pattern-test (car clause) value rename compare)
                         (,(rename 'let)
                          ,(pattern-bindings (car clause) value rename compare)
                          ,@(cdr clause))))
                     (cddr form))
              (,(rename 'else) (,(rename 'error) "match: no clause matched" ,value))))))))

    ;; ---- Effects ----

    ;; Stage 0 runs the compiler, whose effect only fails: no operation of
    ;; it is resumed. So an effect is a parameter holding its innermost
    ;; handler, the continuation of that handler's `handle` and its
    ;; implementations, and an operation escapes to the continuation and
    ;; runs its implementation there, outside the handler; the
    ;; implementation's answer is the `handle`'s value. It escapes with
    ;; `call/cc`, not `raise`, so that no guard between the operation and
    ;; its handler can intercept it. An operation whose answer is `Never`
    ;; takes no `resume`; any other is handed one stage 0 cannot call.
    ;;
    ;; Stage 0 refuses ordinary operations, whose implementations would have
    ;; to run in place under the handlers outside their own `handle`, of
    ;; every effect, and `default` clauses.
    (define-syntax effect
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((name (cadr form)))
           (unless (null? (without-annotations (cdddr form)))
             (error "stage 0's effect takes no default clause" name))
           `(,(rename 'begin)
             (,(rename 'scheme-define) ,name (,(rename 'make-parameter) #f))
             ,@(map (lambda (operation) (operation-definition name operation rename))
                    (caddr form)))))))

    (scheme-define (operation-definition effect operation rename)
      (unless (eq? (car operation) 'ctl)
        (error "stage 0 implements only control operations" operation))
      (let ((name (cadr operation)) (arguments (rename 'arguments)))
        `(,(rename 'scheme-define) (,name . ,arguments)
          (,(rename 'perform) ,effect
           ',name
           ,(if (never-answer? (caddr operation))
                arguments
                `(,(rename 'append)
                  ,arguments
                  (,(rename 'list) ,(rename 'cannot-resume))))))))

    ;; The operation contract carries one answer immediately after `→`.
    ;; Stage 0 erases receiver and storage distinctions with the signature.
    (scheme-define (never-answer? type)
      (let ((result (memq '→ (cadr type))))
        (and result (pair? (cdr result)) (eq? (cadr result) 'Never))))

    ;; The innermost handler of `effect` runs the implementation of
    ;; `operation` back at its `handle`, so under the handlers outside it.
    (scheme-define (perform effect operation arguments)
      (let ((handler (effect)))
        (unless handler
          (error "unhandled effect operation" operation))
        ((car handler)
         (lambda () (apply (cdr (assq operation (cdr handler))) arguments)))))

    (scheme-define (cannot-resume answer)
      (error "stage 0 cannot resume"))

    ;; `(handle Name ((operation implementation) ...) body ...)`.
    (define-syntax handle
      (syntax-rules ()
        ((_ effect ((operation implementation) ...) body ...)
         (handling effect (list (cons 'operation implementation) ...) (lambda () body ...)))))

    ;; The body's value, or the answer of the implementation an operation
    ;; escaped to run. The escape hands back a thunk, which is called here,
    ;; outside the `parameterize`.
    (scheme-define (handling effect implementations body)
      ((call/cc (lambda (escape)
                  (let ((value (parameterize ((effect (cons escape implementations)))
                                 (body))))
                    (lambda () value))))))

    ;; Typed definitions use the same names and bodies at stage 0. A function
    ;; parameter `(name Type)` becomes `name`; declaration clauses disappear.
    ;; This macro is last so the R7RS definitions above remain ordinary host
    ;; definitions while the eraser itself is being initialized.
    (scheme-define (typed-definition-clause? part)
      (and (pair? part)
           (or (memq (car part) '(→ ! ∀ ⊨))
               (and (eq? (car part) 'annotations)
                    (or (null? (cdr part))
                        (pair? (cadr part)))))))

    (scheme-define (erase-parameter-types parameters)
      (cond ((null? parameters) '())
            ((pair? parameters)
             (cons (if (pair? (car parameters)) (caar parameters) (car parameters))
                   (erase-parameter-types (cdr parameters))))
            (else parameters)))

    (scheme-define (erase-definition target clauses rename)
      (let ((definition (rename 'scheme-define)))
        (cond ((pair? target)
               `(,definition
                  (,(car target) ,@(erase-parameter-types (cdr target)))
                  ,@clauses))
              (else `(,definition ,target ,@clauses)))))

    (define-syntax define
      (er-macro-transformer
       (lambda (form rename compare)
         (let* ((target (cadr form))
                (clauses (cddr form)))
           (let loop ((clauses clauses))
             (if (and (pair? clauses) (typed-definition-clause? (car clauses)))
                 (loop (cdr clauses))
                 (erase-definition target clauses rename)))))))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-forms)
    (import
     (snail stage0 testing))
    (begin
      (define (annotations value) value)
      (effect Stop
        ((ctl stop (dyn (Fn I64 → Never)) (annotations (doc "Stop now.")))
         (ctl ask (dyn (Fn I64 → I64))))
        (annotations (doc "A documented control effect.")))

      (scheme-define (failure-message thunk)
        (guard (failure ((error-object? failure) (error-object-message failure)))
          (thunk)))

      ;; A mutable field changes in place, so every name for the struct
      ;; sees the write, and a swap answers the old content.
      (struct Counter
        ((name String)
         (count mut I64)))

      ;; Metadata erases before stage 0 counts fields or enum cases.
      (struct Documented
        ((text String (annotations (doc "Text."))))
        (annotations (doc "A record.")))
      (enum DocumentedResult
        (DocumentedReady ((value I64 (annotations (doc "Value."))))
                         (annotations (doc "Ready.")))
        (DocumentedWaiting (annotations (doc "Waiting.")))
        (annotations (doc "A result.")))
      (type DocumentedAlias I64 (annotations (doc "An alias.")))
      (: documented-number I64 (annotations (doc "A value.")))
      (scheme-define documented-number 8)

      (define (typed-sum (left I64) (right I64))
        (→ I64)
        (∀ T)
        (⊨ example-constraint)
        (+ left right))
      (define typed-value (→ I64) (∀ T) 9)
      (define ordinary-annotation-value (annotations 3))
      (define documented-identity (→ (Fn I64 → I64))
        (annotations (doc "A typed header."))
        (lambda (value) value))

      (scheme-define (test-forms)
        (expect (Documented-text (Documented "text")) "text")
        (expect (field-of (Counter "n" 3) 'count) 3)
        (expect (● (Counter "n" 3) count) 3)
        (expect (● (ref (ref (Counter "n" 4))) count) 4)
        (expect (ref-get (● (Counter "n" (ref 5)) count)) 5)
        (let ((reads 0))
          (expect (● (begin (set! reads (+ reads 1)) (ref (Counter "n" 6))) count) 6)
          (expect reads 1))
        (expect (failure-message (lambda () (field-of (Counter "n" 3) 'total)))
                "no such field")
        (expect (DocumentedReady-value (DocumentedReady 5)) 5)
        (expect (match (DocumentedWaiting) ((DocumentedWaiting) #t) (_ #f)) #t)
        (expect documented-number 8)
        (expect (typed-sum 4 5) 9)
        (expect typed-value 9)
        (expect ordinary-annotation-value 3)
        (expect (documented-identity 7) 7)
        ;; The implementation's answer is the handle's; nothing after the
        ;; operation runs, and a guard between them does not see it.
        (expect
         (handle Stop ((stop (lambda (code) (* code 10))) (ask (lambda (n resume) n)))
           (+ 1 (guard (failure (#t 0)) (stop 4))))
         40)
        ;; An implementation runs outside its handler, so its operation
        ;; reaches the next handler out.
        (expect (handle Stop ((stop (lambda (code) (list 'outer code)))
                              (ask (lambda (n resume) n)))
                  (handle Stop ((stop (lambda (code) (stop (+ code 1))))
                                (ask (lambda (n resume) n)))
                    (stop 1)))
                '(outer 2))
        (expect
         (handle Stop ((stop (lambda (code) code)) (ask (lambda (n resume) n))) 5)
         5)
        (expect (failure-message
                 (lambda ()
                   (handle Stop ((stop (lambda (code) code))
                                 (ask (lambda (n resume) (resume n))))
                     (ask 3))))
                "stage 0 cannot resume")
        (expect (failure-message (lambda () (stop 1))) "unhandled effect operation")
        (let* ((counter (Counter "clicks" 1)) (same counter))
          (Counter-count-set! counter 5)
          (expect (Counter-count same) 5)
          (expect (Counter-count-replace! same 7) 5)
          (expect (Counter-count counter) 7)
          (expect (Counter-name counter) "clicks")))))
   (else)))
