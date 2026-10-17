;; Functional record replacement over the common typed kernel.
(define-library (scheme immutable)
  (export define-immutable-record list append reverse)
  (import
   (scheme base)
   (only (lofi core) datatype library-begin))
  (begin
    (define-syntax record-updaters
      (syntax-rules ()
        ((_ constructor (before ...) ()) (library-begin))
        ((_ constructor (before ...) ((field type getter replace)
                                      (rest-field rest-type rest-getter rest-replace) ...))
         (library-begin
          (define (replace record value)
            (constructor (before record) ... value (rest-getter record) ...))
          (record-updaters constructor (before ... getter)
                           ((rest-field rest-type rest-getter rest-replace) ...))))))
    (define-syntax define-immutable-record
      (syntax-rules ()
        ((_ name constructor (field type getter replace) ...)
         (library-begin
          (define name (datatype ()
                         (constructor
                          (field type getter) ...)))
          (record-updaters constructor () ((field type getter replace) ...))))))
    (define-syntax list
      (syntax-rules () ((_) (empty-list)) ((_ first rest ...) (cons first (list rest ...)))))
    (define (append left right)
      (if (null? left) right (cons (car left) (append (cdr left) right))))
    (define (reverse source)
      (let loop ((source source) (result (empty-list)))
        (if (null? source) result (loop (cdr source) (cons (car source) result)))))))
