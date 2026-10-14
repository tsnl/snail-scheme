;; Canonical paraffins control flow, partitions and accumulation order from
;; r7rs-benchmarks 85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1. Tagged H/C and
;; BCP/CCP vectors become closed immutable variants; numeric partition vectors
;; and the two-list result retain their original homogeneous representation.
(import (snail strict))
(define-data Radical (H) (C (first Radical) (second Radical) (third Radical)))
(define-data Paraffin
  (BCP (first Radical) (second Radical))
  (CCP (first Radical) (second Radical) (third Radical) (fourth Radical)))
(define (max a b) (if (> a b) a b))
(define (list-length xs) (if (null? xs) 0 (+ 1 (list-length (cdr xs)))))
(define (gen n)
  (let* ((n/2 (quotient n 2))
         (radicals (make-vector (+ n/2 1) (cons (H) '()))))

    (define (rads-of-size n)
      (let loop1 ((ps
                   (three-partitions (- n 1)))
                  (lst
                   '()))
        (if (null? ps)
            lst
            (let* ((p (car ps))
                   (nc1 (vector-ref p 0))
                   (nc2 (vector-ref p 1))
                   (nc3 (vector-ref p 2)))
              (let loop2 ((rads1
                           (vector-ref radicals nc1))
                          (lst
                           (loop1 (cdr ps)
                                  lst)))
                (if (null? rads1)
                    lst
                    (let loop3 ((rads2
                                 (if (= nc1 nc2)
                                     rads1
                                     (vector-ref radicals nc2)))
                                (lst
                                 (loop2 (cdr rads1)
                                        lst)))
                      (if (null? rads2)
                          lst
                          (let loop4 ((rads3
                                       (if (= nc2 nc3)
                                           rads2
                                           (vector-ref radicals nc3)))
                                      (lst
                                       (loop3 (cdr rads2)
                                              lst)))
                            (if (null? rads3)
                                lst
                                (cons (C
                                       (car rads1)
                                       (car rads2)
                                       (car rads3))
                                      (loop4 (cdr rads3)
                                             lst))))))))))))

    (define (bcp-generator j)
      (if (not (= (remainder j 2) 0))
          '()
          (let loop1 ((rads1
                       (vector-ref radicals (quotient j 2)))
                      (lst
                       '()))
            (if (null? rads1)
                lst
                (let loop2 ((rads2
                             rads1)
                            (lst
                             (loop1 (cdr rads1)
                                    lst)))
                  (if (null? rads2)
                      lst
                      (cons (BCP
                             (car rads1)
                             (car rads2))
                            (loop2 (cdr rads2)
                                   lst))))))))

    (define (ccp-generator j)
      (let loop1 ((ps
                   (four-partitions (- j 1)))
                  (lst
                   '()))
        (if (null? ps)
            lst
            (let* ((p (car ps))
                   (nc1 (vector-ref p 0))
                   (nc2 (vector-ref p 1))
                   (nc3 (vector-ref p 2))
                   (nc4 (vector-ref p 3)))
              (let loop2 ((rads1
                           (vector-ref radicals nc1))
                          (lst
                           (loop1 (cdr ps)
                                  lst)))
                (if (null? rads1)
                    lst
                    (let loop3 ((rads2
                                 (if (= nc1 nc2)
                                     rads1
                                     (vector-ref radicals nc2)))
                                (lst
                                 (loop2 (cdr rads1)
                                        lst)))
                      (if (null? rads2)
                          lst
                          (let loop4 ((rads3
                                       (if (= nc2 nc3)
                                           rads2
                                           (vector-ref radicals nc3)))
                                      (lst
                                       (loop3 (cdr rads2)
                                              lst)))
                            (if (null? rads3)
                                lst
                                (let loop5 ((rads4
                                             (if (= nc3 nc4)
                                                 rads3
                                                 (vector-ref radicals nc4)))
                                            (lst
                                             (loop4 (cdr rads3)
                                                    lst)))
                                  (if (null? rads4)
                                      lst
                                      (cons (CCP
                                             (car rads1)
                                             (car rads2)
                                             (car rads3)
                                             (car rads4))
                                            (loop5 (cdr rads4)
                                                   lst))))))))))))))

    (let loop ((i 1))
      (if (> i n/2)
          (vector (bcp-generator n)
                  (ccp-generator n))
          (begin
            (vector-set! radicals i (rads-of-size i))
            (loop (+ i 1)))))))

(define (three-partitions m)
  (let loop1 ((lst '())
              (nc1 (quotient m 3)))
    (if (< nc1 0)
        lst
        (let loop2 ((lst lst)
                    (nc2 (quotient (- m nc1) 2)))
          (if (< nc2 nc1)
              (loop1 lst
                     (- nc1 1))
              (loop2 (cons (vector nc1 nc2 (- m (+ nc1 nc2))) lst)
                     (- nc2 1)))))))

(define (four-partitions m)
  (let loop1 ((lst '())
              (nc1 (quotient m 4)))
    (if (< nc1 0)
        lst
        (let loop2 ((lst lst)
                    (nc2 (quotient (- m nc1) 3)))
          (if (< nc2 nc1)
              (loop1 lst
                     (- nc1 1))
              (let ((start (max nc2 (- (quotient (+ m 1) 2) (+ nc1 nc2)))))
                (let loop3 ((lst lst)
                            (nc3 (quotient (- m (+ nc1 nc2)) 2)))
                  (if (< nc3 start)
                      (loop2 lst (- nc2 1))
                      (loop3 (cons (vector nc1 nc2 nc3 (- m (+ nc1 (+ nc2 nc3)))) lst)
                             (- nc3 1))))))))))

(define (nb n)
  (let ((x (gen n)))
    (+ (list-length (vector-ref x 0))
       (list-length (vector-ref x 1)))))

(nb 10)
