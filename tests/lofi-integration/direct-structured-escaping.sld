(import
 (lofi base))

(def calls
     (ref (ann 0 I64)))
(def make-counter
     (lambda (seed early?)
       (begin
         (def cell
              (ref seed))
         (def saved
              (lambda (amount)
                ((begin (let increment amount)
                        (begin
                          (def apply
                               (lambda ()
                                 (begin
                                   (ref-set! calls (+ (ref-get calls) (ann 1 I64)))
                                   ((begin step) increment))))
                          apply)))))
         (def early
              (if early? (saved (ann 1 I64)) (ann 0 I64)))
         (def step
              (lambda (amount)
                (begin
                  (ref-set! cell (+ (ref-get cell) amount))
                  (ref-get cell))))
         saved)))
(def left
     (make-counter (ann 40 I64) #f))
(def right
     (make-counter (ann 100 I64) #f))
(def make-next
     (lambda (seed)
       ((begin (let cell (ref seed))
               (begin
                 (def step
                      (lambda (amount)
                        (begin
                          (ref-set! cell (+ (ref-get cell) amount))
                          (ref-get cell))))
                 (def build
                      (lambda () (lambda (amount) ((begin step) amount))))
                 build)))))
(def next
     (make-next (ann 40 I64)))

(def checked (-> I64)
     (lambda () ((make-counter (ann 0 I64) #t) (ann 1 I64))))

(def observed (-> I64)
     (lambda () (ref-get calls)))

(if (if (= (left (ann 1 I64)) (ann 41 I64))
        (if (= (right (ann 2 I64)) (ann 102 I64)) (if (= (left (ann 1 I64)) (ann 42 I64)) (if (= (next (ann 1 I64)) (ann 41 I64)) (= (next (ann 1 I64)) (ann 42 I64)) #f) #f) #f)
        #f)
    (ann 42 I64)
    (ann 0 I64))
