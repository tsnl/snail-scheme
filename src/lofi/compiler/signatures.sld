;; Declared signatures retain opaque quantified identities until inference.
;; This module contains no gradual Scheme types or runtime type operations.
(define-library (lofi compiler signatures)
  (export make-type-variable type-variable? type-variable-name type-variable-loc
          arrow-type? make-all-signature all-signature?
          signature-variables signature-requirements signature-type type-arguments)
  (import
   (scheme base)
   (scheme cxr))
  (begin

    ;; ---- Declared types ----

    (define-record-type <type-variable>
      (new-type-variable name loc) type-variable?
      (name type-variable-name)
      (loc type-variable-loc))
    (define (make-type-variable name . location)
      (new-type-variable name (and (pair? location) (car location))))
    (define (arrow-type? type) (and (pair? type) (eq? (car type) '->)))
    ;; Ordinary types are unquantified signatures. All always carries the same
    ;; three fields; an omitted requires clause contributes an empty list.
    (define (make-all-signature variables requirements type)
      (list 'All variables requirements type))
    (define (all-signature? signature) (and (pair? signature) (eq? (car signature) 'All)))
    (define (signature-variables signature) (if (all-signature? signature) (cadr signature) '()))
    (define (signature-requirements signature) (if (all-signature? signature) (caddr signature) '()))
    (define (signature-type signature) (if (all-signature? signature) (cadddr signature) signature))
    (define (type-arguments type) (reverse (cdr (reverse (cdr type)))))))
