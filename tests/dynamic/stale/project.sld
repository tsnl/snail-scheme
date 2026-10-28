;; The shared library as an older build of the plugin saw it, before
;; Project had an owner. A plugin built from it has another TypeId for
;; Project, so the host refuses its function before calling it.
(define-library (project)
  (export
   Project
   Project-name
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
       (estimates (List I64))))

    (struct Report
      ((name String)
       (tasks I64)
       (days I64)))))
