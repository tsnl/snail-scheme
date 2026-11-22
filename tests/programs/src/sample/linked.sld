;; A library that links a file beside its own source. Importers get the
;; file's Resource, and a function that reads it.
(define-library (sample linked)
  (export
   greeting
   greeting-text)
  (import
   (snail core base)
   (snail shell resource))
  (begin

    (define (greeting) (→ Resource) (link-file "data/greeting.txt"))

    (define (greeting-text (resources Resources)) (→ String)
      (list->string
       (map (lambda (byte) (i32->char (u8->i32 byte)))
            (array->list (read-resource resources (greeting))))))

    ))
