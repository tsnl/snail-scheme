(import
 (snail core base)
 (snail core io))

;; A generator: `yield` hands a value to the handler, which collects it
;; and resumes the walk, so the handled body runs to its end between the
;; values it yields. Each yield saves the frames of every call it leaves,
;; with the locals they still need, and `resume` runs them again.
(effect Gen
  ((ctl yield (dyn (Fn I64 → Unit)))))

(enum Tree
  (Leaf)
  (Node
   ((left Tree)
    (value I64)
    (right Tree))))

(define tree (→ Tree)
  (Node (Node (Leaf) 3 (Node (Leaf) 8 (Leaf))) 5 (Node (Node (Leaf) 12 (Leaf)) 7 (Leaf))))

;; Every value the body yields, then the body's own result.
(define (collect (body (dyn (Fn → I64 ! Gen)))) (→ (List I64))
  (handle Gen ((yield (lambda (value resume) (Cons value (resume (unit))))))
    (list (body))))

;; An in-order walk yielding each value times its depth: `depth`,
;; `value`, `right` and the left subtree's sum are live across the yield,
;; in a frame per level of the tree. The result is the tree's sum.
(define (walk (tree Tree) (depth I64)) (→ I64) (! Gen)
  (match tree
    ((Leaf) 0)
    ((Node left value right)
     (let ((left-sum (walk left (+ depth 1))))
       (yield (* value depth))
       (+ (+ left-sum value) (walk right (+ depth 1)))))))

(define (show-all (values (List I64))) (→ Unit) (! output-port)
  (write-line (string-join (map show values) " ")))

(show-all (collect (lambda () (walk tree 1))))

;; Yields inside `if`, inside a `match` clause, and in a let's value.
(define (classify (items (List I64))) (→ I64) (! Gen)
  (match items
    ((Nil) 0)
    ((Cons item rest)
     (let ((here (if (< item 0) (begin (yield (- 0 item)) 1) 0)))
       (+ here (classify rest))))))

(show-all (collect (lambda () (classify (list 1 -2 3 -4 -5)))))

;; Operands around a yield run in order: `f`'s yield and its value come
;; first, then the bare yield, then `g`'s.
(define (add3 (a I64) (b I64) (c I64)) (→ I64)
  (+ a (+ b c)))

(define (f (x I64)) (→ I64) (! Gen)
  (yield (* x 10))
  (+ x 100))

(define (g (x I64)) (→ I64) (! Gen)
  (yield (* x 10))
  (+ x 300))

(show-all (collect (lambda () (add3 (f 1) (begin (yield 2) 200) (g 3)))))

;; A yield in the middle of a let's value, whose own frames end where the
;; value does; the let's body runs on what they produce. After an earlier
;; yield, the same shape runs again within the frame that yield saved.
(show-all (collect (lambda ()
                     (let ((inner (let ((x (f 4))) (yield x) (* x 2))))
                       (yield inner)
                       (+ inner 1)))))

(show-all (collect (lambda ()
                     (yield 1)
                     (let ((inner (let ((x (f 5))) (yield x) (* x 2))))
                       (yield inner)
                       (+ inner 1)))))

;; Locals of other representations live across a yield too: a float,
;; boxed in the frame, and a `FnOnce`, moved into it and called once the
;; body resumes.
(define (halves (items (List I64))) (→ F64) (! Gen)
  (match items
    ((Nil) 0.0)
    ((Cons item rest)
     (let ((half (/ (i64->f64 item) 2.0)))
       (yield item)
       (+ half (halves rest))))))

(write-line
 (show (handle Gen ((yield (lambda (value resume) (resume (unit))))) (halves (list 1 2 4)))))

(show-all (handle Gen ((yield (lambda (value resume) (Cons value (resume (unit))))))
            (let ((after (once (lambda () (write-line "after the yield")))))
              (yield 1)
              (after)
              (list 2))))

;; The handler can stop resuming, dropping the rest of the walk: the
;; values up to the first above the limit.
(define (until-above (limit I64) (body (dyn (Fn → I64 ! Gen)))) (→ (List I64))
  (handle Gen ((yield (lambda (value resume)
                        (if (> value limit)
                            (begin
                              (drop resume)
                              (list value))
                            (Cons value (resume (unit)))))))
    (body)
    (Nil)))

(show-all (until-above 20 (lambda () (walk tree 1))))
