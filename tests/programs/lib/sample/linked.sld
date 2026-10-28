;; A library that links a file beside its own source. Importers get the
;; file's Resource, and a function that reads it.
(define-library (sample linked)
  (export
   greeting
   greeting-text)
  (import
   (snail-core base)
   (snail-core resource))
  (begin

    (: greeting Resource)
    (define greeting (link-bytes "data/greeting.txt"))

    (: greeting-text (-> String ! resource))
    (define (greeting-text)
      (list->string (map (lambda (byte) (i32->char (u8->i32 byte)))
                         (vector->list (read-resource greeting)))))

    ))
