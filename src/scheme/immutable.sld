;; Functional record replacement over the common typed kernel.
(define-library (scheme immutable)
  (export define-immutable-record list append reverse)
  (import
   (scheme base)
   (only (lofi core) data deriving))
  (begin
    (define-syntax record-updaters
      (syntax-rules ()
        ((_ constructor (before ...) ()) (begin))
        ((_ constructor (before ...) ((field type getter replace)
                                      (rest-field rest-type rest-getter rest-replace) ...))
         (begin
           (define (replace record value)
             (constructor (before record) ... value (rest-getter record) ...))
           (record-updaters constructor (before ... getter)
                            ((rest-field rest-type rest-getter rest-replace) ...))))))
    (define-syntax define-immutable-record
      (syntax-rules (deriving)
        ((_ name constructor (field type getter replace) ... (deriving transformer ...))
         (begin
           (data name ()
             (constructor
              (field type getter) ...)
             (deriving transformer ...))
           (record-updaters constructor () ((field type getter replace) ...))))
        ((_ name constructor (field type getter replace) ...)
         (begin
           (data name ()
             (constructor
              (field type getter) ...))
           (record-updaters constructor () ((field type getter replace) ...))))))
    (define (append left right)
      (if (null? left) right (cons (car left) (append (cdr left) right))))
    (define (reverse source)
      (let loop ((source source) (result (empty-list)))
        (if (null? source) result (loop (cdr source) (cons (car source) result)))))))
