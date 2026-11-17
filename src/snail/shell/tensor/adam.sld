;; Adam (Kingma and Ba, 2015) as more graph: the update of each trained
;; param, and of the moments Adam keeps for it, built as views a program
;; commits after each run. Nothing here runs or holds state; the moments
;; and the step count are params of the program, which start at zeros as
;; every buffer does, and which a host may write, as densification does
;; when it changes how many gaussians a param holds.
;;
;;   (adam-updates "adam" (adam 0.9 0.999 1e-15)
;;                 (list (new Trained (param w) (grad dw) (rate (scalar 0.01)))))
;;
;; A learning rate is a view, so a schedule is a param the host writes
;; each step. For each param p with gradient g, at step t from 1:
;;
;;   m := b1 m + (1 - b1) g            v := b2 v + (1 - b2) g^2
;;   p := p - rate sqrt(1 - b2^t) / (1 - b1^t) m / (sqrt v + epsilon)
(define-library (snail shell tensor adam)
  (export
   Adam
   adam
   Trained
   adam-updates
   moment-names)
  (import
   (snail core base)
   (snail shell tensor))
  (begin

    ;; ---- Settings ----

    (record Adam
      ((beta1 F64)
       (beta2 F64)
       (epsilon F64)))

    (define (adam (beta1 F64) (beta2 F64) (epsilon F64)) (→ Adam)
      (new Adam (beta1 beta1) (beta2 beta2) (epsilon epsilon)))

    ;; A param trained with its gradient at its rate.
    (record Trained
      ((param View)
       (grad View)
       (rate View)))

    ;; ---- Updates ----

    ;; The names of a param's first and second moments under `prefix`.
    (define (moment-names (prefix String) (param View)) (→ (Pair String String))
      (let ((name (param-name param)))
        (new Pair
          (first (string-append prefix "/m/" name))
          (second (string-append prefix "/v/" name)))))

    (define (param-name (view View)) (→ String)
      (match (● view node kind)
        ((Param name) name)
        (_ (panic "adam: a trained view must be a param"))))

    ;; The step count's update, then each param's and its moments'.
    (define (adam-updates (prefix String) (settings Adam) (trained (List Trained)))
      (→ (List (Pair View View)))
      (let* ((step (param (string-append prefix "/step") (Nil) (Float)))
             (t (+ step (scalar 1.0)))
             (b1 (● settings beta1))
             (b2 (● settings beta2))
             (correction (/ (sqrt (- (scalar 1.0) (power (scalar b2) t)))
                            (- (scalar 1.0) (power (scalar b1) t)))))
        (Cons (new Pair (first step) (second t))
              (concatenate
               (map (lambda (each) (param-updates prefix settings correction each)) trained)))))

    (define (param-updates (prefix String) (settings Adam) (correction View) (each Trained))
      (→ (List (Pair View View)))
      (let* ((p (● each param))
             (g (● each grad))
             (names (moment-names prefix p))
             (m (param (● names first) (shape-of p) (Float)))
             (v (param (● names second) (shape-of p) (Float)))
             (b1 (● settings beta1))
             (b2 (● settings beta2))
             (m2 (+ (* (scalar b1) m) (* (scalar (- 1.0 b1)) g)))
             (v2 (+ (* (scalar b2) v) (* (scalar (- 1.0 b2)) (square g))))
             (step
              (/ (* (* (● each rate) correction) m2) (+ (sqrt v2) (scalar (● settings epsilon))))))
        (list (new Pair (first m) (second m2))
              (new Pair (first v) (second v2))
              (new Pair (first p) (second (- p step))))))

    ))
