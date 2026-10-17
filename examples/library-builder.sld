;; A compiled Lofi function returns structured library syntax through a builder.
(define-library (builder example)
  (import
   (lofi compiler-builder)
   (only (lofi primitive) cons empty-list))
  (export build)
  (begin
    (def produce (-> LofiLibrary)
         (lambda ()
           (begin
             (let span (source-span (builder-name "generated-answer.sld") (ann 1 I32) (ann 1 I32)))
             (let scope (library-scope))
             (let answer (binding scope (builder-name "answer") span))
             (let body (lambda-expression (nested-scope scope) (empty-list) (literal-i32 (ann 42 I32) span) span))
             (lofi-library
              (cons (builder-name "generated") (cons (builder-name "answer") (empty-list))) scope (empty-list)
              (cons (library-export (builder-name "run") (local-reference answer span)) (empty-list))
              (cons (definition answer (function-type (empty-list) (type-i32)) body span) (empty-list)) span))))
    ;; The driver uses this scalar wrapper; produce itself returns LofiLibrary.
    (def build (-> I64) (lambda () (library-token (produce))))))
