;; The pass `outline`: a file's forms, after `include`, become its Outline.
;; The integrator says how it reads the file: as the library it found the
;; file by, or as a program. A library's file holds one `define-library`
;; or `generate-library` form, whose declarations are read here, through
;; `cond-expand`; a program is its leading `import` forms and a body. The
;; header is read as the old expander reads it, message for message and
;; in its order, except that every import set and export is read before
;; any library loads or any body expands. Nothing here resolves a name,
;; loads a library or looks inside a body. Outlining stops at the first
;; problem.
(define-library (snail compiler outline pass)
  (export
   Reading
   AsLibrary
   AsProgram
   outline)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (prefix (snail compiler literals datum) datum-)
   (snail compiler read location)
   (snail compiler outline language)
   (snail compiler names libraries))
  (begin

    ;; ---- Files ----

    ;; How the integrator reads a file: as the library it found by `name`,
    ;; or as a program.
    (enum Reading
      (AsLibrary
       ((name LibraryName)))
      (AsProgram))

    ;; The outline of `forms`, the contents of `file`, read as `reading`
    ;; says.
    (: outline
       (impl (Fn Reading String (List syntax-Syntax) -> (Result Outline (List Feedback)))))
    (define (outline reading file forms)
      (match reading
        ((AsLibrary name) (library-outline name file forms))
        ((AsProgram) (program-outline forms))))

    ;; ---- Libraries ----

    ;; A library's file holds exactly one form, which declares it. A
    ;; generated library's form is its name, its recipe's `import` form and
    ;; the recipe's expression.
    (: library-outline
       (impl (Fn LibraryName String (List syntax-Syntax) -> (Result Outline (List Feedback)))))
    (define (library-outline wanted file forms)
      (match forms
        ((Cons
          (syntax-Form (Cons (syntax-Ident "define-library" _) (Cons declared declarations)) loc)
          (Nil))
         (defined-outline wanted declared declarations loc))
        ((Cons (syntax-Form (Cons (syntax-Ident "generate-library" _)
                                  (Cons declared
                                        (Cons
                                         (syntax-Form (Cons (syntax-Ident "import" _) imports) _)
                                         (Cons expression (Nil)))))
                            loc)
               (Nil))
         (result-let* ((name (declared-name wanted declared loc)))
           (Ok (Generated name imports expression loc))))
        (_ (fail (Loc file 1 1) "expected exactly one define-library or generate-library form"))))

    ;; The name comes first, then the declarations, then the import sets
    ;; and exports they hold.
    (: defined-outline
       (impl (Fn LibraryName syntax-Syntax (List syntax-Syntax) Loc
                 -> (Result Outline (List Feedback)))))
    (define (defined-outline wanted declared declarations loc)
      (result-let* ((name (declared-name wanted declared loc))
                    (sections (declarations-sections declarations))
                    (imports (map-results import-set (::imports sections)))
                    (exports (map-results export-spec (::exports sections))))
        (Ok (Written (Defined name imports exports (::body sections) loc)))))

    ;; The name a library declares at `loc`, which is the name it was found
    ;; by. No library may be found as (prim), the name reserved for the
    ;; compiler's primitives, whatever it declares.
    (: declared-name
       (impl (Fn LibraryName syntax-Syntax Loc -> (Result LibraryName (List Feedback)))))
    (define (declared-name wanted declared loc)
      (if (same-library? wanted prim-library)
          (fail loc "the prim library name is reserved for compiler primitives")
          (result-let* ((name (library-name declared)))
            (if (same-library? name wanted)
                (Ok name)
                (fail loc "library name does not match its path")))))

    ;; A library's name is a form of names and integers.
    (: library-name (impl (Fn syntax-Syntax -> (Result LibraryName (List Feedback)))))
    (define (library-name syntax)
      (match syntax
        ((syntax-Form parts _) (map-results name-part parts))
        (_ (fail (syntax-loc syntax) "expected a library name"))))

    (: name-part (impl (Fn syntax-Syntax -> (Result String (List Feedback)))))
    (define (name-part part)
      (match part
        ((syntax-Ident name _) (Ok name))
        ((syntax-Atom (datum-Integer integer) _) (Ok (i64->string integer)))
        (_ (fail (syntax-loc part) "expected a library name part"))))

    ;; ---- Declarations ----

    ;; The items of a library's import, export and begin declarations, each
    ;; kind joined in the order written.
    (struct Sections
      ((imports (List syntax-Syntax))
       (exports (List syntax-Syntax))
       (body (List syntax-Syntax))))

    (: no-sections Sections)
    (define no-sections (Sections (Nil) (Nil) (Nil)))

    (: joined-sections (impl (Fn Sections Sections -> Sections)))
    (define (joined-sections earlier later)
      (Sections (append (::imports earlier) (::imports later))
                (append (::exports earlier) (::exports later))
                (append (::body earlier) (::body later))))

    (: declarations-sections
       (impl (Fn (List syntax-Syntax) -> (Result Sections (List Feedback)))))
    (define (declarations-sections declarations)
      (result-let* ((declared (map-results declaration-sections declarations)))
        (Ok (fold-right joined-sections no-sections declared))))

    ;; A declaration is a section, or a `cond-expand` choosing more
    ;; declarations.
    (: declaration-sections (impl (Fn syntax-Syntax -> (Result Sections (List Feedback)))))
    (define (declaration-sections declaration)
      (match declaration
        ((syntax-Form (Cons (syntax-Ident "cond-expand" _) clauses) _) (chosen-sections clauses))
        ((syntax-Form (Cons (syntax-Ident "import" _) items) _) (Ok (Sections items (Nil) (Nil))))
        ((syntax-Form (Cons (syntax-Ident "export" _) items) _) (Ok (Sections (Nil) items (Nil))))
        ((syntax-Form (Cons (syntax-Ident "begin" _) items) _) (Ok (Sections (Nil) (Nil) items)))
        (_ (fail (syntax-loc declaration) "expected import, export, begin or cond-expand"))))

    ;; The declarations of the first clause whose requirement holds, or
    ;; none. The clauses after it are not read.
    (: chosen-sections (impl (Fn (List syntax-Syntax) -> (Result Sections (List Feedback)))))
    (define (chosen-sections clauses)
      (match clauses
        ((Nil) (Ok no-sections))
        ((Cons (syntax-Form (Cons requirement declarations) _) rest)
         (if (holds? requirement) (declarations-sections declarations) (chosen-sections rest)))
        ((Cons clause _) (fail (syntax-loc clause) "expected (requirement declaration ...)"))))

    ;; Snail-Core's one feature is `snail-core`, and `else` always holds. A
    ;; requirement of any other shape does not hold.
    (: holds? (impl (Fn syntax-Syntax -> Bool)))
    (define (holds? requirement)
      (match requirement
        ((syntax-Ident name _) (or (string=? name "snail-core") (string=? name "else")))
        ((syntax-Form (Cons (syntax-Ident "and" _) items) _) (every? holds? items))
        ((syntax-Form (Cons (syntax-Ident "or" _) items) _) (any? holds? items))
        ((syntax-Form (Cons (syntax-Ident "not" _) (Cons item (Nil))) _) (not (holds? item)))
        (_ #f)))

    ;; ---- Import sets ----

    ;; An import set, read as the expander reads one: `only`, `except`,
    ;; `prefix` and `rename` modify the set after them when they have the
    ;; arguments they take, and anything else is a library's name, so
    ;; `(only)` names the library (only) and `(prefix (a))` is a name with
    ;; a malformed part. A modifier's own arguments are read before the set
    ;; it modifies.
    (: import-set (impl (Fn syntax-Syntax -> (Result Import (List Feedback)))))
    (define (import-set spec)
      (match spec
        ((syntax-Form (Cons (syntax-Ident "only" _) (Cons inner names)) loc)
         (result-let* ((identifiers (map-results as-identifier names))
                       (modified (import-set inner)))
           (Ok (Only modified identifiers loc))))
        ((syntax-Form (Cons (syntax-Ident "except" _) (Cons inner names)) loc)
         (result-let* ((identifiers (map-results as-identifier names))
                       (modified (import-set inner)))
           (Ok (Except modified identifiers loc))))
        ((syntax-Form (Cons (syntax-Ident "prefix" _)
                            (Cons inner (Cons (syntax-Ident prefix _) (Nil))))
                      loc)
         (result-let* ((modified (import-set inner)))
           (Ok (Prefix modified prefix loc))))
        ((syntax-Form (Cons (syntax-Ident "rename" _) (Cons inner pairs)) loc)
         (result-let* ((renamings (map-results renaming pairs))
                       (modified (import-set inner)))
           (Ok (Rename modified renamings loc))))
        (_ (result-let* ((library (library-name spec)))
             (Ok (Whole library (syntax-loc spec)))))))

    ;; `(name new-name)` in a `rename` import set.
    (: renaming (impl (Fn syntax-Syntax -> (Result Renaming (List Feedback)))))
    (define (renaming pair)
      (match pair
        ((syntax-Form (Cons (syntax-Ident from loc) (Cons (syntax-Ident to _) (Nil))) _)
         (Ok (Renaming (Identifier from loc) to)))
        (_ (fail (syntax-loc pair) "expected (name new-name)"))))

    ;; ---- Exports ----

    ;; An export is an identifier, or `(rename identifier name)`.
    (: export-spec (impl (Fn syntax-Syntax -> (Result Export (List Feedback)))))
    (define (export-spec spec)
      (match spec
        ((syntax-Ident name loc) (Ok (Export (Identifier name loc) name)))
        ((syntax-Form (Cons (syntax-Ident "rename" _)
                            (Cons inner (Cons (syntax-Ident name _) (Nil))))
                      _)
         (result-let* ((exported (as-identifier inner)))
           (Ok (Export exported name))))
        (_ (fail (syntax-loc spec) "expected an export specification"))))

    ;; ---- Programs ----

    ;; A producer program that a build printed begins with the libraries
    ;; loading as it starts, `(generating key ...)`, each key a string.
    (: program-outline (impl (Fn (List syntax-Syntax) -> (Result Outline (List Feedback)))))
    (define (program-outline forms)
      (match forms
        ((Cons (syntax-Form (Cons (syntax-Ident "generating" _) keys) _) rest)
         (result-let* ((loading (map-results loading-key keys)))
           (program-after loading rest)))
        (_ (program-after (Nil) forms))))

    (: loading-key (impl (Fn syntax-Syntax -> (Result String (List Feedback)))))
    (define (loading-key key)
      (match key
        ((syntax-Atom (datum-Text text) _) (Ok text))
        (_ (fail (syntax-loc key) "expected a library key string"))))

    ;; The program after any `generating` form: its leading `import` forms,
    ;; then its body.
    (: program-after
       (impl (Fn (List String) (List syntax-Syntax) -> (Result Outline (List Feedback)))))
    (define (program-after loading forms)
      (let ((leading (leading-imports forms)))
        (result-let* ((imports (map-results import-set (::specs leading))))
          (Ok (Written (with-recipe loading imports (::body leading)))))))

    ;; The import sets of a program's leading `import` forms, joined in
    ;; order, and the forms after them.
    (struct Leading
      ((specs (List syntax-Syntax))
       (body (List syntax-Syntax))))

    (: leading-imports (impl (Fn (List syntax-Syntax) -> Leading)))
    (define (leading-imports forms)
      (match forms
        ((Cons (syntax-Form (Cons (syntax-Ident "import" _) specs) _) rest)
         (let ((after (leading-imports rest)))
           (Leading (append specs (::specs after)) (::body after))))
        (_ (Leading (Nil) forms))))

    ;; A producer's body begins with `(recipe "file")`, naming the file its
    ;; recipe is written in. Only a program with libraries loading has a
    ;; recipe; in any other, that form is the body's first.
    (: with-recipe (impl (Fn (List String) (List Import) (List syntax-Syntax) -> Library)))
    (define (with-recipe loading imports body)
      (match body
        ((Cons (syntax-Form (Cons (syntax-Ident "recipe" _)
                                  (Cons (syntax-Atom (datum-Text file) _) (Nil)))
                            _)
               rest)
         (if (null? loading)
             (Program loading (None) imports body)
             (Program loading (Some file) imports rest)))
        (_ (Program loading (None) imports body))))

    ;; ---- Identifiers ----

    (: as-identifier (impl (Fn syntax-Syntax -> (Result Identifier (List Feedback)))))
    (define (as-identifier syntax)
      (match syntax
        ((syntax-Ident name loc) (Ok (Identifier name loc)))
        (_ (fail (syntax-loc syntax) "expected an identifier"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-outline)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail stage0 testing))
    (begin
      (define (test-outline)
        (test-defined)
        (test-generated)
        (test-library-forms)
        (test-library-names)
        (test-declarations)
        (test-requirements)
        (test-import-sets)
        (test-import-problems)
        (test-exports)
        (test-library-order)
        (test-programs)
        (test-producers))

      ;; ---- Helpers ----

      ;; Syntax for quoted data, in the file "t.sld" on line 1, each node at
      ;; a column of its own: nodes are numbered in the order they are
      ;; written, a form before its items, so the forms of `((a (b)) c)`
      ;; are `(a (b))` at 1, `a` at 2, `(b)` at 3, `b` at 4 and `c` at 5.
      (define (node number)
        (Loc "t.sld" 1 number))

      (define (forms data)
        (::first (numbered-list data 1)))

      ;; `datum` alone, numbered from `first`.
      (define (numbered first datum)
        (::first (numbering datum first)))

      ;; The Syntax for each datum, numbered from `next`, and the number
      ;; after them.
      (define (numbered-list data next)
        (let loop ((data data)
                   (next next)
                   (made (Nil)))
          (match data
            ((Nil) (Pair (reverse made) next))
            ((Cons datum rest)
             (let ((one (numbering datum next)))
               (loop rest (::second one) (Cons (::first one) made)))))))

      (define (numbering datum next)
        (define (leaf syntax)
          (Pair syntax (+ next 1)))
        (cond ((or (null? datum) (pair? datum))
               (let ((items (numbered-list datum (+ next 1))))
                 (Pair (syntax-Form (::first items) (node next)) (::second items))))
              ((symbol? datum) (leaf (syntax-Ident (symbol->string datum) (node next))))
              ((string? datum) (leaf (syntax-Atom (datum-Text datum) (node next))))
              ((exact-integer? datum) (leaf (syntax-Atom (datum-Integer datum) (node next))))
              ((boolean? datum) (leaf (syntax-Atom (datum-Boolean datum) (node next))))
              (else (panic "no syntax for this datum"))))

      ;; The file "a.sld" read as the library `name`, or as a program.
      (define (library name data)
        (outline (AsLibrary name) "a.sld" (forms data)))

      (define (program data)
        (outline (AsProgram) "a.sld" (forms data)))

      (define (whole library column)
        (Whole library (node column)))

      (define (identifier name column)
        (Identifier name (node column)))

      ;; ---- Libraries ----

      ;; Declarations of each kind join in order, and a library's integer
      ;; name part is its decimal text.
      (define (test-defined)
        (expect (library (list "a" "1")
                  '((define-library (a 1)
                      (export x (rename y z))
                      (import
                       (b)
                       (only (c) p))
                      (begin (define x 1))
                      (import
                       (d))
                      (export w)
                      (begin y))))
                (Ok (Written (Defined (list "a" "1")
                               (list (whole (list "b") 15)
                                     (Only (whole (list "c") 19)
                                           (list (identifier "p" 21))
                                           (node 17))
                                     (whole (list "d") 30))
                               (list (Export (identifier "x" 8) "x")
                                     (Export (identifier "y" 11) "z")
                                     (Export (identifier "w" 34) "w"))
                               (list (numbered 24 '(define x 1)) (numbered 37 'y))
                               (node 1)))))
        (expect (library (list "a") '((define-library (a))))
                (Ok (Written (Defined (list "a") (list) (list) (list) (node 1))))))

      ;; A generated library keeps its recipe's import sets and expression
      ;; as written.
      (define (test-generated)
        (expect (library (list "g") '((generate-library (g) (import
                                                             (x)
                                                             (only (y) z)) (make 1))))
                (Ok (Generated (list "g")
                               (list (numbered 7 '(x)) (numbered 9 '(only (y) z)))
                               (numbered 14 '(make 1))
                               (node 1))))
        (expect (library (list "g") '((generate-library (g) (import) e)))
                (Ok (Generated (list "g") (list) (numbered 7 'e) (node 1)))))

      ;; A library's file holds one form of either shape, or the file as a
      ;; whole is wrong.
      (define (test-library-forms)
        (define (wrong data)
          (expect (library (list "a") data)
                  (fail (Loc "a.sld" 1 1)
                        "expected exactly one define-library or generate-library form")))
        (wrong '())
        (wrong '((define-library (a)) (begin)))
        (wrong '((begin)))
        (wrong '((define-library)))
        (wrong '(define-library (a)))
        (wrong '((generate-library (a) (x) e)))
        (wrong '((generate-library (a) (import))))
        (wrong '((generate-library (a) (import) e f)))
        (wrong '((generate-library (a) e (import)))))

      ;; The reserved name is refused before the declared name is read,
      ;; and a declared name must be the name the library was found by.
      (define (test-library-names)
        (expect (library (list "prim") '((define-library x)))
                (fail (node 1) "the prim library name is reserved for compiler primitives"))
        (expect (library (list "prim") '((generate-library (prim) (import) e)))
                (fail (node 1) "the prim library name is reserved for compiler primitives"))
        (expect (library (list "a") '((define-library x)))
                (fail (node 3) "expected a library name"))
        (expect (library (list "a") '((define-library (a "b" (c)))))
                (fail (node 5) "expected a library name part"))
        (expect (library (list "a" "b") '((define-library (a c))))
                (fail (node 1) "library name does not match its path"))
        (expect (library (list "a") '((define-library (a b))))
                (fail (node 1) "library name does not match its path"))
        (expect (library (list "a" "b") '((define-library (a))))
                (fail (node 1) "library name does not match its path"))
        (expect (library (list "a") '((generate-library (b) (import) e)))
                (fail (node 1) "library name does not match its path"))
        (expect (library (list) '((define-library ())))
                (Ok (Written (Defined (list) (list) (list) (list) (node 1))))))

      ;; A `cond-expand` chooses its first clause that holds, at any depth,
      ;; and reads no clause after it.
      (define (test-declarations)
        (expect (library (list "a")
                  '((define-library (a)
                      (cond-expand ((not snail-core) (import
                                                      (x)))
                                   (snail-core (export y))
                                   (else (bogus))))))
                (Ok (Written (Defined (list "a")
                               (list)
                               (list (Export (identifier "y" 19) "y"))
                               (list)
                               (node 1)))))
        (expect (library (list "a")
                  '((define-library (a)
                      (begin x)
                      (cond-expand (else (begin y) (cond-expand (snail-core (begin z)))))
                      (begin w))))
                (Ok (Written (Defined (list "a")
                               (list)
                               (list)
                               (list (numbered 7 'x)
                                     (numbered 14 'y)
                                     (numbered 21 'z)
                                     (numbered 24 'w))
                               (node 1)))))
        (expect (library (list "a") '((define-library (a) (cond-expand (snail-core) x))))
                (Ok (Written (Defined (list "a") (list) (list) (list) (node 1)))))
        (expect (library (list "a") '((define-library (a) (cond-expand (snail-tests (bogus))))))
                (Ok (Written (Defined (list "a") (list) (list) (list) (node 1)))))
        (expect (library (list "a") '((define-library (a) (include "x") (bogus))))
                (fail (node 5) "expected import, export, begin or cond-expand"))
        (expect (library (list "a") '((define-library (a) x)))
                (fail (node 5) "expected import, export, begin or cond-expand"))
        (expect (library (list "a") '((define-library (a) ())))
                (fail (node 5) "expected import, export, begin or cond-expand"))
        (expect (library (list "a") '((define-library (a) (cond-expand x (else)))))
                (fail (node 7) "expected (requirement declaration ...)"))
        (expect (library (list "a") '((define-library (a) (cond-expand () (else)))))
                (fail (node 7) "expected (requirement declaration ...)"))
        (expect (library (list "a")
                  '((define-library (a) (cond-expand (snail-tests x) (else (bogus))))))
                (fail (node 12) "expected import, export, begin or cond-expand")))

      (define (test-requirements)
        (for-each (lambda (requirement) (expect (holds? (numbered 1 requirement)) #t))
                  '(snail-core else (and) (and snail-core else) (or snail-tests else)
                               (not snail-tests) (not (or)) (and snail-core (not snail-tests))
                               (and else (or snail-core x))))
        (for-each (lambda (requirement) (expect (holds? (numbered 1 requirement)) #f))
                  '(snail-tests chibi (or) (not snail-core) (not) (not x y)
                                (library (snail core base))
                                "snail-core"
                                1
                                ()
                                (and snail-core snail-tests)
                                ((and)) (or (library (a))))))

      ;; ---- Import sets ----

      (define (import-of datum)
        (import-set (numbered 1 datum)))

      ;; A modifier with the arguments it takes modifies the set after it,
      ;; and any other form is a library's name.
      (define (test-import-sets)
        (expect (import-of '(a b)) (Ok (whole (list "a" "b") 1)))
        (expect (import-of '(a 1)) (Ok (whole (list "a" "1") 1)))
        (expect (import-of '()) (Ok (whole (list) 1)))
        (expect (import-of '(only)) (Ok (whole (list "only") 1)))
        (expect (import-of '(except)) (Ok (whole (list "except") 1)))
        (expect (import-of '(prefix)) (Ok (whole (list "prefix") 1)))
        (expect (import-of '(rename)) (Ok (whole (list "rename") 1)))
        (expect (import-of '(only (a) x y))
                (Ok
                 (Only (whole (list "a") 3) (list (identifier "x" 5) (identifier "y" 6)) (node 1))))
        (expect (import-of '(except (a))) (Ok (Except (whole (list "a") 3) (list) (node 1))))
        (expect (import-of '(except (only) x))
                (Ok (Except (whole (list "only") 3) (list (identifier "x" 5)) (node 1))))
        (expect (import-of '(prefix (a) p:)) (Ok (Prefix (whole (list "a") 3) "p:" (node 1))))
        (expect (import-of '(rename (a) (x y) (z w)))
                (Ok (Rename (whole (list "a") 3)
                            (list (Renaming (identifier "x" 6) "y")
                                  (Renaming (identifier "z" 9) "w"))
                            (node 1))))
        (expect (import-of '(rename (prefix (only (a) x) p:) (p:x y)))
                (Ok (Rename (Prefix (Only (whole (list "a") 7) (list (identifier "x" 9)) (node 5))
                                    "p:"
                                    (node 3))
                            (list (Renaming (identifier "p:x" 12) "y"))
                            (node 1)))))

      ;; A modifier's arguments are read before the set it modifies, and a
      ;; modifier without the arguments it takes is read as a name.
      (define (test-import-problems)
        (define (problem datum column message)
          (expect (import-of datum) (fail (node column) message)))
        (problem 'a 1 "expected a library name")
        (problem '(a "b") 3 "expected a library name part")
        (problem '(a (b)) 3 "expected a library name part")
        (problem '(only (a) 1) 5 "expected an identifier")
        (problem '(only x 1) 4 "expected an identifier")
        (problem '(only x y) 3 "expected a library name")
        (problem '(except (a) x (y)) 6 "expected an identifier")
        (problem '(rename x (a)) 4 "expected (name new-name)")
        (problem '(rename (a) (x y z)) 5 "expected (name new-name)")
        (problem '(rename (a) (x 1)) 5 "expected (name new-name)")
        (problem '(rename (a) x) 5 "expected (name new-name)")
        (problem '(rename (a) ()) 5 "expected (name new-name)")
        (problem '(prefix x p) 3 "expected a library name")
        (problem '(prefix (a)) 3 "expected a library name part")
        (problem '(prefix (a) p q) 3 "expected a library name part")
        (problem '(prefix (a) "p") 3 "expected a library name part")
        (problem '(only (prefix (a)) x) 5 "expected a library name part"))

      ;; ---- Exports ----

      (define (test-exports)
        (define (export-of datum)
          (export-spec (numbered 1 datum)))
        (expect (export-of 'x) (Ok (Export (identifier "x" 1) "x")))
        (expect (export-of '(rename x y)) (Ok (Export (identifier "x" 3) "y")))
        (expect (export-of '(rename (x) y)) (fail (node 3) "expected an identifier"))
        (expect (export-of '(rename 1 y)) (fail (node 3) "expected an identifier"))
        (for-each (lambda (datum)
                    (expect (export-of datum) (fail (node 1) "expected an export specification")))
                  '((rename x) (rename x y z) (rename x 1) (other x y) 1 () "x")))

      ;; The name is read first, then the declarations, then the import
      ;; sets, then the exports.
      (define (test-library-order)
        (expect (library (list "a") '((define-library (a b) (bogus))))
                (fail (node 1) "library name does not match its path"))
        (expect (library (list "a") '((define-library (a) (export 1) (import 2) (bogus))))
                (fail (node 11) "expected import, export, begin or cond-expand"))
        (expect (library (list "a") '((define-library (a) (export 1) (import 2))))
                (fail (node 10) "expected a library name"))
        (expect (library (list "a") '((define-library (a) (export 1 x) (import
                                                                        (b)))))
                (fail (node 7) "expected an export specification")))

      ;; ---- Programs ----

      ;; A program's leading `import` forms join, and its body is every form
      ;; after them; a library's form read as a program is its body.
      (define (test-programs)
        (expect (program '()) (Ok (Written (Program (list) (None) (list) (list)))))
        (expect (program '((import
                            (a)
                            (b)) (import
                                  (c)) (define x 1) (import
                                                     (d))))
                (Ok (Written (Program (list)
                                      (None)
                                      (list (whole (list "a") 3)
                                            (whole (list "b") 5)
                                            (whole (list "c") 9))
                                      (list (numbered 11 '(define x 1)) (numbered 15 '(import
                                                                                       (d))))))))
        (expect (program '((define-library (a))))
                (Ok (Written
                     (Program (list) (None) (list) (list (numbered 1 '(define-library (a))))))))
        (expect (program '((import
                            (only (a) 1)))) (fail (node 7) "expected an identifier"))
        (expect (program '((import x))) (fail (node 3) "expected a library name")))

      ;; A printed producer names the libraries loading as it starts, and
      ;; its recipe's file; `recipe` is a recipe only in such a program.
      (define (test-producers)
        (expect (program '((generating "a.b" "c") (import
                                                   (x)) (recipe "lib/r.sld") (run)))
                (Ok (Written (Program (list "a.b" "c")
                                      (Some "lib/r.sld")
                                      (list (whole (list "x") 7))
                                      (list (numbered 12 '(run)))))))
        (expect (program '((recipe "r.sld") (run)))
                (Ok (Written (Program (list)
                                      (None)
                                      (list)
                                      (list (numbered 1 '(recipe "r.sld")) (numbered 4 '(run)))))))
        (expect (program '((generating) (recipe "r.sld")))
                (Ok (Written (Program (list) (None) (list) (list (numbered 3 '(recipe "r.sld")))))))
        (expect (program '((generating "k") (recipe "r.sld" x)))
                (Ok (Written
                     (Program (list "k") (None) (list) (list (numbered 4 '(recipe "r.sld" x)))))))
        (expect (program '((generating "k") (recipe r)))
                (Ok (Written (Program (list "k") (None) (list) (list (numbered 4 '(recipe r)))))))
        (expect (program '((import
                            (x)) (generating "k")))
                (Ok (Written (Program (list)
                                      (None)
                                      (list (whole (list "x") 3))
                                      (list (numbered 5 '(generating "k")))))))
        (expect (program '((generating "k" a))) (fail (node 4) "expected a library key string"))
        (expect (program '((generating 1) (import 2)))
                (fail (node 3) "expected a library key string")))))
   (else)))
