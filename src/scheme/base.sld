;; R7RS names for Snail-Core. Programs keep Snail-Core's types and fixed arities: a list
;; holds one type of element, `if` tests a Bool, and `car` of an empty list
;; panics. Chibi never loads this library; it is on Snail-Core's search path only.
(define-library (scheme base)
  (export
   define lambda if begin let let* letrec cond case when unless and or do
   define-syntax syntax-rules quote
   + - * / = < <= > >= quotient remainder modulo abs min max not
   cons car cdr null? pair? list length append reverse map for-each list-ref list-tail
   vector make-vector vector-ref vector-length vector->list list->vector
   string string-length string-ref string-append substring string=? string<?
   string->list list->string char->integer integer->char char=? char<?
   display newline write-string write-char)
  (import
   (snail core base)
   (snail core io))
  (begin

    ;; ---- Pairs ----

    (define (cons (head T) (tail (List T))) (→ (List T)) (∀ T)
      (Cons head tail))

    (define (car (items (List T))) (→ T) (∀ T) (⊨ (Copy T))
      (match items
        ((Cons head _) head)
        ((Nil) (panic "car of an empty list"))))

    (define (cdr (items (List T))) (→ (List T)) (∀ T) (⊨ (Copy T))
      (match items
        ((Cons _ tail) tail)
        ((Nil) (panic "cdr of an empty list"))))

    (define (pair? (items (List T))) (→ Bool) (∀ T) (⊨ (Copy T))
      (not (null? items)))

    ;; ---- Vectors and characters ----

    (define-syntax vector
      (syntax-rules ()
        ((_ item ...) (list->vector (list item ...)))))

    (define (char=? (a Char) (b Char)) (→ Bool)
      (= a b))

    (define (char<? (a Char) (b Char)) (→ Bool)
      (< a b))

    ))
