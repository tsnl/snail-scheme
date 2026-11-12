;; What a piece of Syntax includes. `(include-bytes "path")` names the
;; file at `path` beside the file the form is written in, as `beside` in
;; (snail compiler source) decides. The query (snail compiler include
;; paths) and the pass `include` both decide through this rule, so the
;; files the integrator reads are the files the pass looks up.
(define-library (snail compiler include inclusion)
  (export
   Inclusion
   NoInclusion
   MalformedInclusion
   FileInclusion
   inclusion)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read language)
   (snail compiler literals datum))
  (begin

    ;; ---- Inclusions ----

    ;; A node is no `include-bytes` form, one without exactly one string,
    ;; or the inclusion of the file at a resolved path.
    (enum Inclusion
      (NoInclusion)
      (MalformedInclusion)
      (FileInclusion
       ((path String))))

    ;; What `syntax` includes, as a node by itself: an inclusion inside it
    ;; is its own node's.
    (: inclusion (impl (Fn Syntax -> Inclusion)))
    (define (inclusion syntax)
      (match syntax
        ((Form (Cons (Ident "include-bytes" _) arguments) loc)
         (inclusion-of arguments (::file loc)))
        (_ (NoInclusion))))

    (: inclusion-of (impl (Fn (List Syntax) String -> Inclusion)))
    (define (inclusion-of arguments file)
      (match arguments
        ((Cons (Atom (Text path) _) (Nil)) (FileInclusion (beside file path)))
        (_ (MalformedInclusion))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-inclusion)
    (import
     (snail stage0 testing))
    (begin
      (define (test-inclusion)
        (test-inclusions))

      ;; The path is resolved against the file the form is in; its head and
      ;; argument may be anywhere.
      (define (test-inclusions)
        (define (at file)
          (Loc file 1 1))
        (define (include-form file arguments)
          (Form (Cons (Ident "include-bytes" (at "other.sld")) arguments) (at file)))
        (expect (inclusion (include-form "lib/a.sld" (list (Atom (Text "x.bin") (at "other.sld")))))
                (FileInclusion "lib/x.bin"))
        (expect (inclusion (include-form "lib/a.sld" (list (Atom (Text "/x.bin") (at "a.sld")))))
                (FileInclusion "/x.bin"))
        (for-each (lambda (arguments)
                    (expect (inclusion (include-form "lib/a.sld" arguments)) (MalformedInclusion)))
                  (list (list)
                        (list (Ident "x" (at "a.sld")))
                        (list (Atom (Integer 1) (at "a.sld")))
                        (list (include-form "lib/a.sld" (list (Atom (Text "x") (at "a.sld")))))
                        (list (Atom (Text "x") (at "a.sld")) (Atom (Text "y") (at "a.sld")))))
        (for-each (lambda (syntax) (expect (inclusion syntax) (NoInclusion)))
                  (list (Ident "include-bytes" (at "a.sld"))
                        (Atom (Text "include-bytes") (at "a.sld"))
                        (Form (list) (at "a.sld"))
                        (Form (list (Ident "f" (at "a.sld"))
                                    (include-form "a.sld" (list (Atom (Text "x") (at "a.sld")))))
                              (at "a.sld"))
                        (Form (list (Atom (Text "include-bytes") (at "a.sld"))
                                    (Atom (Text "x") (at "a.sld")))
                              (at "a.sld")))))))
   (else)))
