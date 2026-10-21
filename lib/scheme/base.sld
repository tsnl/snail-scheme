;; R7RS names for Lofi. Programs keep Lofi's types and fixed arities: a list
;; holds one type of element, `if` tests a Bool, and `car` of an empty list
;; panics. Chibi never loads this library; it is on Lofi's search path only.
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
   (lofi base)
   (lofi io))
  (begin

    ;; ---- Pairs ----

    (: cons (All (T) (-> T (List T) (List T))))
    (define (cons head tail)
      (Cons head tail))

    (: car (All (T) (-> (List T) T)))
    (define (car items)
      (match items
        ((Cons head _) head)
        ((Nil) (panic "car of an empty list"))))

    (: cdr (All (T) (-> (List T) (List T))))
    (define (cdr items)
      (match items
        ((Cons _ tail) tail)
        ((Nil) (panic "cdr of an empty list"))))

    (: pair? (All (T) (-> (List T) Bool)))
    (define (pair? items)
      (not (null? items)))

    ;; ---- Vectors and characters ----

    (define-syntax vector
      (syntax-rules ()
        ((_ item ...) (list->vector (list item ...)))))

    (: char=? (-> Char Char Bool))
    (define (char=? a b)
      (= a b))

    (: char<? (-> Char Char Bool))
    (define (char<? a b)
      (< a b))

    ))
