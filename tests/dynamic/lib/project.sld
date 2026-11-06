;; The types a host and its plugin share: a static import gives both the
;; one declaration, so a value crosses between them by reference.
(define-library (project)
  (export
   Project
   Report)
  (import
   (snail core base))
  (begin

    (struct Project
      ((name String)
       (owner String)
       (estimates (List I64))))

    (struct Report
      ((name String)
       (tasks I64)
       (days I64)))))
