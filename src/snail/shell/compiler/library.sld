;; Library files: where a library's source is, and what its file declares
;; before any of it is expanded. A file holds one `define-library`, read
;; into its sections, or one `generate-library`, read into the producer
;; program whose output is the library.
(define-library (snail shell compiler library)
  (export
   library-name
   library-path
   LibraryFile
   DefinedLibrary
   GeneratedLibrary
   file-library
   output-library-file
   section-items)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read))
  (begin

    ;; ---- Names and paths ----

    ;; `(snail core base)` is the list ("snail" "core" "base"); its globals are prefixed
    ;; `snail.core.base` and its source is `snail/core/base.sld` in a search directory.

    (define (library-name (syntax Syntax)) (→ (List String)) (! compile)
      (match syntax
        ((Form parts _)
         (map (lambda (part)
                (match part
                  ((Ident name _ _) name)
                  ((Atom (DInt number) _) (i64->string number))
                  (_ (compile-error (syntax-loc part) "expected a library name part"))))
              parts))
        (_ (compile-error (syntax-loc syntax) "expected a library name"))))

    (define (check-library-name (declared Syntax) (name (List String)) (loc Loc))
      (→ Unit)
      (! compile)
      (when (string=? (string-join name ".") "prim")
        (compile-error loc "the prim library name is reserved for compiler primitives"))
      (unless (string=? (string-join (library-name declared) ".") (string-join name "."))
        (compile-error loc "library name does not match its path")))

    ;; Where a library's source is: the first search directory holding it.

    (define (find-library (directories (List String)) (name (List String)))
      (→ (Option String))
      (! fs)
      (let ((relative (string-append (string-join name "/") ".sld")))
        (find file-exists?
              (map (lambda (directory) (string-append directory "/" relative)) directories))))

    (define (library-path (directories (List String)) (name (List String)) (loc Loc))
      (→ String)
      (! fs compile)
      (match (find-library directories name)
        ((Some path) path)
        ((None)
         (compile-error loc (string-append "library not found: (" (string-join name " ") ")")))))

    ;; What a library's file declares, read but not expanded: a defined
    ;; library's sections, through its `cond-expand`s, or a generated
    ;; library's producer program, with the location of the recipe's
    ;; expression, where the producer's output is placed.
    (enum LibraryFile
      (DefinedLibrary
        ((sections (List (Pair String (List Syntax))))))
      (GeneratedLibrary
       ((forms (List Syntax))
        (loc Loc))))

    ;; A library file holds one `define-library`, or one `generate-library`
    ;; whose program writes the library's `define-library` form as syntax.

    (define (file-library (name (List String)) (forms (List Syntax)) (path String))
      (→ LibraryFile)
      (! compile)
      (match forms
        ((Cons (Form (Cons (Ident "define-library" _ _) (Cons declared declarations)) loc) (Nil))
         (check-library-name declared name loc)
         (DefinedLibrary (concatenate (map library-sections declarations))))
        ((Cons (Form (Cons (Ident "generate-library" _ _)
                           (Cons declared
                                 (Cons (Form (Cons (Ident "import" _ _) imports) _)
                                       (Cons expression (Nil)))))
                     loc)
               (Nil))
         (check-library-name declared name loc)
         (GeneratedLibrary
          (producer path imports expression loc)
          (syntax-loc expression)))
        (_ (compile-error (new Loc (file path) (line 1) (column 1))
                          "expected exactly one define-library or generate-library form"))))

    ;; The library a producer's output declares, as if it were written at
    ;; `loc` in the recipe's file.

    (define (output-library-file (name (List String)) (bytes Bytes) (loc Loc))
      (→ LibraryFile)
      (! compile)
      (file-library name (list (decode-syntax bytes loc)) (● loc file)))

    ;; ---- Producers ----

    ;; The producer imports what the recipe imports, names the recipe's
    ;; file, and writes the syntax its expression returns, a
    ;; `(snail shell syntax)` Syntax, which it computes in a task.

    (define (producer (recipe String) (imports (List Syntax)) (expression Syntax) (loc Loc))
      (→ (List Syntax))
      (let ((write-library (Ident "write-generated-library" (None) loc)))
        (list (Form (Cons (Ident "import" (None) loc)
                          (append imports
                                  (list (Form (list (Ident "only" (None) loc)
                                                    (Form (list (Ident "snail" (None) loc)
                                                                (Ident "shell" (None) loc)
                                                                (Ident "syntax" (None) loc))
                                                          loc)
                                                    write-library)
                                              loc))))
                    loc)
              (Form (list (Ident "recipe" (None) loc) (Atom (DString recipe) loc)) loc)
              (Form (list (Ident "define" (None) loc) (Ident "main" (None) loc)
                          (Form (list (Ident "lambda" (None) loc) (Form (Nil) loc)
                                      (Form (list write-library
                                                  (Form (list (Ident "lambda" (None) loc)
                                                              (Form (Nil) loc) expression) loc))
                                            loc)) loc)) loc))))

    ;; ---- Sections ----

    ;; Each declaration is a section of imports, exports or definitions, or a
    ;; `cond-expand` choosing more declarations.

    (define (library-sections (declaration Syntax))
      (→ (List (Pair String (List Syntax))))
      (! compile)
      (match declaration
        ((Form (Cons (Ident "cond-expand" _ _) clauses) _) (cond-expand-sections clauses))
        ((Form (Cons (Ident kind _ _) items) loc)
         (if (member? kind (list "import" "export" "begin"))
             (list (new Pair (first kind) (second items)))
             (compile-error loc "expected import, export, begin or cond-expand")))
        (_
         (compile-error (syntax-loc declaration) "expected import, export, begin or cond-expand"))))

    ;; The declarations of the first clause whose requirement holds. `snail-scheme`'s
    ;; only feature is `snail-scheme`.

    (define (cond-expand-sections (clauses (List Syntax)))
      (→ (List (Pair String (List Syntax))))
      (! compile)
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons requirement declarations) _) rest)
         (if (feature? requirement)
             (concatenate (map library-sections declarations))
             (cond-expand-sections rest)))
        ((Cons clause _)
         (compile-error (syntax-loc clause) "expected (requirement declaration ...)"))))

    (define (feature? (requirement Syntax)) (→ Bool)
      (match requirement
        ((Ident name _ _) (or (string=? name "snail-scheme") (string=? name "else")))
        ((Form (Cons (Ident "and" _ _) items) _) (every? feature? items))
        ((Form (Cons (Ident "or" _ _) items) _) (any? feature? items))
        ((Form (Cons (Ident "not" _ _) (Cons item (Nil))) _) (not (feature? item)))
        (_ #f)))

    (define (section-items (sections (List (Pair String (List Syntax)))) (kind String))
      (→ (List Syntax))
      (concatenate
       (map (lambda (record) (● record second))
            (filter (lambda (section) (string=? (● section first) kind)) sections))))))
