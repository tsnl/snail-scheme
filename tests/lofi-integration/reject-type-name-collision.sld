(import
 (lofi core))

(define-syntax define-private
     (syntax-rules ()
       ((_ name)
        (begin
         (data Private ()
           (private))
         (def name String (type-name Private))))))
(define-private first)
(define-private second)
42
