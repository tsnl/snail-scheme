(import
 (lofi base))
(def Empty (datatype ()
             (empty)))
(def Choice (datatype ( T)
              (absent)
              (alternate)
              (value
               (item T choice-value))))
(def make-choice
     absent)
(def call-constructor
     (lambda (procedure) (procedure)))
(def first
     (ann (call-constructor make-choice) (Choice I32)))
(def second
     (ann (call-constructor make-choice) (Choice Char)))
(def marker
     (call-constructor empty))
;; Shared immutable values must not merge the explicit mutable cells around them.
(def left
     (ref first))
(def right
     (ref first))
(ref-set! left (alternate))
(+ (+ (if (ref-eq? left right) (ann -100 I64) (ann 10 I64))
      (match (ref-get left) ((absent) (ann -100 I64)) ((alternate) (ann 12 I64)) ((value item) (ann -100 I64))))
   (+ (match (ref-get right) ((absent) (ann 7 I64)) ((alternate) (ann -100 I64)) ((value item) (ann -100 I64)))
      (+ (match second ((absent) (ann 8 I64)) ((alternate) (ann -100 I64)) ((value item) (ann -100 I64)))
         (match marker ((empty) (ann 5 I64))))))
