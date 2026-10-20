(import
 (lofi primitive))
(define-syntax bad (syntax-rules () ((_ value) (i32-add value #t))))
(bad 1)
