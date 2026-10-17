(define-library (producer make)
  (import
   (lofi compiler-builder)
   (only (lofi primitive) cons empty-list))
  (export constant-library dependent-library importing-library ill-typed-library produce)
  (begin
    (def names
         (lambda (first second)
           (cons (builder-name first) (cons (builder-name second) (empty-list)))))
    (def exported-library
         (lambda (scope span body imports)
           (begin
             (let answer (binding scope (builder-name "answer") span))
             (lofi-library
              (names "descriptive" "result") scope imports
              (cons (library-export (builder-name "value") (local-reference answer span)) (empty-list))
              (cons (definition answer (function-type (empty-list) (type-i32)) body span) (empty-list)) span))))
    (def constant-library (-> I32 LofiLibrary)
         (lambda (value)
           (begin
             (let span (source-span (builder-name "generated-value.sld") 7 3))
             (let scope (library-scope))
             (exported-library scope span
                               (lambda-expression (nested-scope scope) (empty-list) (literal-i32 value span) span)
                               (empty-list)))))
    (def dependent-library (-> I32 LofiLibrary)
         (lambda (offset)
           (begin
             (let span (source-span (builder-name "generated-dependent.sld") 11 5))
             (let scope (library-scope))
             (let base (reference-expression (import-reference scope (builder-name "value") span)))
             (let add (reference-expression (import-reference scope (builder-name "add") span)))
             (let arguments (cons (application-expression base (empty-list) span)
                                  (cons (literal-i32 offset span) (empty-list))))
             (let imports (cons (library-import (names "generated" "support") (all-imports) scope span)
                                (cons (library-import (names "consumer" "arithmetic") (all-imports) scope span)
                                      (empty-list))))
             (exported-library scope span
                               (lambda-expression (nested-scope scope) (empty-list)
                                                  (application-expression add arguments span) span) imports))))
    (def importing-library (-> String String LofiLibrary)
         (lambda (first second)
           (begin
             (let span (source-span (builder-name "generated-import.sld") 17 9))
             (let scope (library-scope))
             (lofi-library (names "descriptive" "importer") scope
                           (cons (library-import (names first second) (all-imports) scope span) (empty-list))
                           (empty-list) (empty-list) span))))
    (def ill-typed-library (-> LofiLibrary)
         (lambda ()
           (begin
             (let span (source-span (builder-name "generated-invalid.sld") 19 4))
             (let scope (library-scope))
             (let answer (binding scope (builder-name "answer") span))
             (lofi-library (names "descriptive" "invalid") scope (empty-list) (empty-list)
                           (cons (definition answer (type-i32) (literal-bool #t span) span) (empty-list)) span))))
    (def produce (-> LofiLibrary) (lambda () (constant-library 42)))))
