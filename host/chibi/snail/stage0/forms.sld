;; Snail-Core's typed forms for the Chibi host, erased to R7RS: signatures and
;; aliases disappear, struct values are vectors whose first slot is their
;; constructor procedure, so `match` can test it with `eq?`, and a control
;; effect escapes to its handler. Chibi's (snail core base) re-exports these;
;; Snail-Core itself never loads this library.
(define-library (snail stage0 forms)
  (export
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
   ref-set!)
  (import
   (scheme base)
   (scheme cxr)
   (only (chibi) er-macro-transformer))
  (begin

    ;; ---- Erased declarations ----

    (define-syntax :
      (syntax-rules ()
        ((_ . anything) (begin))))

    ;; An alias's name is bound, so libraries can export it.
    (define-syntax type
      (syntax-rules ()
        ((_ (name parameter ...) body) (define name 'name))
        ((_ name body) (define name 'name))))

    (define-syntax ann
      (syntax-rules ()
        ((_ expression type) expression)))

    ;; Without static types, every value is already dynamic.
    (define-syntax type-convert
      (syntax-rules ()
        ((_ expression type) expression)))

    ;; ---- Mutable cells ----

    ;; A cell is a one-slot vector; cells are never matched as structs.
    (define (ref value)
      (vector value))

    (define (ref-get cell)
      (vector-ref cell 0))

    (define (ref-set! cell value)
      (vector-set! cell 0 value))

    ;; ---- Structs and enum cases ----

    ;; `(struct (Name T ...) ((field type) ...))` defines the constructor `Name`,
    ;; accessors `Name-field` and pure replacements `Name-field-set`. A field
    ;; written `(field mut type)` gets `Name-field-set!` and
    ;; `Name-field-replace!` instead, which change the vector in place, and its
    ;; struct gets no pure replacements, as Snail-Core's own expander decides.
    (define (head-name head)
      (if (pair? head) (car head) head))

    (define (joined-name . parts)
      (string->symbol
       (apply string-append
              (map (lambda (part) (if (symbol? part) (symbol->string part) part)) parts))))

    (define (mutable-field? field)
      (and (pair? (cdr field)) (eq? (cadr field) 'mut) (pair? (cddr field))))

    (define (any-mutable? fields)
      (and (pair? fields) (or (mutable-field? (car fields)) (any-mutable? (cdr fields)))))

    (define (field-definitions name field index pure? rename)
      (let ((define* (rename 'define))
            (vector-ref* (rename 'vector-ref))
            (vector-set* (rename 'vector-set!))
            (field-name (car field)))
        (cons `(,define* (,(joined-name name "-" field-name) value) (,vector-ref* value ,index))
              (cond ((mutable-field? field)
                     (list `(,define* (,(joined-name name "-" field-name "-set!") value content)
                              (,vector-set* value ,index content))
                           `(,define* (,(joined-name name "-" field-name "-replace!") value content)
                              (,(rename 'let) ((old (,vector-ref* value ,index)))
                               (,vector-set* value ,index content)
                               old))))
                    (pure?
                     (list `(,define* (,(joined-name name "-" field-name "-set") value replacement)
                              (,(rename 'let) ((copy (,(rename 'vector-copy) value)))
                               (,vector-set* copy ,index replacement)
                               copy))))
                    (else '())))))

    (define (record-definitions name fields struct? rename)
      (let ((pure? (and struct? (not (any-mutable? fields)))))
        (let loop ((fields fields) (index 1) (out '()))
          (if (null? fields)
              out
              (loop (cdr fields)
                    (+ index 1)
                    (append out (field-definitions name (car fields) index pure? rename)))))))

    (define (constructor-definition name fields rename)
      (let ((parameters (map car fields)))
        `(,(rename 'define) (,name ,@parameters) (,(rename 'vector) ,name ,@parameters))))

    (define-syntax struct
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((name (head-name (cadr form)))
               (fields (if (pair? (cddr form)) (caddr form) '())))
           `(,(rename 'begin)
             ,(constructor-definition name fields rename)
             ,@(record-definitions name fields #t rename))))))

    ;; The enum's name is bound too, so libraries can export it.
    (define-syntax enum
      (er-macro-transformer
       (lambda (form rename compare)
         `(,(rename 'begin)
           (,(rename 'define) ,(head-name (cadr form)) ',(head-name (cadr form)))
           ,@(apply append
                    (map (lambda (case)
                           (let ((fields (if (pair? (cdr case)) (cadr case) '())))
                             (cons (constructor-definition (car case) fields rename)
                                   (record-definitions (car case) fields #f rename))))
                         (cddr form)))))))

    ;; ---- Pattern matching ----

    ;; Patterns are `_`, variables, literals, `'datum`, `(Constructor pattern ...)`,
    ;; and the list patterns `(Cons head tail)` and `(Nil)`. Each clause becomes
    ;; a `cond` test over paths into the scrutinee and a `let` of the paths its
    ;; variables name, so matching allocates nothing.
    (define (pattern-test pattern path rename compare)
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

    (define (field-tests patterns path index rename compare)
      (if (null? patterns)
          '()
          (cons (pattern-test (car patterns) `(,(rename 'vector-ref) ,path ,index) rename compare)
                (field-tests (cdr patterns) path (+ index 1) rename compare))))

    ;; The (variable path) bindings of a pattern.
    (define (pattern-bindings pattern path rename compare)
      (cond ((and (symbol? pattern) (compare pattern (rename '_))) '())
            ((symbol? pattern) (list (list pattern path)))
            ((and (pair? pattern) (compare (car pattern) (rename 'quote))) '())
            ((and (pair? pattern) (eq? (car pattern) 'Nil)) '())
            ((and (pair? pattern) (eq? (car pattern) 'Cons))
             (append (pattern-bindings (cadr pattern) `(,(rename 'car) ,path) rename compare)
                     (pattern-bindings (caddr pattern) `(,(rename 'cdr) ,path) rename compare)))
            ((pair? pattern) (field-bindings (cdr pattern) path 1 rename compare))
            (else '())))

    (define (field-bindings patterns path index rename compare)
      (if (null? patterns)
          '()
          (append
           (pattern-bindings (car patterns) `(,(rename 'vector-ref) ,path ,index) rename compare)
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
           (unless (null? (cdddr form))
             (error "stage 0's effect takes no default clause" name))
           `(,(rename 'begin)
             (,(rename 'define) ,name (,(rename 'make-parameter) #f))
             ,@(map (lambda (operation) (operation-definition name operation rename))
                    (caddr form)))))))

    (define (operation-definition effect operation rename)
      (unless (eq? (car operation) 'ctl)
        (error "stage 0 implements only control operations" operation))
      (let ((name (cadr operation)) (arguments (rename 'arguments)))
        `(,(rename 'define) (,name . ,arguments)
          (,(rename 'perform) ,effect
           ',name
           ,(if (never-answer? (caddr operation))
                arguments
                `(,(rename 'append) ,arguments (,(rename 'list) ,(rename 'cannot-resume))))))))

    ;; Whether an operation's type, `(-> argument ... answer)` with perhaps
    ;; `! effect ...` after it, answers `Never`.
    (define (never-answer? type)
      (let loop ((parts (cdr type)) (answer #f))
        (if (or (null? parts) (eq? (car parts) '!))
            (eq? answer 'Never)
            (loop (cdr parts) (car parts)))))

    ;; The innermost handler of `effect` runs the implementation of
    ;; `operation` back at its `handle`, so under the handlers outside it.
    (define (perform effect operation arguments)
      (let ((handler (effect)))
        (unless handler
          (error "unhandled effect operation" operation))
        ((car handler) (lambda () (apply (cdr (assq operation (cdr handler))) arguments)))))

    (define (cannot-resume answer)
      (error "stage 0 cannot resume"))

    ;; `(handle Name ((operation implementation) ...) body ...)`.
    (define-syntax handle
      (syntax-rules ()
        ((_ effect ((operation implementation) ...) body ...)
         (handling effect (list (cons 'operation implementation) ...) (lambda () body ...)))))

    ;; The body's value, or the answer of the implementation an operation
    ;; escaped to run. The escape hands back a thunk, which is called here,
    ;; outside the `parameterize`.
    (define (handling effect implementations body)
      ((call/cc (lambda (escape)
                  (let ((value (parameterize ((effect (cons escape implementations))) (body))))
                    (lambda () value))))))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-forms)
    (import
     (snail stage0 testing))
    (begin
      (effect Stop
        ((ctl stop (-> I64 Never))
         (ctl ask (-> I64 I64))))

      (define (failure-message thunk)
        (guard (failure ((error-object? failure) (error-object-message failure))) (thunk)))

      ;; A mutable field changes in place, so every name for the struct
      ;; sees the write, and a swap answers the old content.
      (struct Counter
        ((name String)
         (count mut I64)))

      (define (test-forms)
        ;; The implementation's answer is the handle's; nothing after the
        ;; operation runs, and a guard between them does not see it.
        (expect (handle Stop ((stop (lambda (code) (* code 10))) (ask (lambda (n resume) n)))
                  (+ 1 (guard (failure (#t 0)) (stop 4))))
                40)
        ;; An implementation runs outside its handler, so its operation
        ;; reaches the next handler out.
        (expect (handle Stop ((stop (lambda (code) (list 'outer code))) (ask (lambda (n resume) n)))
                  (handle Stop ((stop (lambda (code) (stop (+ code 1))))
                                (ask (lambda (n resume) n)))
                    (stop 1)))
                '(outer 2))
        (expect (handle Stop ((stop (lambda (code) code)) (ask (lambda (n resume) n))) 5) 5)
        (expect (failure-message
                 (lambda ()
                   (handle Stop ((stop (lambda (code) code)) (ask (lambda (n resume) (resume n))))
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
