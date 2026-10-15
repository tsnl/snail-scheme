; Original ten primitive type environments; constructor recipes are data.
(define misc-env
  (list
   (cons 'quote (forall (lambda (tv) tv)))
   (cons 'eqv? (forall (lambda (tv) (procedure (convert-tvars (list tv tv))
                                               (boolean)))))
   (cons 'eq? (forall (lambda (tv) (procedure (convert-tvars (list tv tv))
                                              (boolean)))))
   (cons 'equal? (forall (lambda (tv) (procedure (convert-tvars (list tv tv))
                                                 (boolean)))))
   ))

;; type environment for input/output

(define io-env
  (list
   (cons 'open-input-file (procedure (convert-tvars (list (charseq))) dynamic))
   (cons 'eof-object? (procedure (convert-tvars (list dynamic)) (boolean)))
   (cons 'read (forall (lambda (tv)
                         (procedure (convert-tvars (list tv)) dynamic))))
   (cons 'write (forall (lambda (tv)
                          (procedure (convert-tvars (list tv)) dynamic))))
   (cons 'display (forall (lambda (tv)
                            (procedure (convert-tvars (list tv)) dynamic))))
   (cons 'newline (procedure (null) dynamic))
   (cons 'pretty-print (forall (lambda (tv)
                                 (procedure (convert-tvars (list tv)) dynamic))))))


;; type environment for Booleans

(define boolean-env
  (list
   (cons 'boolean? (forall (lambda (tv)
                             (procedure (convert-tvars (list tv)) (boolean)))))
   ;;(cons #f (boolean))
   ;; #f doesn't exist in Chez Scheme, but gets mapped to null!
   (cons #t (boolean))
   (cons 'not (procedure (convert-tvars (list (boolean))) (boolean)))
   ))


;; type environment for pairs and lists

(define (list-type tv)
  (fix (lambda (tv2) (pair tv tv2))))

(define list-env
  (list
   (cons 'pair? (forall2 (lambda (tv1 tv2)
                           (procedure (convert-tvars (list (pair tv1 tv2)))
                                      (boolean)))))
   (cons 'null? (forall2 (lambda (tv1 tv2)
                           (procedure (convert-tvars (list (pair tv1 tv2)))
                                      (boolean)))))
   (cons 'list? (forall2 (lambda (tv1 tv2)
                           (procedure (convert-tvars (list (pair tv1 tv2)))
                                      (boolean)))))
   (cons 'cons (forall2 (lambda (tv1 tv2)
                          (procedure (convert-tvars (list tv1 tv2))
                                     (pair tv1 tv2)))))
   (cons 'car (forall2 (lambda (tv1 tv2)
                         (procedure (convert-tvars (list (pair tv1 tv2)))
                                    tv1))))
   (cons 'cdr (forall2 (lambda (tv1 tv2)
                         (procedure (convert-tvars (list (pair tv1 tv2)))
                                    tv2))))
   (cons 'set-car! (forall2 (lambda (tv1 tv2)
                              (procedure (convert-tvars (list (pair tv1 tv2)
                                                              tv1))
                                         dynamic))))
   (cons 'set-cdr! (forall2 (lambda (tv1 tv2)
                              (procedure (convert-tvars (list (pair tv1 tv2)
                                                              tv2))
                                         dynamic))))
   (cons 'caar (forall3 (lambda (tv1 tv2 tv3)
                          (procedure (convert-tvars
                                      (list (pair (pair tv1 tv2) tv3)))
                                     tv1))))
   (cons 'cdar (forall3 (lambda (tv1 tv2 tv3)
                          (procedure (convert-tvars
                                      (list (pair (pair tv1 tv2) tv3)))
                                     tv2))))

   (cons 'cadr (forall3 (lambda (tv1 tv2 tv3)
                          (procedure (convert-tvars
                                      (list (pair tv1 (pair tv2 tv3))))
                                     tv2))))
   (cons 'cddr (forall3 (lambda (tv1 tv2 tv3)
                          (procedure (convert-tvars
                                      (list (pair tv1 (pair tv2 tv3))))
                                     tv3))))
   (cons 'caaar (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair (pair (pair tv1 tv2) tv3) tv4)))
                              tv1))))
   (cons 'cdaar (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair (pair (pair tv1 tv2) tv3) tv4)))
                              tv2))))
   (cons 'cadar (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair (pair tv1 (pair tv2 tv3)) tv4)))
                              tv2))))
   (cons 'cddar (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair (pair tv1 (pair tv2 tv3)) tv4)))
                              tv3))))
   (cons 'caadr (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair tv1 (pair (pair tv2 tv3) tv4))))
                              tv2))))
   (cons 'cdadr (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair tv1 (pair (pair tv2 tv3) tv4))))
                              tv3))))
   (cons 'caddr (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair tv1 (pair tv2 (pair tv3 tv4)))))
                              tv3))))
   (cons 'cdddr (forall4
                 (lambda (tv1 tv2 tv3 tv4)
                   (procedure (convert-tvars
                               (list (pair tv1 (pair tv2 (pair tv3 tv4)))))
                              tv4))))
   (cons 'cadddr
         (forall5 (lambda (tv1 tv2 tv3 tv4 tv5)
                    (procedure (convert-tvars
                                (list (pair tv1
                                            (pair tv2
                                                  (pair tv3
                                                        (pair tv4 tv5))))))
                               tv4))))
   (cons 'cddddr
         (forall5 (lambda (tv1 tv2 tv3 tv4 tv5)
                    (procedure (convert-tvars
                                (list (pair tv1
                                            (pair tv2
                                                  (pair tv3
                                                        (pair tv4 tv5))))))
                               tv5))))
   (cons 'list (forall (lambda (tv)
                         (procedure tv tv))))
   (cons 'length (forall (lambda (tv)
                           (procedure (convert-tvars (list (list-type tv)))
                                      (number)))))
   (cons 'append (forall (lambda (tv)
                           (procedure (convert-tvars (list (list-type tv)
                                                           (list-type tv)))
                                      (list-type tv)))))
   (cons 'reverse (forall (lambda (tv)
                            (procedure (convert-tvars (list (list-type tv)))
                                       (list-type tv)))))
   (cons 'list-ref (forall (lambda (tv)
                             (procedure (convert-tvars (list (list-type tv)
                                                             (number)))
                                        tv))))
   (cons 'memq (forall (lambda (tv)
                         (procedure (convert-tvars (list tv
                                                         (list-type tv)))
                                    (boolean)))))
   (cons 'memv (forall (lambda (tv)
                         (procedure (convert-tvars (list tv
                                                         (list-type tv)))
                                    (boolean)))))
   (cons 'member (forall (lambda (tv)
                           (procedure (convert-tvars (list tv
                                                           (list-type tv)))
                                      (boolean)))))
   (cons 'assq (forall2 (lambda (tv1 tv2)
                          (procedure (convert-tvars
                                      (list tv1
                                            (list-type (pair tv1 tv2))))
                                     (pair tv1 tv2)))))
   (cons 'assv (forall2 (lambda (tv1 tv2)
                          (procedure (convert-tvars
                                      (list tv1
                                            (list-type (pair tv1 tv2))))
                                     (pair tv1 tv2)))))
   (cons 'assoc (forall2 (lambda (tv1 tv2)
                           (procedure (convert-tvars
                                       (list tv1
                                             (list-type (pair tv1 tv2))))
                                      (pair tv1 tv2)))))
   ))


