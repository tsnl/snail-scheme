;; What a lifecycle instance says of its type. A Drop instance is for a row
;; and a declared type, `(Drop (! label ...) (T a ...))`, and makes the
;; values of T moved, never copied, as the old compiler's
;; `lifecycle-program` (src/snail/shell/compiler/expand.sld) makes T
;; owned. Only T's own library may declare one; a head that is not a row
;; and a type, or names a type of another library, makes nothing moved
;; here, and the checks that refuse it are still to come.
(define-library (snail compiler declare lifecycle)
  (export
   drop-type
   with-drops)
  (import
   (snail core base)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) same-library?)
   (only (snail compiler expand language) Global ClassGlobal FieldClass)
   (snail compiler declare language)
   (snail compiler declare forms)
   (snail compiler declare equality))
  (begin

    ;; ---- Drop ----

    ;; The type of `library` a Drop instance of that library is for.
    (: drop-type (impl (Fn LibraryName Instance -> (Option Global))))
    (define (drop-type library instance)
      (match (Pair (::class instance) (::types instance))
        ((Pair (ClassGlobal class) (Cons _ (Cons (Con type _) (Nil))))
         (if (and (same-global? class drop-class) (same-library? (::library type) library))
             (Some type)
             (None)))
        (_ (None))))

    ;; `data`, saying whether it is among the types `dropped`, which have a
    ;; Drop instance.
    (: with-drops (impl (Fn Data (List Global) -> Data)))
    (define (with-drops data dropped)
      (Data (::global data)
            (::parameters data)
            (::cases data)
            (::kind data)
            (::move? data)
            (any? (lambda (type) (same-global? type (::global data))) dropped)
            (::annotations data)
            (::loc data)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-lifecycle)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-lifecycle)
        (let* ((loc (Loc "t.sld" 1 1))
               (handle (Global (list "main") "Handle" 0))
               (row (Row (Effects (list) (None))))
               (instance (lambda (class types)
                           (Instance (Global (list "main") "Drop" 7)
                                     class
                                     (list)
                                     types
                                     (list)
                                     (list)
                                     (list)
                                     (Methods (list))
                                     loc))))
          (expect (drop-type (list "main")
                             (instance (ClassGlobal drop-class) (list row (Con handle (list)))))
                  (Some handle))
          (expect (drop-type (list "other")
                             (instance (ClassGlobal drop-class) (list row (Con handle (list)))))
                  (None))
          (expect
           (drop-type (list "main") (instance (ClassGlobal drop-class) (list (Con handle (list)))))
           (None))
          (expect (drop-type (list "main")
                             (instance (ClassGlobal (Global (list "snail" "core" "base") "Clone" 0))
                               (list row (Con handle (list)))))
                  (None))
          (expect
           (drop-type (list "main") (instance (FieldClass "x") (list row (Con handle (list)))))
           (None))
          (let ((data (Data handle (list) (list) (StructData) #f #f (list) loc)))
            (expect (::drop? (with-drops data (list handle))) #t)
            (expect (::drop? (with-drops data (list (Global (list "main") "Handle" 2)))) #f))))))
   (else)))
