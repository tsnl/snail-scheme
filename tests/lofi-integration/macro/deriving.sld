(define-library (macro deriving)
  (export derive-reader derive-names define-named derive-instance read-derived
          derive-type-key ImportedName)
  (import
   (lofi core)
   (only (lofi base) i32-add string-append))
  (begin
    (data ImportedName ()
      (imported-name))
    (def private-increment (-> I32 I32) (lambda (value) (i32-add value 1)))
    (typeclass Readable (T)
               (: read-derived (-> T I32)))
    (def derive-instance
         (syntax-rules (data)
           ((_ (data Name ()
                 (constructor
                  (field Type accessor))))
            (instance derived-reader (Readable Name)
                      (read-derived (lambda (value) (private-increment (accessor value))))))))
    (def derive-reader
         (syntax-rules (data)
           ((_ (data Name ()
                 (constructor
                  (reader Type accessor))))
            (begin
              (def reader (-> Name Type)
                   (lambda (value) (private-increment (accessor value))))))))
    (def named-description
         (syntax-rules ()
           ((_ Name constructor field accessor)
            (string-append (library-name) "/" (identifier-name Name) "/"
                           (identifier-name constructor) "/" (identifier-name field) "/"
                           (identifier-name accessor)))))
    (def derive-names
         (syntax-rules (data)
           ((_ (data Name ()
                 (constructor
                  (field Type accessor))))
            (def field String (named-description Name constructor field accessor)))))
    (def derive-type-key
         (syntax-rules (data)
           ((_ (data Name (parameter ...)
                 (constructor
                  (field Type accessor))))
            (def field String (type-name Name)))))
    (def define-named
         (syntax-rules ()
           ((_ Name constructor field accessor)
            (data Name ()
              (constructor
               (field I32 accessor))
              (deriving derive-names)))))))