(define symbol-env
  (list
   (cons 'symbol? (forall (lambda (tv)
                            (procedure (convert-tvars (list tv)) (boolean)))))
   (cons 'symbol->string (procedure (convert-tvars (list (symbol))) (charseq)))
   (cons 'string->symbol (procedure (convert-tvars (list (charseq))) (symbol)))
   ))

(define number-env
  (list
   (cons 'number? (forall (lambda (tv)
                            (procedure (convert-tvars (list tv)) (boolean)))))
   (cons '+ (procedure (convert-tvars (list (number) (number))) (number)))
   (cons '- (procedure (convert-tvars (list (number) (number))) (number)))
   (cons '* (procedure (convert-tvars (list (number) (number))) (number)))
   (cons '/ (procedure (convert-tvars (list (number) (number))) (number)))
   (cons 'number->string (procedure (convert-tvars (list (number))) (charseq)))
   (cons 'string->number (procedure (convert-tvars (list (charseq))) (number)))
   ))

(define char-env
  (list
   (cons 'char? (forall (lambda (tv)
                          (procedure (convert-tvars (list tv)) (boolean)))))
   (cons 'char->integer (procedure (convert-tvars (list (character)))
                                   (number)))
   (cons 'integer->char (procedure (convert-tvars (list (number)))
                                   (character)))
   ))

(define string-env
  (list
   (cons 'string? (forall (lambda (tv)
                            (procedure (convert-tvars (list tv)) (boolean)))))
   ))

(define vector-env
  (list
   (cons 'vector? (forall (lambda (tv)
                            (procedure (convert-tvars (list tv)) (boolean)))))
   (cons 'make-vector (forall (lambda (tv)
                                (procedure (convert-tvars (list (number)))
                                           (array tv)))))
   (cons 'vector-length (forall (lambda (tv)
                                  (procedure (convert-tvars (list (array tv)))
                                             (number)))))
   (cons 'vector-ref (forall (lambda (tv)
                               (procedure (convert-tvars (list (array tv)
                                                               (number)))
                                          tv))))
   (cons 'vector-set! (forall (lambda (tv)
                                (procedure (convert-tvars (list (array tv)
                                                                (number)
                                                                tv))
                                           dynamic))))
   ))

(define procedure-env
  (list
   (cons 'procedure? (forall (lambda (tv)
                               (procedure (convert-tvars (list tv)) (boolean)))))
   (cons 'map (forall2 (lambda (tv1 tv2)
                         (procedure (convert-tvars
                                     (list (procedure (convert-tvars
                                                       (list tv1)) tv2)
                                           (list-type tv1)))
                                    (list-type tv2)))))
   (cons 'foreach (forall2 (lambda (tv1 tv2)
                             (procedure (convert-tvars
                                         (list (procedure (convert-tvars
                                                           (list tv1)) tv2)
                                               (list-type tv1)))
                                        (list-type tv2)))))
   (cons 'call-with-current-continuation
         (forall2 (lambda (tv1 tv2)
                    (procedure (convert-tvars
                                (list (procedure
                                       (convert-tvars
                                        (list (procedure (convert-tvars
                                                          (list tv1)) tv2)))
                                       tv2)))
                               tv2))))
   ))


