;; Former macro-introduced extern has an explicit distinct binding.
(import
 (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I32) (combine foreign-add)))
(define-extern foreign-add "probe" "add" (-> I32 I32 I32))
(define-extern mark "probe" "mark" (-> I32 Unit))
(define-extern id-i64 "probe" "id64" (-> I64 I64))
(define-extern id-f32 "probe" "idf32" (-> F32 F32))
(define-extern id-f64 "probe" "idf64" (-> F64 F64))
(define-extern id-bool "probe" "id32" (-> Bool Bool))
(define-extern id-char "probe" "id32" (-> Char Char))

(def worker (-> I32 I32)
     (begin (let state (ref (ann 0 I32)))
            (begin
              (mark (ann 9 I32))
              (lambda (amount)
                (begin
                  (ref-set! state (i32-add (ref-get state) amount))
                  (ref-get state))))))

(def void-worker (-> I32 Unit)
     (lambda (digit)
       (begin
         (def invoke
              (lambda (action) (action digit)))
         (invoke mark)
         (unit))))

(def class-worker (-> I32 I32)
     (lambda (x) (combine x (ann 2 I32))))

(def class-value-worker (-> I32 I32)
     (lambda (x)
       (begin
         (def invoke
              (lambda (f) (f x (ann 2 I32))))
         (invoke combine))))

(def local-worker (-> I32 I32)
     (lambda (x)
       (begin
         (define-extern local-add "probe" "add" (-> I32 I32 I32))
         (local-add x (ann 2 I32)))))

(def macro-worker (-> I32 I32)
     (lambda (foreign) (begin
                         (begin (define-extern local-identity "probe" "id32" (-> I32 I32)) (local-identity foreign)))))

(def i64-worker (-> I64 I64)
     id-i64)

(def f32-worker (-> F32 F32)
     id-f32)

(def f64-worker (-> F64 F64)
     id-f64)

(def bool-worker (-> Bool Bool)
     id-bool)

(def char-worker (-> Char Char)
     id-char)
((begin (mark (ann 3 I32)) foreign-add)
 (begin (mark (ann 1 I32)) (ann 20 I32))
 (begin (mark (ann 2 I32)) (ann 22 I32)))
