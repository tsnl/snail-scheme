;; Functional tree composition. Only an element's procedure-valued type runs;
;; labels, payloads, and leaves otherwise remain ordinary Scheme values.
(define-library (snail-scheme react)
  (export element element? element-type element-data element-children
          fragment fragment? fragment-children resolve)
  (import (scheme base))
  (begin
    ;; Descriptions have no setters. Treat their contents as immutable, finite,
    ;; and acyclic; each component expansion must eventually terminate.
    (define-record-type <element>
      (make-element type data children)
      element?
      (type element-type)
      (data element-data)
      (children element-children))

    (define-record-type <fragment>
      (make-fragment children)
      fragment?
      (children fragment-children))

    (define (element type data . children)
      (make-element type data children))

    (define (fragment . children)
      (make-fragment children))

    ;; Resolution returns a forest of elements and opaque leaf values. Explicit
    ;; fragments splice siblings; a list or #f in a leaf position is just data.
    ;; Completed siblings accumulate in reverse order, avoiding repeated copies
    ;; through nested fragments. Components run depth-first, left-to-right.
    (define (resolve description)
      (reverse (resolve-into description '())))

    (define (resolve-into description reversed)
      (cond
       ((fragment? description)
        (resolve-children (fragment-children description) reversed))
       ((element? description) (resolve-element description reversed))
       (else (cons description reversed))))

    (define (resolve-children children reversed)
      (let loop ((children children) (reversed reversed))
        (if (null? children) reversed
            (loop (cdr children) (resolve-into (car children) reversed)))))

    (define (resolve-element description reversed)
      (let ((type (element-type description))
            (data (element-data description))
            (children (element-children description)))
        (if (procedure? type)
            (resolve-into (type data children) reversed)
            (cons (make-element type data (reverse (resolve-children children '())))
                  reversed))))))
