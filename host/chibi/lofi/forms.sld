;; Lofi's typed forms for the Chibi host, erased to R7RS: signatures and
;; aliases disappear, and struct values are vectors whose first slot is their
;; constructor procedure, so `match` can test it with `eq?`. Chibi's (lofi
;; base) re-exports these; Lofi itself never loads this library.
(define-library (lofi forms)
  (export
   :
   type
   ann
   type-convert
   struct
   enum
   match
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
    ;; accessors `Name-field` and pure replacements `Name-field-set`.
    (define (head-name head)
      (if (pair? head) (car head) head))

    (define (joined-name . parts)
      (string->symbol
       (apply string-append
              (map (lambda (part) (if (symbol? part) (symbol->string part) part)) parts))))

    (define (record-definitions name fields setters? rename)
      (let ((define* (rename 'define)) (vector-ref* (rename 'vector-ref)))
        (let loop ((fields fields) (index 1) (out '()))
          (if (null? fields)
              (reverse out)
              (let* ((field (caar fields))
                     (accessor `(,define* (,(joined-name name "-" field) value) (,vector-ref* value ,index)))
                     (setter `(,define* (,(joined-name name "-" field "-set") value replacement)
                                (,(rename 'let) ((copy (,(rename 'vector-copy) value)))
                                 (,(rename 'vector-set!) copy ,index replacement)
                                 copy))))
                (loop (cdr fields) (+ index 1)
                      (if setters? (cons setter (cons accessor out)) (cons accessor out))))))))

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
            ((and (pair? pattern) (compare (car pattern) (rename 'quote))) `(,(rename 'equal?) ,path ,pattern))
            ((and (pair? pattern) (eq? (car pattern) 'Nil)) `(,(rename 'null?) ,path))
            ((and (pair? pattern) (eq? (car pattern) 'Cons))
             `(,(rename 'and) (,(rename 'pair?) ,path)
               ,(pattern-test (cadr pattern) `(,(rename 'car) ,path) rename compare)
               ,(pattern-test (caddr pattern) `(,(rename 'cdr) ,path) rename compare)))
            ((pair? pattern)
             `(,(rename 'and) (,(rename 'vector?) ,path) (,(rename 'eq?) (,(rename 'vector-ref) ,path 0) ,(car pattern))
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
          (append (pattern-bindings (car patterns) `(,(rename 'vector-ref) ,path ,index) rename compare)
                  (field-bindings (cdr patterns) path (+ index 1) rename compare))))

    (define-syntax match
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((value (rename 'scrutinee)))
           `(,(rename 'let) ((,value ,(cadr form)))
             (,(rename 'cond)
              ,@(map (lambda (clause)
                       `(,(pattern-test (car clause) value rename compare)
                         (,(rename 'let) ,(pattern-bindings (car clause) value rename compare) ,@(cdr clause))))
                     (cddr form))
              (,(rename 'else) (,(rename 'error) "match: no clause matched" ,value))))))))

    ))
