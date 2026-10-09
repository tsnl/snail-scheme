;; Bootstrap library for compiled programs. The existing Scheme host supplies
;; its own (scheme base) while running the compiler.
(define-library (scheme base)
  (export
   define define-syntax syntax-rules let-syntax letrec-syntax lambda quote if set! begin
   let let* letrec letrec* and or cond case else => when unless
   let-values let*-values quasiquote unquote unquote-splicing define-record-type parameterize
   + - * / = < <= > >= quotient remainder modulo zero? positive? negative? abs
   eq? eqv? equal? not boolean? number? real? inexact? integer? exact-integer? pair? null? list?
   symbol? string? char? vector? bytevector? procedure?
   cons car cdr set-car! set-cdr! caar cadr cdar cddr
   list append reverse length list-ref list-tail make-list
   member memq memv assoc assq assv map for-each
   vector vector-ref vector-set! vector-length make-vector vector->list list->vector
   string string-ref string-length string-append substring string=?
   string->list list->string string->symbol symbol->string string->number number->string
   char->integer integer->char char=? char<? char<=? char>? char>=?
   bytevector bytevector-length bytevector-u8-ref bytevector-u8-set!
   values call-with-values apply error
   close-port close-input-port close-output-port call-with-port read-char eof-object?
   open-output-string get-output-string newline
   current-input-port current-output-port current-error-port make-parameter)
  (import (snail-scheme core))
  (begin
    ;; Introduced identifiers retain their definition-site bindings. Auxiliary
    ;; keywords have bindings too, so a locally shadowed `else` is not special.
    (define-syntax else (syntax-rules ()))
    (define-syntax => (syntax-rules ()))
    (define-syntax unquote (syntax-rules ()))
    (define-syntax unquote-splicing (syntax-rules ()))

    (define-syntax let
      (syntax-rules ()
        ((_ ((name initializer) ...) body ...)
         ((lambda (name ...) body ...) initializer ...))
        ((_ loop ((name initializer) ...) body ...)
         (((lambda ()
             (define (loop name ...) body ...)
             loop))
          initializer ...))))

    (define-syntax let*
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ ((name initializer) remaining ...) body ...)
         (let ((name initializer)) (let* (remaining ...) body ...)))))

    (define-syntax letrec*
      (syntax-rules ()
        ((_ ((name initializer) ...) body ...)
         (let () (define name initializer) ... body ...))))

    (define-syntax letrec
      (syntax-rules ()
        ((_ bindings body ...) (letrec* bindings body ...))))

    (define-syntax and
      (syntax-rules ()
        ((_) #t)
        ((_ expression) expression)
        ((_ first rest ...) (if first (and rest ...) #f))))

    (define-syntax or
      (syntax-rules ()
        ((_) #f)
        ((_ expression) expression)
        ((_ first rest ...) (let ((value first)) (if value value (or rest ...))))))

    (define-syntax when
      (syntax-rules () ((_ test body ...) (if test (begin body ...)))))

    (define-syntax unless
      (syntax-rules () ((_ test body ...) (if test (if #f #f) (begin body ...)))))

    (define-syntax cond
      (syntax-rules (else =>)
        ((_) (if #f #f))
        ((_ (else expression ...)) (begin expression ...))
        ((_ (test => receiver) remaining ...)
         (let ((value test)) (if value (receiver value) (cond remaining ...))))
        ((_ (test) remaining ...)
         (let ((value test)) (if value value (cond remaining ...))))
        ((_ (test expression ...) remaining ...)
         (if test (begin expression ...) (cond remaining ...)))))

    (define-syntax case
      (syntax-rules (else =>)
        ((_ key) (let ((value key)) (if #f #f)))
        ((_ key (else => receiver)) (receiver key))
        ((_ key (else expression ...)) (let ((value key)) (begin expression ...)))
        ((_ key ((datum ...) => receiver) remaining ...)
         (let ((value key))
           (if (memv value '(datum ...)) (receiver value) (case value remaining ...))))
        ((_ key ((datum ...) expression ...) remaining ...)
         (let ((value key))
           (if (memv value '(datum ...)) (begin expression ...) (case value remaining ...))))))

    (define-syntax let*-values
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ ((formals producer) remaining ...) body ...)
         (call-with-values (lambda () producer)
           (lambda formals (let*-values (remaining ...) body ...))))))

    ;; Build temporary formals one expansion at a time. Only the final let
    ;; introduces user names, so each producer sees the original environment.
    (define-syntax let-values
      (syntax-rules ()
        ((_ (binding ...) body ...)
         (let-values "bind" (binding ...) () (begin body ...)))
        ((_ "bind" () temporaries body) (let temporaries body))
        ((_ "bind" ((formals producer) remaining ...) temporaries body)
         (let-values "formals" formals producer () (remaining ...) temporaries body))
        ((_ "formals" () producer arguments remaining temporaries body)
         (call-with-values (lambda () producer)
           (lambda arguments (let-values "bind" remaining temporaries body))))
        ((_ "formals" (first . rest) producer (argument ...) remaining (temporary ...) body)
         (let-values "formals" rest producer (argument ... fresh) remaining
                     (temporary ... (first fresh)) body))
        ((_ "formals" rest producer () remaining (temporary ...) body)
         (call-with-values (lambda () producer)
           (lambda fresh (let-values "bind" remaining (temporary ... (rest fresh)) body))))
        ((_ "formals" rest producer (argument ...) remaining (temporary ...) body)
         (call-with-values (lambda () producer)
           (lambda (argument ... . fresh)
             (let-values "bind" remaining (temporary ... (rest fresh)) body))))))

    ;; The depth stack distinguishes commas in this template from commas in a
    ;; nested quasiquotation. Dotted tails and vector templates use the same walk.
    (define-syntax quasiquote
      (syntax-rules (quasiquote unquote unquote-splicing)
        ((_ datum) (quasiquote "expand" datum ()))
        ((_ "expand" (unquote expression) ()) expression)
        ((_ "expand" (unquote expression) (marker . depth))
         (list 'unquote (quasiquote "expand" expression depth)))
        ((_ "expand" (unquote-splicing expression) (marker . depth))
         (list 'unquote-splicing (quasiquote "expand" expression depth)))
        ((_ "expand" (quasiquote expression) depth)
         (list 'quasiquote (quasiquote "expand" expression (nested . depth))))
        ((_ "expand" ((unquote-splicing expression) . rest) ())
         (append expression (quasiquote "expand" rest ())))
        ((_ "expand" (first . rest) depth)
         (cons (quasiquote "expand" first depth) (quasiquote "expand" rest depth)))
        ((_ "expand" #(element ...) depth)
         (list->vector (quasiquote "expand" (element ...) depth)))
        ((_ "expand" atom depth) 'atom)))

    (define-syntax define-record-accessors
      (syntax-rules ()
        ((_ type field accessor)
         (define (accessor object) (%record-ref type 'field object)))
        ((_ type field accessor modifier)
         (begin
           (define (accessor object) (%record-ref type 'field object))
           (define (modifier object value) (%record-set! type 'field object value))))))

    (define-syntax define-record-type
      (syntax-rules ()
        ((_ type (constructor argument ...) predicate (field accessor modifier ...) ...)
         (begin
           (define type (%make-record-type 'type '(field ...)))
           (define (constructor argument ...)
             (%make-record type '(argument ...) (list argument ...)))
           (define (predicate object) (%record? type object))
           (define-record-accessors type field accessor modifier ...) ...))))

    ;; Collections stay in Scheme. Native handlers own allocation and individual
    ;; object accesses; they never need to call back into Scheme for map/equality.
    (define (not value) (if value #f #t))
    (define (list . elements) elements)
    (define (caar value) (car (car value)))
    (define (cadr value) (car (cdr value)))
    (define (cdar value) (cdr (car value)))
    (define (cddr value) (cdr (cdr value)))

    (define (list? value)
      (let loop ((slow value) (fast value))
        (cond ((null? fast) #t)
              ((not (pair? fast)) #f)
              ((null? (cdr fast)) #t)
              ((not (pair? (cdr fast))) #f)
              (else (let ((slow (cdr slow)) (fast (cddr fast)))
                      (and (not (eq? slow fast)) (loop slow fast)))))))

    (define (reverse elements)
      (let loop ((elements elements) (result '()))
        (if (null? elements) result (loop (cdr elements) (cons (car elements) result)))))

    (define (append . lists)
      (define (copy-prefix elements tail)
        (if (null? elements) tail (cons (car elements) (copy-prefix (cdr elements) tail))))
      (let loop ((lists lists))
        (cond ((null? lists) '())
              ((null? (cdr lists)) (car lists))
              (else (copy-prefix (car lists) (loop (cdr lists)))))))

    (define (length elements)
      (let loop ((elements elements) (size 0))
        (if (null? elements) size (loop (cdr elements) (+ size 1)))))

    (define (list-tail elements index)
      (if (not (and (exact-integer? index) (>= index 0)))
          (error "list-tail: expected nonnegative exact index" index))
      (if (= index 0) elements (list-tail (cdr elements) (- index 1))))

    (define (list-ref elements index) (car (list-tail elements index)))

    (define (make-list size . optional)
      (if (not (and (exact-integer? size) (>= size 0)))
          (error "make-list: expected nonnegative exact length" size))
      (let ((fill (if (null? optional) #f (car optional))))
        (let loop ((size size) (result '()))
          (if (= size 0) result (loop (- size 1) (cons fill result))))))

    (define (member-by compare value elements)
      (cond ((null? elements) #f)
            ((compare value (car elements)) elements)
            (else (member-by compare value (cdr elements)))))

    (define (member value elements . optional)
      (member-by (if (null? optional) equal? (car optional)) value elements))
    (define (memq value elements) (member-by eq? value elements))
    (define (memv value elements) (member-by eqv? value elements))

    (define (assoc-by compare key entries)
      (cond ((null? entries) #f)
            ((compare key (caar entries)) (car entries))
            (else (assoc-by compare key (cdr entries)))))

    (define (assoc key entries . optional)
      (assoc-by (if (null? optional) equal? (car optional)) key entries))
    (define (assq key entries) (assoc-by eq? key entries))
    (define (assv key entries) (assoc-by eqv? key entries))

    (define (some-empty? lists)
      (and (pair? lists) (or (null? (car lists)) (some-empty? (cdr lists)))))

    (define (map-one procedure elements)
      (if (null? elements) '()
          (cons (procedure (car elements)) (map-one procedure (cdr elements)))))

    (define (map procedure first . rest)
      (let loop ((lists (cons first rest)))
        (if (some-empty? lists) '()
            (cons (apply procedure (map-one car lists)) (loop (map-one cdr lists))))))

    (define (for-each procedure first . rest)
      (let loop ((lists (cons first rest)))
        (if (not (some-empty? lists))
            (begin (apply procedure (map-one car lists)) (loop (map-one cdr lists))))))

    (define (indexed->list size ref object)
      (let loop ((index (- size 1)) (result '()))
        (if (< index 0) result (loop (- index 1) (cons (ref object index) result)))))

    (define (vector->list object) (indexed->list (vector-length object) vector-ref object))
    (define (list->vector elements) (apply vector elements))
    (define (string->list object) (indexed->list (string-length object) string-ref object))
    (define (list->string elements) (apply string elements))

    ;; Track already compared pairs of containers, including user-created cycles.
    (define (equal? left right)
      (define (seen? left right seen)
        (and (pair? seen)
             (or (and (eq? left (caar seen)) (eq? right (cdar seen)))
                 (seen? left right (cdr seen)))))
      (define (indexed-equal? left right length ref seen)
        (and (= (length left) (length right))
             (let loop ((index 0))
               (or (= index (length left))
                   (and (compare (ref left index) (ref right index) seen)
                        (loop (+ index 1)))))))
      (define (compare left right seen)
        (cond ((eqv? left right) #t)
              ((seen? left right seen) #t)
              ((and (pair? left) (pair? right))
               (let ((seen (cons (cons left right) seen)))
                 (and (compare (car left) (car right) seen)
                      (compare (cdr left) (cdr right) seen))))
              ((and (string? left) (string? right)) (string=? left right))
              ((and (vector? left) (vector? right))
               (indexed-equal? left right vector-length vector-ref (cons (cons left right) seen)))
              ((and (bytevector? left) (bytevector? right))
               (indexed-equal? left right bytevector-length bytevector-u8-ref seen))
              (else #f)))
      (compare left right '()))

    (define (zero? value) (= value 0))
    (define (positive? value) (> value 0))
    (define (negative? value) (< value 0))
    (define (abs value) (if (< value 0) (- value) value))

    ;; Parameterization supports normal returns, including multiple values.
    ;; Nonlocal exits require dynamic-wind and are outside this bootstrap subset.
    ;; The private key permits conversion before entering the dynamic extent and
    ;; restoration without converting the old value a second time.
    (define parameter-key (cons 'parameter '()))

    (define (parameter-accessor get put convert)
      (lambda arguments
        (cond ((null? arguments) (get))
              ((null? (cdr arguments)) (put (convert (car arguments))))
              ((eq? (car arguments) parameter-key)
               (case (cadr arguments)
                 ((convert) (convert (car (cddr arguments))))
                 ((restore) (put (car (cddr arguments))))
                 (else (error "invalid internal parameter operation"))))
              (else (error "invalid parameter arguments" arguments)))))

    (define (make-parameter initial . optional)
      (let* ((convert (if (null? optional) (lambda (value) value) (car optional)))
             (value (convert initial)))
        (parameter-accessor (lambda () value) (lambda (new) (set! value new)) convert)))

    (define (identity value) value)
    (define current-input-port
      (parameter-accessor %current-input-port %set-current-input-port! identity))
    (define current-output-port
      (parameter-accessor %current-output-port %set-current-output-port! identity))
    (define current-error-port
      (parameter-accessor %current-error-port %set-current-error-port! identity))

    (define (call-with-parameterization bindings thunk)
      (let ((converted (map (lambda (binding)
                              (cons (car binding)
                                    ((car binding) parameter-key 'convert (cdr binding))))
                            bindings))
            (saved (map (lambda (binding) (cons (car binding) ((car binding))))
                        bindings)))
        (for-each (lambda (binding) ((car binding) parameter-key 'restore (cdr binding))) converted)
        (call-with-values thunk
          (lambda results
            (for-each (lambda (binding) ((car binding) parameter-key 'restore (cdr binding)))
                      (reverse saved))
            (apply values results)))))

    (define-syntax parameterize
      (syntax-rules ()
        ((_ (binding ...) body ...)
         (parameterize "collect" (binding ...) () (lambda () body ...)))
        ((_ "collect" () (binding ...) thunk)
         (call-with-parameterization (list binding ...) thunk))
        ((_ "collect" ((parameter value) remaining ...) (binding ...) thunk)
         (let ((target parameter) (replacement value))
           (parameterize "collect" (remaining ...)
                         (binding ... (cons target replacement)) thunk)))))

    (define close-input-port close-port)
    (define close-output-port close-port)
    (define (call-with-port port procedure)
      (call-with-values (lambda () (procedure port))
        (lambda results (close-port port) (apply values results))))))
