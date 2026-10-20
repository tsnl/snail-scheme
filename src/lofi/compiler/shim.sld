;; The Chibi host's view of Lofi's typed forms. Each form erases to R7RS:
;; signatures and aliases disappear, and struct values are vectors whose first
;; slot is their constructor procedure, so `match` can test it with `eq?`.
;; Where the compiler uses #f for an absent value, a constructor pattern
;; simply fails to match it.
(define-library (lofi compiler shim)
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

    (define-syntax type
      (syntax-rules ()
        ((_ . anything) (begin))))

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

    (define-syntax enum
      (er-macro-transformer
       (lambda (form rename compare)
         `(,(rename 'begin)
           ,@(apply append
                    (map (lambda (case)
                           (let ((fields (if (pair? (cdr case)) (cadr case) '())))
                             (cons (constructor-definition (car case) fields rename)
                                   (record-definitions (car case) fields #f rename))))
                         (cddr form)))))))

    ;; ---- Pattern matching ----

    ;; Patterns are `_`, variables, literals, `'datum`, `(Constructor pattern ...)`,
    ;; and the list patterns `(Cons head tail)`, `(Nil)` and `(list pattern ...)`.
    ;; Clauses are tried in order. A failed clause calls the next clause's thunk,
    ;; so each body appears once in the expansion.
    (define fresh-count 0)

    (define (fresh-name prefix rename)
      (set! fresh-count (+ fresh-count 1))
      (rename (joined-name prefix (number->string fresh-count))))

    (define (pattern-code value pattern success failure rename compare)
      (cond ((and (symbol? pattern) (compare pattern (rename '_))) success)
            ((symbol? pattern) `(,(rename 'let) ((,pattern ,value)) ,success))
            ((and (pair? pattern) (compare (car pattern) (rename 'quote)))
             `(,(rename 'if) (,(rename 'equal?) ,value ,pattern) ,success ,failure))
            ((and (pair? pattern) (eq? (car pattern) 'Nil))
             `(,(rename 'if) (,(rename 'null?) ,value) ,success ,failure))
            ((and (pair? pattern) (eq? (car pattern) 'Cons))
             (pair-code value (cadr pattern) (caddr pattern) success failure rename compare))
            ((and (pair? pattern) (eq? (car pattern) 'list))
             (pattern-code value (fold-right (lambda (item tail) (list 'Cons item tail)) '(Nil) (cdr pattern))
                           success failure rename compare))
            ((pair? pattern)
             `(,(rename 'if) (,(rename 'and) (,(rename 'vector?) ,value) (,(rename 'eq?) (,(rename 'vector-ref) ,value 0) ,(car pattern)))
               ,(fields-code value (cdr pattern) 1 success failure rename compare)
               ,failure))
            (else `(,(rename 'if) (,(rename 'equal?) ,value ,pattern) ,success ,failure))))

    ;; Scheme lists stand in for Lofi's `(List T)`, whose cases are `Cons` and `Nil`.
    (define (pair-code value head tail success failure rename compare)
      (let ((first (fresh-name "head" rename)) (rest (fresh-name "tail" rename)))
        `(,(rename 'if) (,(rename 'pair?) ,value)
          (,(rename 'let) ((,first (,(rename 'car) ,value)) (,rest (,(rename 'cdr) ,value)))
           ,(pattern-code first head (pattern-code rest tail success failure rename compare) failure rename compare))
          ,failure)))

    (define (fold-right kons knil items)
      (if (null? items) knil (kons (car items) (fold-right kons knil (cdr items)))))

    (define (fields-code value patterns index success failure rename compare)
      (if (null? patterns)
          success
          (let ((field (fresh-name "field" rename)))
            `(,(rename 'let) ((,field (,(rename 'vector-ref) ,value ,index)))
              ,(pattern-code field (car patterns)
                             (fields-code value (cdr patterns) (+ index 1) success failure rename compare)
                             failure rename compare)))))

    (define (clauses-code value clauses rename compare)
      (if (null? clauses)
          `(,(rename 'error) "match: no clause matched" ,value)
          (let ((next (fresh-name "next" rename)))
            `(,(rename 'let) ((,next (,(rename 'lambda) () ,(clauses-code value (cdr clauses) rename compare))))
              ,(pattern-code value (caar clauses)
                             `(,(rename 'let) () ,@(cdar clauses))
                             `(,next) rename compare)))))

    (define-syntax match
      (er-macro-transformer
       (lambda (form rename compare)
         (let ((value (rename 'scrutinee)))
           `(,(rename 'let) ((,value ,(cadr form)))
             ,(clauses-code value (cddr form) rename compare))))))

    ))
