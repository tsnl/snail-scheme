;; Declared signatures retain opaque quantified identities until inference.
;; This module contains no gradual Scheme types or runtime type operations.
(define-library (snail-sfir signatures)
  (export make-type-variable type-variable? type-variable-name
          arrow-type? all-type? all-variables all-body type-constraints type-arguments)
  (import (scheme base) (scheme cxr))
  (begin

    ;; ---- Declared types ----

    (define-record-type <type-variable>
      (make-type-variable name) type-variable? (name type-variable-name))
    (define (arrow-type? type) (and (pair? type) (eq? (car type) '->)))
    (define (all-type? type) (and (pair? type) (eq? (car type) 'All)))
    (define (all-variables type) (cadr type))
    (define (quantified-body type) (if (all-type? type) (caddr type) type))
    (define (qualified-type? type) (and (pair? type) (eq? (car type) '=>)))
    (define (all-body type)
      (let ((body (quantified-body type)))
        (if (qualified-type? body) (caddr body) body)))
    (define (type-constraints type)
      (let ((body (quantified-body type)))
        (if (qualified-type? body) (cadr body) '())))
    (define (type-arguments type) (reverse (cdr (reverse (cdr type)))))))
