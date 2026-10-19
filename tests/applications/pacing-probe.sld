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

    (define (tile seed cell)
      (let ((x (index-x cell)) (y (index-y cell)))
        (+ (* 10 (deposit-rate seed x y))
           (if (ground? seed x y) 1 (if (water? seed x y) 2 0)))))
    (define (path-length path)
      (if (null? path) 0 (+ 1 (path-length (cdr path)))))
    (define (nest-route seed)
      (path-length (walking-path seed (spawn-x seed) (spawn-y seed) (nest-x seed) (nest-y seed)
                                 (list (make-survey 64 64 128)) #f)))
    (define answer
      (ann (lambda (operation seed cell)
             (cond ((= operation 0) (tile seed cell))
                   ((= operation 1) (spawn-x seed))
                   ((= operation 2) (spawn-y seed))
                   ((= operation 3) (nest-x seed))
                   ((= operation 4) (nest-y seed))
                   ((= operation 5) (nest-route seed))
                   ((= operation 6) map-width)
                   ((= operation 7) map-height)
                   (else -1)))
           (-> I32 I32 I32 I32)))))
