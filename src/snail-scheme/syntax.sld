(define-library (snail-scheme syntax)
  (export
   syntax?
   syntax-loc
   syntax-identifier?
   syntax->datum
   <list-syntax>
   make-list-syntax
   list-syntax?
   list-syntax-elements
   list-syntax-improper-tail
   list-syntax-loc
   <vector-syntax>
   make-vector-syntax
   vector-syntax?
   vector-syntax-elements
   vector-syntax-loc
   <atom-syntax>
   make-atom-syntax
   atom-syntax?
   atom-syntax-value
   atom-syntax-loc)

  (import
   (scheme base))

  (begin
    (define (syntax? obj)
      (or
       (list-syntax? obj)
       (vector-syntax? obj)
       (atom-syntax? obj)))

    (define (syntax-loc stx)
      (cond
       ((list-syntax? stx)
        (list-syntax-loc stx))
       ((vector-syntax? stx)
        (vector-syntax-loc stx))
       ((atom-syntax? stx)
        (atom-syntax-loc stx))
       (else
        (error "syntax-loc expected syntax object" stx))))

    (define-record-type <list-syntax>
      (make-list-syntax
       elements ; list of syntax objects
       improper-tail ; null or a syntax object representing the improper tail
       loc) ; location of the opening fence
      list-syntax?
      (elements list-syntax-elements)
      (improper-tail list-syntax-improper-tail)
      (loc list-syntax-loc))

    (define-record-type <vector-syntax>
      (make-vector-syntax
       elements ; list of syntax objects
       loc) ; location of the # prefix
      vector-syntax?
      (elements vector-syntax-elements)
      (loc vector-syntax-loc))

    (define-record-type <atom-syntax>
      (make-atom-syntax
       value ; decoded terminal value
       loc) ; loc indicating the start of this syntax object
      atom-syntax?
      (value atom-syntax-value)
      (loc atom-syntax-loc))

    (define (syntax-identifier? stx)
      (and (atom-syntax? stx) (symbol? (atom-syntax-value stx))))

    (define (syntax->datum stx)
      (cond
       ((atom-syntax? stx) (atom-syntax-value stx))
       ((vector-syntax? stx)
        (list->vector (map syntax->datum (vector-syntax-elements stx))))
       (else
        (let ((elements (map syntax->datum (list-syntax-elements stx)))
              (tail (list-syntax-improper-tail stx)))
          (append elements (if (null? tail) '() (syntax->datum tail)))))))

    ))
