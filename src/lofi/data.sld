;; Nominal types name a resolved declaration, never its spelling. The schema
;; remains shared static metadata; a runtime layout substitutes only its explicit
;; parameters. Following a field stops at the next nominal identity, so recursive
;; source types are finite values even when their layout graph contains cycles.
(define-library (lofi data)
  (export data-type data-type? data-type-schema data-case-fields data-tagged?
          data-constructor? data-constructor-schema data-constructor-index
          data-schema-bindings)
  (import (scheme base) (scheme cxr) (lofi types)
          (only (lofi ir)
                binding-kind binding-payload data-schema-definition
                data-schema-variables data-schema-cases))
  (begin

    ;; ---- Nominal applications and concrete field substitution ----

    (define (data-type definition arguments) (cons 'Data (cons definition arguments)))
    (define (data-type? type)
      (let ((type (resolve type))) (and (pair? type) (eq? (car type) 'Data))))
    (define (data-type-schema type) (binding-payload (cadr (resolve type))))
    (define (data-tagged? type)
      (pair? (cdr (data-schema-cases (data-type-schema type)))))
    (define (data-case-fields type index)
      (let* ((type (resolve type)) (schema (data-type-schema type))
             (mapping (map cons (data-schema-variables schema) (cddr type))))
        (map (lambda (field) (substitute (cadr field) mapping))
             (cadr (list-ref (data-schema-cases schema) index)))))

    ;; ---- Static constructor and accessor bindings ----

    (define (data-constructor? definition)
      (and (eq? (binding-kind definition) 'data)
           (eq? (car (binding-payload definition)) 'construct)))
    (define (data-constructor-schema definition) (cadr (binding-payload definition)))
    (define (data-constructor-index definition) (caddr (binding-payload definition)))
    (define (data-schema-bindings schema)
      (apply append
             (map (lambda (row)
                    (cons (car row)
                          (let collect ((fields (cadr row)))
                            (cond ((null? fields) '())
                                  ((caddar fields) (cons (caddar fields) (collect (cdr fields))))
                                  (else (collect (cdr fields)))))))
                  (data-schema-cases schema))))))
