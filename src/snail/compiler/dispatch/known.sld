;; What `dispatch` knows of a class where an instance or a form names it,
;; as the old compiler knows it there: its parameters, each a type or a
;; row, its outputs, and its members, each with its own scheme. A class
;; of another library is what that library offers its importers'
;; declaration, complete. A class of the library's own is its entity once
;; its declaration is reached, in the order the declarations are written,
;; and before that its shape alone: every parameter a type, its outputs,
;; and no member, as the old compiler's scan registers a class before its
;; declaration gives it methods. A field class `::label` is `(::label R
;; T)`, two types, no output and its one reader.
(define-library (snail compiler dispatch known)
  (export
   KnownClass
   Classes
   library-classes
   classes-with-reached
   known-class)
  (import
   (snail core base)
   (snail core table)
   (snail compiler names libraries)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare offer) Declarations)
   (only (snail compiler names globals) Global ClassRef ClassGlobal FieldClass same-global?)
   (only (snail compiler declare schemes) field-class-parameters)
   (only (snail compiler declare membership) member-schemes))
  (begin

    ;; ---- Classes ----

    ;; A class as an instance or a form sees it: its written parameters,
    ;; its outputs, and each member it has there with its own scheme, in
    ;; the class's order.
    (struct KnownClass
      ((parameters (List declared-ClassParameter))
       (outputs (List declared-Output))
       (members (List (Pair declared-Member declared-Scheme)))))

    ;; What is known of classes at one point of the library `library`: the
    ;; offers of its import closure; each class it declares, found before
    ;; the walk; and those whose declarations the walk has reached.
    (struct Classes
      ((library LibraryName)
       (imported (List Declarations))
       (own (List declared-Class))
       (reached (List declared-Class))))

    ;; What is known before the first declaration of a library whose
    ;; declarations are `tops`.
    (: library-classes
       (impl (Fn LibraryName (List Declarations) (List declared-Top) -> Classes)))
    (define (library-classes library imported tops)
      (Classes library imported (tops-classes tops) (Nil)))

    (: tops-classes (impl (Fn (List declared-Top) -> (List declared-Class))))
    (define (tops-classes tops)
      (concatenate (map (lambda (top)
                          (match top
                            ((declared-TopClass class) (list class))
                            ((declared-InstanceScope _ inner _) (tops-classes inner))
                            (_ (Nil))))
                        tops)))

    ;; What is known once the declaration of `class` is reached.
    (: classes-with-reached (impl (Fn Classes declared-Class -> Classes)))
    (define (classes-with-reached classes class)
      (Classes (::library classes)
               (::imported classes)
               (::own classes)
               (Cons class (::reached classes))))

    ;; ---- Lookups ----

    ;; `expand` resolves a class's name to a class of the library or of
    ;; one in its import closure, and the integrator hands `dispatch` the
    ;; offers of that closure, so a lookup finds the class, and a miss is a
    ;; compiler bug.
    (: known-class (impl (Fn Classes ClassRef -> KnownClass)))
    (define (known-class classes class)
      (match class
        ((FieldClass _) (KnownClass field-class-parameters (Nil) (member-schemes class (Nil))))
        ((ClassGlobal global)
         (if (same-library? (::library global) (::library classes))
             (match (named global (::reached classes))
               ((Some reached) (entity-known reached))
               ((None) (shape-known (own-class classes global))))
             (entity-known (imported-class classes global))))))

    (: entity-known (impl (Fn declared-Class -> KnownClass)))
    (define (entity-known class)
      (KnownClass (::parameters class)
                  (::outputs class)
                  (member-schemes (ClassGlobal (::global class)) (::methods class))))

    ;; A class whose declaration is not reached: every parameter a type,
    ;; and no member.
    (: shape-known (impl (Fn declared-Class -> KnownClass)))
    (define (shape-known class)
      (KnownClass (map (lambda (parameter)
                         (match parameter
                           ((declared-TypeParameter name) (declared-TypeParameter name))
                           ((declared-RowParameter name) (declared-TypeParameter name))))
                       (::parameters class))
                  (::outputs class)
                  (Nil)))

    (: own-class (impl (Fn Classes Global -> declared-Class)))
    (define (own-class classes global)
      (match (named global (::own classes))
        ((Some found) found)
        ((None)
         (panic (string-append "dispatch: the library declares no class " (::name global))))))

    (: imported-class (impl (Fn Classes Global -> declared-Class)))
    (define (imported-class classes global)
      (match (find (lambda (offer) (same-library? (::library offer) (::library global)))
                   (::imported classes))
        ((Some offer)
         (match (table-ref (::classes offer) (::name global))
           ((Some found)
            (match (named global found)
              ((Some class) class)
              ((None) (panic (string-append "dispatch: no library offers the class "
                                            (::name global))))))
           ((None)
            (panic (string-append "dispatch: no library offers the class " (::name global))))))
        ((None) (panic (string-append "dispatch: no offer of the library of " (::name global))))))

    (: named (impl (Fn Global (List declared-Class) -> (Option declared-Class))))
    (define (named global classes)
      (find (lambda (class) (same-global? (::global class) global)) classes))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-known)
    (import
     (snail compiler source)
     (only (snail compiler names globals) Label)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler declare schemes) field-reader-scheme)
     (snail stage0 testing))
    (begin
      (define (test-known)
        (test-imported)
        (test-own)
        (test-field))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define lib (list "lib"))

      (define own-scheme
        (declared-Scheme (list)
                         (list)
                         (list)
                         (declared-Con (Global forms-library "Unit" 0) (list))))

      ;; (typeclass (Store e S) (type Out) (: fetch ...)) in `library`,
      ;; whose e is a row.
      (define (store library)
        (declared-Class (Global library "Store" 0)
                        (list (declared-RowParameter "e") (declared-TypeParameter "S"))
                        (list (declared-Output (Label "Out" loc) (list)))
                        (list (declared-Method (Global library "fetch" 0) own-scheme (list) loc))
                        (list)
                        loc))

      (define (store-known library)
        (KnownClass (list (declared-RowParameter "e") (declared-TypeParameter "S"))
                    (list (declared-Output (Label "Out" loc) (list)))
                    (list (Pair (declared-ClassMethod (Global library "fetch" 0)) own-scheme))))

      (define imported
        (list (Declarations lib
                            empty-table
                            (table-set empty-table "Store" (list (store lib)))
                            empty-table)))

      ;; A class another library offers is complete.
      (define (test-imported)
        (expect (known-class (library-classes main imported (list))
                             (ClassGlobal (Global lib "Store" 0)))
                (store-known lib)))

      ;; The library's own class, inside an instance scope too, is its
      ;; shape until its declaration is reached: every parameter a type and
      ;; no member; then its entity.
      (define (test-own)
        (let ((classes (library-classes main
                                        imported
                                        (list (declared-InstanceScope
                                               (list)
                                               (list (declared-TopClass (store main)))
                                               loc))))
              (class (ClassGlobal (Global main "Store" 0))))
          (expect (known-class classes class)
                  (KnownClass (list (declared-TypeParameter "e") (declared-TypeParameter "S"))
                              (list (declared-Output (Label "Out" loc) (list)))
                              (list)))
          (expect (known-class (classes-with-reached classes (store main)) class)
                  (store-known main))))

      ;; A field class's two types and its one reader.
      (define (test-field)
        (expect (known-class (library-classes main (list) (list)) (FieldClass "x"))
                (KnownClass (list (declared-TypeParameter "R") (declared-TypeParameter "T"))
                            (list)
                            (list (Pair (declared-FieldReader "x") field-reader-scheme)))))))
   (else)))
