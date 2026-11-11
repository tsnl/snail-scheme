;; Query: the files a file's forms include, which the integrator reads
;; before `include` runs, as the rule (snail compiler include inclusion)
;; decides them.
(define-library (snail compiler include paths)
  (export
   included-paths)
  (import
   (snail core base)
   (snail compiler read language)
   (snail compiler include inclusion))
  (begin

    ;; ---- Included files ----

    ;; The resolved path of each well-formed `include-bytes` form, at any
    ;; depth, in the order the forms are written, once for each form. A
    ;; malformed one names no file, and `include` reports it.
    (: included-paths (impl (Fn (List Syntax) -> (List String))))
    (define (included-paths forms)
      (concatenate (map form-paths forms)))

    (: form-paths (impl (Fn Syntax -> (List String))))
    (define (form-paths syntax)
      (match (inclusion syntax)
        ((FileInclusion path) (list path))
        ((MalformedInclusion) (Nil))
        ((NoInclusion) (inner-paths syntax))))

    (: inner-paths (impl (Fn Syntax -> (List String))))
    (define (inner-paths syntax)
      (match syntax
        ((Form items _) (included-paths items))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-paths)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-paths)
        (let ((at (Loc "lib/a.sld" 1 1)))
          (define (include-form path)
            (Form (list (Ident "include-bytes" at) (Atom (Text path) at)) at))
          (expect (included-paths (list)) (list))
          (expect (included-paths (list (Ident "x" at) (include-form "one.bin")))
                  (list "lib/one.bin"))
          (expect (included-paths
                   (list (Form (list (Ident "define" at)
                                     (Form (list (include-form "/abs.bin")) at)
                                     (include-form "two.bin"))
                               at)
                         (include-form "two.bin")))
                  (list "/abs.bin" "lib/two.bin" "lib/two.bin"))
          (expect (included-paths
                   (list (Form (list (Ident "include-bytes" at)) at)
                         (Form (list (Ident "include-bytes" at) (Ident "x" at)) at)
                         (Form (list (Ident "include-bytes" at) (include-form "inner.bin")) at)
                         (Form (list (Ident "include-bytes" at)
                                     (Atom (Text "a") at)
                                     (Atom (Text "b") at))
                               at)))
                  (list))
          (expect (included-paths
                   (list (include-form "x.bin")
                         (Form (list (Ident "include-bytes" (Loc "other/b.sld" 2 2))
                                     (Atom (Text "y.bin") at))
                               (Loc "other/b.sld" 2 1))))
                  (list "lib/x.bin" "other/y.bin"))))))
   (else)))
