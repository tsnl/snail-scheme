;; The types a host and its plugin share: a static import gives both the
;; one declaration, so a value crosses between them by reference.
(define-library (project)
  (export
   Project
   Project-name
   Project-owner
   Project-estimates
   Report
   Report-name
   Report-tasks
   Report-days)
  (import
   (snail-core base))
  (begin

    (struct Project
      ((name String)
       (owner String)
       (estimates (List I64))))

    (struct Report
      ((name String)
       (tasks I64)
       (days I64)))))
