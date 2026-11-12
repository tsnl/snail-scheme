;; The pass `include`: each `(include-bytes "path")` form becomes the byte
;; vector it stands for, which is the contents of the file at `path`
;; beside the file the form is written in. The pass reads Syntax and
;; writes Syntax, so it has no language of its own; its output holds no
;; `include-bytes` form. The integrator reads the files first, as the
;; query (snail compiler include paths) names them, and hands their bytes
;; in by resolved path; the rule (snail compiler include inclusion)
;; decides for both what a form includes. Including stops at the first
;; problem.
(define-library (snail compiler include pass)
  (export
   include)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (snail compiler read language)
   (snail compiler literals datum)
   (snail compiler read location)
   (snail compiler include inclusion))
  (begin

    ;; ---- Forms ----

    ;; `forms` with every `include-bytes` form in them, at any depth,
    ;; replaced by its bytes, found in `files` by resolved path.
    (: include
       (impl (Fn (List Syntax) (Table Bytes) -> (Result (List Syntax) (List Feedback)))))
    (define (include forms files)
      (map-results (lambda (form) (included form files)) forms))

    (: included (impl (Fn Syntax (Table Bytes) -> (Result Syntax (List Feedback)))))
    (define (included syntax files)
      (match (inclusion syntax)
        ((FileInclusion path) (included-bytes path (syntax-loc syntax) files))
        ((MalformedInclusion) (fail (syntax-loc syntax) "expected (include-bytes \"path\")"))
        ((NoInclusion) (included-inside syntax files))))

    (: included-inside (impl (Fn Syntax (Table Bytes) -> (Result Syntax (List Feedback)))))
    (define (included-inside syntax files)
      (match syntax
        ((Form items loc)
         (result-let* ((replaced (include items files)))
           (Ok (Form replaced loc))))
        (_ (Ok syntax))))

    ;; ---- Included bytes ----

    ;; The bytes of the file at `path`, located where its `include-bytes`
    ;; form, at `loc`, is.
    (: included-bytes (impl (Fn String Loc (Table Bytes) -> (Result Syntax (List Feedback)))))
    (define (included-bytes path loc files)
      (match (table-ref files path)
        ((Some bytes) (Ok (Atom (ByteVector bytes) loc)))
        ((None) (fail loc (string-append "no file to include at " path)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-include)
    (import
     (snail stage0 testing))
    (begin
      (define (test-include)
        (test-replaced)
        (test-problems))

      ;; ---- Helpers ----

      (define (at column)
        (Loc "lib/a.sld" 1 column))

      (define (include-form path column)
        (Form (list (Ident "include-bytes" (at (+ column 1))) (Atom (Text path) (at (+ column 15))))
              (at column)))

      (define (bytes-atom numbers column)
        (Atom (ByteVector (list->vector numbers)) (at column)))

      (define files
        (table-set (table-set empty-table "lib/one.bin" (list->vector (list 1)))
                   "/abs/two.bin"
                   (list->vector (list 2 3))))

      ;; ---- Cases ----

      ;; A form at any depth becomes its bytes, where the form is; other
      ;; syntax stays as it is.
      (define (test-replaced)
        (expect (include (list) files) (Ok (list)))
        (expect (include (list (Ident "x" (at 1)) (include-form "one.bin" 3)) files)
                (Ok (list (Ident "x" (at 1)) (bytes-atom (list 1) 3))))
        (expect (include (list (Form (list (Ident "f" (at 2))
                                           (Form (list (include-form "/abs/two.bin" 4)) (at 3))
                                           (Atom (Text "one.bin") (at 30)))
                                     (at 1)))
                         files)
                (Ok (list (Form (list (Ident "f" (at 2))
                                      (Form (list (bytes-atom (list 2 3) 4)) (at 3))
                                      (Atom (Text "one.bin") (at 30)))
                                (at 1)))))
        (expect
         (include (list (Form (list (Ident "quote" (at 1)) (include-form "one.bin" 2)) (at 1)))
                  files)
         (Ok (list (Form (list (Ident "quote" (at 1)) (bytes-atom (list 1) 2)) (at 1))))))

      ;; A form takes exactly one string, and names a file it is handed;
      ;; including stops at the first problem.
      (define (test-problems)
        (define expected-form "expected (include-bytes \"path\")")
        (expect (include (list (Form (list (Ident "include-bytes" (at 2))) (at 1))) files)
                (fail (at 1) expected-form))
        (expect (include (list (Form (list (Ident "include-bytes" (at 2)) (Ident "p" (at 16)))
                                     (at 1)))
                         files)
                (fail (at 1) expected-form))
        (expect (include (list (Form (list (Ident "include-bytes" (at 2))
                                           (Atom (Text "one.bin") (at 16))
                                           (Atom (Text "one.bin") (at 26)))
                                     (at 1)))
                         files)
                (fail (at 1) expected-form))
        (expect (include (list (include-form "one.bin" 1)
                               (Form (list (include-form "missing.bin" 3)
                                           (Form (list (Ident "include-bytes" (at 9))) (at 8)))
                                     (at 2)))
                         files)
                (fail (at 3) "no file to include at lib/missing.bin"))
        (expect (include (list (include-form "two.bin" 1)) files)
                (fail (at 1) "no file to include at lib/two.bin")))))
   (else)))
