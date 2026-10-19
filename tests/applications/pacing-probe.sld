;; Geometry observations come from the real seeded terrain. The host's paid
;; progression policy may ask about a tile only after colony sight reveals it.
(define-library (tests pacing-probe)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (siegework terrain)
   (only (lofi core) ann -> I32))
  (begin

    ;; ---- Scalar map observations ----

    (define (tile seed cell cleared)
      (let* ((x (index-x cell)) (y (index-y cell))
             (rate (if (and cleared (nest-site? seed x y)) nest-deposit-rate (deposit-rate seed x y))))
        (+ (* 10 rate)
           (if (ground? seed x y) 1 (if (water? seed x y) 2 0)))))
    (define (path-length path)
      (if (null? path) 0 (+ 1 (path-length (cdr path)))))
    (define (nest-route seed front)
      (path-length (walking-path seed (spawn-x seed) (spawn-y seed) (front-x seed front) (front-y seed front)
                                 (list (make-survey 64 64 128)) #f)))
    (define answer
      (ann (lambda (operation seed cell)
             (cond ((= operation 0) (tile seed cell #f))
                   ((= operation 1) (spawn-x seed))
                   ((= operation 2) (spawn-y seed))
                   ((= operation 3) (front-x seed cell))
                   ((= operation 4) (front-y seed cell))
                   ((= operation 5) (nest-route seed cell))
                   ((= operation 6) map-width)
                   ((= operation 7) map-height)
                   ((= operation 8) (deposit-capacity seed (index-x cell) (index-y cell)))
                   ;; The policy may use this only after observing a cleared nest.
                   ((= operation 9) (tile seed cell #t))
                   (else -1)))
           (-> I32 I32 I32 I32)))))
