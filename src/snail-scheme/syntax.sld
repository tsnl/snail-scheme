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
   list-syntax-prefix
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
       (atom-syntax? obj)))

    (define (syntax-loc stx)
      (cond
       ((list-syntax? stx)
        (list-syntax-loc stx))
       ((atom-syntax? stx)
        (atom-syntax-loc stx))
       (else
        (error "syntax-loc expected syntax object" stx))))

    (define-record-type <list-syntax>
      (make-list-syntax
       elements ; list of syntax objects
       improper-tail ; null or a syntax object representing the improper tail
       loc ; location of the prefix or opening fence
       prefix) ; () for lists or "#" for vectors
      list-syntax?
      (elements list-syntax-elements)
      (improper-tail list-syntax-improper-tail)
      (loc list-syntax-loc)
      (prefix list-syntax-prefix))

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
      (if (atom-syntax? stx)
          (atom-syntax-value stx)
          (let ((elements (map syntax->datum (list-syntax-elements stx)))
                (tail (list-syntax-improper-tail stx)))
            (if (equal? (list-syntax-prefix stx) "#")
                (list->vector elements)
                (append elements (if (null? tail) '() (syntax->datum tail)))))))

    ))
