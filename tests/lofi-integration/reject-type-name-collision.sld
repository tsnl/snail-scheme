(import
 (lofi core))

(def define-private
     (syntax-rules ()
       ((_ name)
        (library-begin
         (data Private ()
           (private))
         (def name String (type-name Private))))))
(define-private first)
(define-private second)
42
