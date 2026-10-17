;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.1 (lambda (xs.1 n) (if (null? xs.1) n (loop.1 (cdr xs.1) (+ n (ann 1 I64)))))) loop.1)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def MutableList (datatype ( T)
  (ml-empty)
  (ml-node (head T ml-car) (tail (Ref (MutableList T)) ml-tail-cell))))

(def Lattice (datatype ( T)
  (make-lattice (elements (MutableList T) lattice->elements) (compare (-> T T I64) lattice->cmp))))

(def Binding (datatype ( S T) (make-binding (source S binding-source) (target T binding-target))))

(def ml-cons (All (T) (-> T (MutableList T) (MutableList T)))
  (lambda (head.4 tail.2) (ml-node head.4 (ref tail.2))))

(def ml-null? (All (T) (-> (MutableList T) Bool))
  (lambda (values.3) (match values.3 ((ml-empty) #t) ((ml-node head.3 tail.1) #f))))

(def ml-cdr (All (T) (-> (MutableList T) (MutableList T)))
  (lambda (values.2) (ref-get (ml-tail-cell values.2))))

(def ml-set-cdr! (All (T) (-> (MutableList T) (MutableList T) Unit))
  (lambda (values.1 tail) (ref-set! (ml-tail-cell values.1) tail)))

(def ml-map (All (A B) (-> (-> A B) (MutableList A) (MutableList B)))
  (lambda (procedure values)
    (if (ml-null? values)
      (ml-empty)
      ((lambda (head.2) (ml-cons head.2 (ml-map procedure (ml-cdr values))))
        (procedure (ml-car values))))))

(def ml-append (All (T) (-> (MutableList T) (MutableList T) (MutableList T)))
  (lambda (first last)
    (if (ml-null? first) last (ml-cons (ml-car first) (ml-append (ml-cdr first) last)))))

(def ml-concatenate (All (T) (-> (MutableList (MutableList T)) (MutableList T)))
  (lambda (lists)
    (if (ml-null? lists)
      (ml-empty)
      (if (ml-null? (ml-cdr lists))
        (ml-car lists)
        (ml-append (ml-car lists) (ml-concatenate (ml-cdr lists)))))))

(def code-member? (-> I64 (MutableList I64) Bool)
  (lambda (value.16 codes)
    (if (not (ml-null? codes))
      ((lambda (value.17) (if value.17 value.17 (code-member? value.16 (ml-cdr codes))))
        (= value.16 (ml-car codes)))
      #f)))

(def lattice-base-elements (ml-cons (ann 0 I64) (ml-cons (ann 1 I64) (ml-empty))))

(def lattice-less-equal (ml-cons (ann 0 I64) (ml-cons (ann 1 I64) (ml-empty))))

(def lattice-more-equal (ml-cons (ann 2 I64) (ml-cons (ann 1 I64) (ml-empty))))

(def hide (lambda (count.1 x.4) (hide-i64 x.4)))

(def lexico (All (T) (-> (-> T T I64) (-> (MutableList T) (MutableList T) I64)))
  (lambda (base)
    (begin
      (def lex-fixed
        (lambda (fixed lhs.2 rhs.2)
          (begin
            (def check
              (lambda (lhs.3 rhs.3)
                (if (ml-null? lhs.3)
                  fixed
                  ((lambda (probe.1) (if ((lambda (value.15) (if value.15 value.15 (= probe.1 fixed))) (= probe.1 (ann 1 I64))) (check (ml-cdr lhs.3) (ml-cdr rhs.3)) (ann 3 I64)))
                    (base (ml-car lhs.3) (ml-car rhs.3))))))
            (check lhs.2 rhs.2))))
      (def lex-first
        (lambda (lhs.1 rhs.1)
          (if (ml-null? lhs.1)
            (ann 1 I64)
            ((lambda (probe) ((lambda (value.11) (if ((lambda (value.14) (if value.14 value.14 (= value.11 (ann 2 I64)))) (= value.11 (ann 0 I64))) (lex-fixed probe (ml-cdr lhs.1) (ml-cdr rhs.1)) ((lambda (value.12) (if (= value.12 (ann 1 I64)) (lex-first (ml-cdr lhs.1) (ml-cdr rhs.1)) ((lambda (value.13) (if (= value.13 (ann 3 I64)) (ann 3 I64) (unreachable))) value.12))) value.11))) probe))
              (base (ml-car lhs.1) (ml-car rhs.1))))))
      lex-first)))

(def zulu-select (All (T) (-> (-> T Bool) (MutableList T) (MutableList T)))
  (lambda (test.1 lst.6)
    (begin
      (def select-a.1
        (lambda (ac.1 lst.7)
          (if (ml-null? lst.7)
            (xreverse! ac.1)
            (select-a.1
              ((lambda (head.1) (if (test.1 head.1) (ml-cons head.1 ac.1) ac.1)) (ml-car lst.7))
              (ml-cdr lst.7)))))
      (select-a.1 (ml-empty) lst.6))))

(def xreverse! (All (T) (-> (MutableList T) (MutableList T)))
  (lambda (lst.5)
    ((lambda () (begin (def rotate (lambda (fo fum) ((lambda (next.1) (begin (ml-set-cdr! fo fum) (if (ml-null? next.1) fo (rotate next.1 fo)))) (ml-cdr fo)))) (if (ml-null? lst.5) (ml-empty) (rotate lst.5 (ml-empty)))))
)))

(def select-map (All (A B) (-> (-> A Bool) (-> A B) (MutableList A) (MutableList B)))
  (lambda (test func lst.3)
    (begin
      (def select-a
        (lambda (ac lst.4)
          (if (ml-null? lst.4)
            (xreverse! ac)
            (select-a
              ((lambda (head) (if (test head) (ml-cons (func head) ac) ac)) (ml-car lst.4))
              (ml-cdr lst.4)))))
      (select-a (ml-empty) lst.3))))

(def map-and (All (T) (-> (-> T Bool) (MutableList T) Bool))
  (lambda (proc lst.1)
    (if (ml-null? lst.1)
      #t
      ((lambda () (begin (def drudge (lambda (lst.2) ((lambda (rest.2) (if (ml-null? rest.2) (proc (ml-car lst.2)) (if (proc (ml-car lst.2)) (drudge rest.2) #f))) (ml-cdr lst.2)))) (drudge lst.1)))
))))

(def maps-1 (All (S T) (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) S (MutableList T)))
  (lambda (source.3 target.3 pas.1 new)
    ((lambda (scmp tcmp) ((lambda (less more) (zulu-select (lambda (t) (if (map-and (lambda (t2.1) (code-member? (tcmp t2.1 t) lattice-less-equal)) less) (map-and (lambda (t2) (code-member? (tcmp t2 t) lattice-more-equal)) more) #f)) (lattice->elements target.3))) (select-map (lambda (p) (= (ann 0 I64) (scmp (binding-source p) new))) binding-target pas.1) (select-map (lambda (p.1) (= (ann 2 I64) (scmp (binding-source p.1) new))) binding-target pas.1)))
      (lattice->cmp source.3)
      (lattice->cmp target.3))))

(def maps-rest (All (S T R) (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) (MutableList S) (-> (MutableList (Binding S T)) R) (-> (MutableList R) R) R))
  (lambda (source.2 target.2 pas rest to-1 to-collect)
    (if (ml-null? rest)
      (to-1 pas)
      ((lambda (next rest.1) (to-collect (ml-map (lambda (x.3) (maps-rest source.2 target.2 (ml-cons (make-binding next x.3) pas) rest.1 to-1 to-collect)) (maps-1 source.2 target.2 pas next))))
        (ml-car rest)
        (ml-cdr rest)))))

(def maps (All (S T) (-> (Lattice S) (Lattice T) (Lattice (MutableList T))))
  (lambda (source.1 target.1)
    (make-lattice
      (maps-rest
        source.1
        target.1
        (ml-empty)
        (lattice->elements source.1)
        (lambda (x.1) (ml-cons (ml-map binding-target x.1) (ml-empty)))
        (lambda (x.2) (ml-concatenate x.2)))
      (lexico (lattice->cmp target.1)))))

(def count-maps (All (S T) (-> (Lattice S) (Lattice T) I64))
  (lambda (source target)
    (maps-rest source target (ml-empty) (lattice->elements source) (lambda (x) (ann 1 I64)) sum)))

(def sum (-> (MutableList I64) I64)
  (lambda (lst) (if (ml-null? lst) (ann 0 I64) (+ (ml-car lst) (sum (ml-cdr lst))))))

(def run (-> I64 I64)
  (lambda (k)
    ((lambda (l2) ((lambda (l3) ((lambda (l4) ((lambda () (begin (count-maps l2 l2) (count-maps l3 l3) (count-maps l2 l3) (count-maps l3 l2) ((lambda (value.6) (if (= value.6 (ann 33 I64)) (count-maps l3 l3) ((lambda (value.7) (if (= value.7 (ann 44 I64)) (count-maps l4 l4) ((lambda (value.8) (if (= value.8 (ann 45 I64)) ((lambda (l5.2) (count-maps l4 l5.2)) (maps l4 l4)) ((lambda (value.9) (if (= value.9 (ann 54 I64)) ((lambda (l5.1) (count-maps l5.1 l4)) (maps l4 l4)) ((lambda (value.10) (if (= value.10 (ann 55 I64)) ((lambda (l5) (count-maps l5 l5)) (maps l4 l4)) (unreachable))) value.9))) value.8))) value.7))) value.6))) k))))) (maps l3 l3))) (maps l2 l2)))
      (make-lattice
        lattice-base-elements
        (lambda (lhs rhs)
          ((lambda (value) (if (= value (ann 0 I64)) ((lambda (value.4) (if (= value.4 (ann 0 I64)) (ann 1 I64) ((lambda (value.5) (if (= value.5 (ann 1 I64)) (ann 0 I64) (unreachable))) value.4))) rhs) ((lambda (value.3) (if (= value.3 (ann 1 I64)) ((lambda (value.1) (if (= value.1 (ann 0 I64)) (ann 2 I64) ((lambda (value.2) (if (= value.2 (ann 1 I64)) (ann 1 I64) (unreachable))) value.1))) rhs) (unreachable))) value)))
            lhs))))))

(def input0 (native-input-i64 (ann 0 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (if (<= count (ann 0 I64))
      (unreachable)
      (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (run (hide count input0))) result))) loop)))
        (ann 1 I64)
        (run (hide count input0))))))

(unit)
