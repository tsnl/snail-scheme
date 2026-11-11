;; What a piece of Syntax includes. `(include-bytes "path")` names the
;; file at `path` beside the file the form is written in: a relative path
;; is in the directory that holds that file, and an absolute one is
;; itself. The query (snail compiler include paths) and the pass `include`
;; both decide through this rule, so the files the integrator reads are
;; the files the pass looks up.
(define-library (snail compiler include inclusion)
  (export
   Inclusion
   NoInclusion
   MalformedInclusion
   FileInclusion
   inclusion)
  (import
   (snail core base)
   (snail compiler read language))
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

    ;; ---- Paths ----

    ;; `path`, written in `file`. A file named without a directory is in
    ;; the current one, so a relative path written there stays as written.
    (: beside (impl (Fn String String -> String)))
    (define (beside file path)
      (if (absolute? path)
          path
          (let ((chars (string->vector file)))
            (string-append (vector->string (subvector chars 0 (directory-end chars))) path))))

    (: absolute? (impl (Fn String -> Bool)))
    (define (absolute? path)
      (let ((chars (string->vector path)))
        (and (> (vector-length chars) 0) (char=? (vector-ref chars 0) #\/))))

    ;; The index just after the last `/` of a file's name, which ends the
    ;; name of its directory, or 0 when it has none.
    (: directory-end (impl (Fn (Vector Char) -> I64)))
    (define (directory-end chars)
      (let loop ((end (vector-length chars)))
        (cond ((= end 0) 0)
              ((char=? (vector-ref chars (- end 1)) #\/) end)
              (else (loop (- end 1))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-inclusion)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-inclusion)
        (test-inclusions)
        (test-beside))

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
                              (at "a.sld")))))

      (define (test-beside)
        (expect (beside "lib/sample/blob.sld" "data/blob.bin") "lib/sample/data/blob.bin")
        (expect (beside "/root/main.sld" "../x") "/root/../x")
        (expect (beside "dir/" "x") "dir/x")
        (expect (beside "main.sld" "data/x") "data/x")
        (expect (beside "" "x") "x")
        (expect (beside "lib/a.sld" "/abs/x") "/abs/x")
        (expect (beside "lib/a.sld" "") "lib/")
        (expect (beside "λ/é.sld" "😀") "λ/😀"))))
   (else)))
