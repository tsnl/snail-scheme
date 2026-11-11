;; The passes `include` and `outline` beside the old compiler, for as long
;; as both exist. No old function does the work of either alone: the old
;; compiler includes bytes as it reads a file, reads a library's
;; declarations in `library-file` and a program's import sets in
;; `program-imports`, and reads each import set and export only as its
;; expander loads the library. So there are two comparisons, which
;; tests/compiler.scm runs.
;;
;; - Every tracked file, outlined after `read` and `include`, beside what
;;   `library-file` or `program-imports` reads of it, with each import set
;;   also beside the library the old closure walk visits for it.
;; - The headers below, beside the first problem the old expander finds
;;   when it loads them, which the outline predicts. These cover what
;;   only the expander checks: includes, import sets and exports.
;;
;; The comparisons read and write files, as the old functions they call do.
(define-library (snail compiler adapter outline)
  (export
   Comparison
   Agreed
   Differed
   Uncompared
   as-comparison
   stop-comparison
   only-old-stops
   only-new-stops
   feedback-text
   file-comparison
   Header
   LibraryHeader
   ProgramHeader
   malformed-headers
   header-comparison)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler read pass)
   (prefix (snail compiler read language) syntax-)
   (snail compiler read location)
   (snail compiler include paths)
   (snail compiler include pass)
   (snail compiler outline language)
   (snail compiler outline pass)
   (snail compiler outline imports)
   (snail compiler outline names)
   (snail compiler adapter read)
   (prefix (only (snail shell compiler read)
                 Loc
                 Syntax
                 Atom
                 Ident
                 Form
                 DInt
                 syntax-loc
                 loc->string
                 SourceDiagnostic
                 diagnostics->list
                 diagnostics->string
                 diagnostic->string
                 compile
                 compile-error
                 Stop
                 Failed
                 Requested
                 compiling)
           old:)
   (prefix (only (snail shell compiler expand)
                 LibraryFile
                 DefinedLibrary
                 GeneratedLibrary
                 library-file
                 program-imports
                 library-closure
                 expand-program
                 empty-expansion)
           old:)
   (prefix (only (snail shell compiler inputs)
                 no-inputs
                 generating-stack
                 read-source-file)
           old:))
  (begin

    ;; ---- Comparisons ----

    ;; What one comparison found: agreement, the first difference, or why
    ;; the two could not be compared.
    (enum Comparison
      (Agreed)
      (Differed
       ((difference String)))
      (Uncompared
       ((reason String))))

    (: as-comparison (impl (Fn (Option String) -> Comparison)))
    (define (as-comparison difference)
      (match difference
        ((Some text) (Differed text))
        ((None) (Agreed))))

    ;; Both stopped: the same feedback, in the same order, is agreement.
    (: stop-comparison (impl (Fn (List Feedback) old:Stop -> Comparison)))
    (define (stop-comparison feedback stop)
      (match stop
        ((old:Failed diagnostics)
         (as-comparison (feedback-difference (map feedback->old feedback)
                                             (old:diagnostics->list diagnostics))))
        ((old:Requested _) (Differed "the old compiler asked for an input"))))

    (: only-old-stops (impl (Fn old:Stop -> Comparison)))
    (define (only-old-stops stop)
      (match stop
        ((old:Failed diagnostics)
         (Differed (string-append "only the old compiler rejects it: "
                                  (old:diagnostics->string diagnostics))))
        ((old:Requested _) (Differed "the old compiler asked for an input"))))

    (: only-new-stops (impl (Fn (List Feedback) -> Comparison)))
    (define (only-new-stops feedback)
      (Differed (string-append "only the new compiler rejects it: " (feedback-text feedback))))

    (: feedback-text (impl (Fn (List Feedback) -> String)))
    (define (feedback-text feedback)
      (string-join (map (lambda (one) (old:diagnostic->string (feedback->old one))) feedback) "; "))

    ;; The first difference found, in the order the checks are listed.
    (: first-difference-of (impl (Fn (List (Option String)) -> (Option String))))
    (define (first-difference-of differences)
      (match differences
        ((Nil) (None))
        ((Cons (Some difference) _) (Some difference))
        ((Cons (None) rest) (first-difference-of rest))))

    ;; ---- The new passes ----

    ;; What `read`, `include` and `outline` make of the file at `path`,
    ;; whose text is `text`, given the bytes of each file it includes that
    ;; exists.
    (: new-outline
       (impl (Fn Reading String String -> (Result Outline (List Feedback)) ! fs)))
    (define (new-outline reading path text)
      (result-let* ((forms (read path text))
                    (included (include forms (included-files forms))))
        (outline reading path included)))

    (: included-files (impl (Fn (List syntax-Syntax) -> (Table Bytes) ! fs)))
    (define (included-files forms)
      (fold-left (lambda (files path)
                   (if (file-exists? path) (table-set files path (read-bytes path)) files))
                 empty-table
                 (included-paths forms)))

    ;; ---- Tracked files ----

    ;; The file at `path` as the library its one form declares, when the
    ;; path ends with that library's, and else as a program. A file that
    ;; does not read, or whose includes fail, has no outline to compare:
    ;; the reader has its own comparison, and the old compiler includes
    ;; nothing in what these functions read.
    (: file-comparison (impl (Fn String -> Comparison ! fs)))
    (define (file-comparison path)
      (let ((text (read-file path)))
        (match (read path text)
          ((Err _) (Uncompared "it does not read"))
          ((Ok forms)
           (match (include forms (included-files forms))
             ((Err feedback)
              (Uncompared (string-append "include stops it: " (feedback-text feedback))))
             ((Ok _)
              (match (found-library path forms)
                ((Some found) (library-comparison path text found))
                ((None) (program-comparison path text)))))))))

    ;; Where the old compiler finds a library: the search directory, and
    ;; the name under it.
    (struct Found
      ((directory String)
       (name LibraryName)))

    (: found-library (impl (Fn String (List syntax-Syntax) -> (Option Found))))
    (define (found-library path forms)
      (match forms
        ((Cons (syntax-Form (Cons (syntax-Ident head _) (Cons (syntax-Form parts _) _)) _) (Nil))
         (if (or (string=? head "define-library") (string=? head "generate-library"))
             (match (plain-name parts)
               ((Some name) (directory-of path name))
               ((None) (None)))
             (None)))
        (_ (None))))

    ;; A library name of names and integers, as the outline reads it.
    (: plain-name (impl (Fn (List syntax-Syntax) -> (Option LibraryName))))
    (define (plain-name parts)
      (match parts
        ((Nil) (Some (Nil)))
        ((Cons (syntax-Ident name _) rest) (name-after name (plain-name rest)))
        ((Cons (syntax-Atom (syntax-Integer integer) _) rest)
         (name-after (i64->string integer) (plain-name rest)))
        (_ (None))))

    (: name-after (impl (Fn String (Option LibraryName) -> (Option LibraryName))))
    (define (name-after part rest)
      (match rest
        ((Some parts) (Some (Cons part parts)))
        ((None) (None))))

    ;; The directory in which `path` is the file of `name`, if it is.
    (: directory-of (impl (Fn String LibraryName -> (Option Found))))
    (define (directory-of path name)
      (let* ((chars (string->vector path))
             (file (string-append "/" (string-join name "/") ".sld"))
             (start (- (vector-length chars) (vector-length (string->vector file)))))
        (if (and (> start 0)
                 (string=? (vector->string (subvector chars start (vector-length chars))) file))
            (Some (Found (vector->string (subvector chars 0 start)) name))
            (None))))

    ;; ---- Libraries ----

    (: library-comparison (impl (Fn String String Found -> Comparison ! fs)))
    (define (library-comparison path text found)
      (let ((new (new-outline (AsLibrary (::name found)) path text))
            (old (old:compiling (lambda ()
                                  (old:library-file (list (::directory found))
                                                    (::name found)
                                                    (old:Loc path 1 1))))))
        (match (Pair new old)
          ((Pair (Ok outline) (Ok file)) (as-comparison (library-difference outline file)))
          ((Pair (Ok _) (Err stop)) (only-old-stops stop))
          ((Pair (Err feedback) (Ok _)) (only-new-stops feedback))
          ((Pair (Err feedback) (Err stop)) (stop-comparison feedback stop)))))

    (: library-difference (impl (Fn Outline old:LibraryFile -> (Option String) ! fs)))
    (define (library-difference outline file)
      (match (Pair outline file)
        ((Pair (Written (Defined _ imports exports body _)) (old:DefinedLibrary sections))
         (let ((specs (section-items sections "import")))
           (first-difference-of
            (list (sets-difference imports specs)
                  (walks-difference (imported-libraries outline) specs)
                  (exports-difference exports (section-items sections "export"))
                  (items-difference "the body"
                                    (map syntax->old body)
                                    (section-items sections "begin"))))))
        ((Pair (Generated _ imports expression loc) (old:GeneratedLibrary forms output))
         (producer-difference imports expression loc forms output))
        (_ (Some "the new compiler reads another kind of library"))))

    (: section-items
       (impl (Fn (List (Pair String (List old:Syntax))) String -> (List old:Syntax))))
    (define (section-items sections kind)
      (concatenate
       (map ::second (filter (lambda (section) (string=? (::first section) kind)) sections))))

    ;; The old reading of a generated library is the producer program it
    ;; builds at the library's form: an `import` form of the recipe's sets
    ;; and its own, `(recipe "file")`, and a call of a function returning
    ;; the recipe's expression. Its output goes where the expression is.
    (: producer-difference
       (impl
        (Fn (List syntax-Syntax) syntax-Syntax Loc (List old:Syntax) old:Loc -> (Option String))))
    (define (producer-difference imports expression loc forms output)
      (match forms
        ((Cons (old:Form (Cons _ specs) import-loc)
               (Cons _
                     (Cons (old:Form
                            (Cons _ (Cons (old:Form (Cons _ (Cons _ (Cons body (Nil)))) _) (Nil)))
                            _)
                           (Nil))))
         (first-difference-of
          (list (loc-difference loc import-loc)
                (items-difference "the recipe's imports"
                                  (map syntax->old imports)
                                  (take specs (- (length specs) 1)))
                (items-difference "the recipe's expression"
                                  (list (syntax->old expression))
                                  (list body))
                (loc-difference (syntax-loc expression) output))))
        (_ (Some "the old producer program has another shape"))))

    ;; ---- Programs ----

    ;; A program's outline beside the libraries its `generating` form names
    ;; and the import sets `program-imports` finds after it, which is how
    ;; the old planner reads an entry. No old export reads a program's
    ;; recipe or body alone, so the unit tests alone judge those.
    (: program-comparison (impl (Fn String String -> Comparison ! fs)))
    (define (program-comparison path text)
      (let ((new (new-outline (AsProgram) path text))
            (old (old:compiling (lambda () (old-program path)))))
        (match (Pair new old)
          ((Pair (Ok outline) (Ok program)) (as-comparison (program-difference outline program)))
          ((Pair (Ok _) (Err stop)) (only-old-stops stop))
          ((Pair (Err feedback) (Ok _)) (only-new-stops feedback))
          ((Pair (Err feedback) (Err stop)) (stop-comparison feedback stop)))))

    (: old-program (impl (Fn String -> (Pair (List String) (List old:Syntax)) ! fs old:compile)))
    (define (old-program path)
      (let ((source (old:generating-stack (old:read-source-file path))))
        (Pair (::first source) (old:program-imports (::second source)))))

    (: program-difference
       (impl (Fn Outline (Pair (List String) (List old:Syntax)) -> (Option String) ! fs)))
    (define (program-difference outline program)
      (match outline
        ((Written (Program loading _ imports _))
         (first-difference-of
          (list (if (string=? (string-join loading " ") (string-join (::first program) " "))
                    (None)
                    (Some "the new compiler reads other libraries loading"))
                (sets-difference imports (::second program))
                (walks-difference (imported-libraries outline) (::second program)))))
        (_ (Some "the new compiler reads it as a library"))))

    ;; ---- Import sets ----

    (: sets-difference (impl (Fn (List Import) (List old:Syntax) -> (Option String))))
    (define (sets-difference imports specs)
      (if (= (length imports) (length specs))
          (first-difference-of (map (lambda (pair) (set-difference (::first pair) (::second pair)))
                                    (zip imports specs)))
          (Some (string-append "the new compiler reads "
                               (i64->string (length imports))
                               " import sets, the old "
                               (i64->string (length specs))))))

    ;; Where an import set differs from the syntax it was read from: its
    ;; kind, its place, its names, or the set it modifies.
    (: set-difference (impl (Fn Import old:Syntax -> (Option String))))
    (define (set-difference import spec)
      (match (Pair import spec)
        ((Pair (Whole library loc) (old:Form parts old-loc))
         (first-difference-of (list (loc-difference loc old-loc)
                                    (name-difference library parts old-loc))))
        ((Pair (Only inner names loc)
               (old:Form (Cons (old:Ident "only" _ _) (Cons old-inner idents)) old-loc))
         (first-difference-of (list (loc-difference loc old-loc)
                                    (identifiers-difference names idents)
                                    (set-difference inner old-inner))))
        ((Pair (Except inner names loc)
               (old:Form (Cons (old:Ident "except" _ _) (Cons old-inner idents)) old-loc))
         (first-difference-of (list (loc-difference loc old-loc)
                                    (identifiers-difference names idents)
                                    (set-difference inner old-inner))))
        ((Pair (Prefix inner prefix loc)
               (old:Form (Cons (old:Ident "prefix" _ _)
                               (Cons old-inner (Cons (old:Ident old-prefix _ _) (Nil))))
                         old-loc))
         (first-difference-of (list (loc-difference loc old-loc)
                                    (text-difference prefix old-prefix old-loc)
                                    (set-difference inner old-inner))))
        ((Pair (Rename inner renamings loc)
               (old:Form (Cons (old:Ident "rename" _ _) (Cons old-inner pairs)) old-loc))
         (first-difference-of (list (loc-difference loc old-loc)
                                    (renamings-difference renamings pairs)
                                    (set-difference inner old-inner))))
        (_ (Some (string-append (old:loc->string (old:syntax-loc spec))
                                ": the new compiler reads this import set otherwise")))))

    (: name-difference (impl (Fn LibraryName (List old:Syntax) old:Loc -> (Option String))))
    (define (name-difference library parts loc)
      (text-difference (written-name library) (written-name (map part-text parts)) loc))

    (: part-text (impl (Fn old:Syntax -> String)))
    (define (part-text part)
      (match part
        ((old:Ident name _ _) name)
        ((old:Atom (old:DInt integer) _) (i64->string integer))
        (_ "(not a part)")))

    (: renamings-difference (impl (Fn (List Renaming) (List old:Syntax) -> (Option String))))
    (define (renamings-difference renamings pairs)
      (if (= (length renamings) (length pairs))
          (first-difference-of
           (map (lambda (pair) (renaming-difference (::first pair) (::second pair)))
                (zip renamings pairs)))
          (Some "the new compiler reads another number of renamings")))

    (: renaming-difference (impl (Fn Renaming old:Syntax -> (Option String))))
    (define (renaming-difference renaming pair)
      (match pair
        ((old:Form (Cons from (Cons (old:Ident to _ _) (Nil))) loc)
         (first-difference-of (list (identifier-difference (::identifier renaming) from)
                                    (text-difference (::name renaming) to loc))))
        (_ (Some (string-append (old:loc->string (old:syntax-loc pair))
                                ": the new compiler reads a renaming here")))))

    ;; Each import set's library beside the old walk from that set alone.
    ;; The walk searches no directory, so it reports the first library it
    ;; would read as missing, where the whole set is written, or reads
    ;; nothing for the compiler's own (snail core forms). Where each set and
    ;; name is written is compared with the sets themselves.
    (: walks-difference (impl (Fn (List Imported) (List old:Syntax) -> (Option String) ! fs)))
    (define (walks-difference imported specs)
      (if (= (length imported) (length specs))
          (first-difference-of (map (lambda (pair) (walk-difference (::first pair) (::second pair)))
                                    (zip imported specs)))
          (Some "the query names another number of libraries")))

    (: walk-difference (impl (Fn Imported old:Syntax -> (Option String) ! fs)))
    (define (walk-difference imported spec)
      (match (old:compiling (lambda () (old:library-closure (Nil) old:no-inputs (Nil) (list spec))))
        ((Ok _) (feedback-difference (walk-stops imported spec) (Nil)))
        ((Err (old:Failed diagnostics))
         (feedback-difference (walk-stops imported spec) (old:diagnostics->list diagnostics)))
        ((Err (old:Requested _)) (Some "the old walk asked for an input"))))

    (: walk-stops (impl (Fn Imported old:Syntax -> (List old:SourceDiagnostic))))
    (define (walk-stops imported spec)
      (if (same-library? (::library imported) (list "snail" "core" "forms"))
          (Nil)
          (list (old:SourceDiagnostic (old:syntax-loc spec)
                                      (::message (missing-library (::library imported)
                                                                  (::loc imported)))))))

    ;; What the old compiler says of a library it cannot find.
    (: missing-library (impl (Fn LibraryName Loc -> Feedback)))
    (define (missing-library library loc)
      (Feedback loc (string-append "library not found: " (written-name library))))

    ;; ---- Exports ----

    (: exports-difference (impl (Fn (List Export) (List old:Syntax) -> (Option String))))
    (define (exports-difference exports specs)
      (if (= (length exports) (length specs))
          (first-difference-of
           (map (lambda (pair) (export-difference (::first pair) (::second pair)))
                (zip exports specs)))
          (Some "the new compiler reads another number of exports")))

    (: export-difference (impl (Fn Export old:Syntax -> (Option String))))
    (define (export-difference exported spec)
      (match spec
        ((old:Ident name _ loc)
         (first-difference-of (list (identifier-difference (::identifier exported) spec)
                                    (text-difference (::name exported) name loc))))
        ((old:Form (Cons _ (Cons inner (Cons (old:Ident outer _ _) (Nil)))) loc)
         (first-difference-of (list (identifier-difference (::identifier exported) inner)
                                    (text-difference (::name exported) outer loc))))
        (_ (Some (string-append (old:loc->string (old:syntax-loc spec))
                                ": the new compiler reads an export here")))))

    ;; ---- Names and places ----

    (: identifiers-difference (impl (Fn (List Identifier) (List old:Syntax) -> (Option String))))
    (define (identifiers-difference identifiers idents)
      (if (= (length identifiers) (length idents))
          (first-difference-of
           (map (lambda (pair) (identifier-difference (::first pair) (::second pair)))
                (zip identifiers idents)))
          (Some "the new compiler reads another number of names")))

    (: identifier-difference (impl (Fn Identifier old:Syntax -> (Option String))))
    (define (identifier-difference identifier ident)
      (match ident
        ((old:Ident name _ loc)
         (first-difference-of (list (loc-difference (::loc identifier) loc)
                                    (text-difference (::name identifier) name loc))))
        (_ (Some (string-append (old:loc->string (old:syntax-loc ident))
                                ": the new compiler reads an identifier here")))))

    (: text-difference (impl (Fn String String old:Loc -> (Option String))))
    (define (text-difference new old loc)
      (if (string=? new old)
          (None)
          (Some (string-append (old:loc->string loc)
                               ": the new compiler reads "
                               new
                               ", the old "
                               old))))

    (: loc-difference (impl (Fn Loc old:Loc -> (Option String))))
    (define (loc-difference loc old)
      (if (and (string=? (::file loc) (::file old))
               (= (::line loc) (::line old))
               (= (::column loc) (::column old)))
          (None)
          (Some (string-append (old:loc->string old)
                               ": the new compiler places this at "
                               (old:loc->string (loc->old loc))))))

    ;; ---- Malformed headers ----

    ;; A header compared with the old expander, which reads one as it
    ;; loads it. A library's text is the file of (sample header), which
    ;; the program `(import (sample header))` loads; a program's is the
    ;; program. Each is written in a directory that also holds the file
    ;; `included.txt`, for the headers that include it.
    (enum Header
      (LibraryHeader
       ((text String)))
      (ProgramHeader
       ((text String))))

    ;; The comparison of `header`, written in `directory`, whose `sample`
    ;; directory exists.
    (: header-comparison (impl (Fn String Header -> Comparison ! fs)))
    (define (header-comparison directory header)
      (let ((main (string-append directory "/main.sld")))
        (write-file (string-append directory "/included.txt") "included")
        (match header
          ((LibraryHeader text)
           (let ((path (string-append directory "/sample/header.sld")))
             (write-file path text)
             (write-file main "(import (sample header))\n")
             (expansion-comparison directory
                                   main
                                   (new-outline (AsLibrary (list "sample" "header")) path text))))
          ((ProgramHeader text)
           (write-file main text)
           (expansion-comparison directory main (new-outline (AsProgram) main text))))))

    ;; The old expander's verdict on the program at `main` beside the one
    ;; the outline predicts.
    (: expansion-comparison
       (impl (Fn String String (Result Outline (List Feedback)) -> Comparison ! fs)))
    (define (expansion-comparison directory main new)
      (let ((old (old:compiling
                  (lambda ()
                    (old:expand-program (list directory)
                                        (lambda (loading forms) (no-producer directory))
                                        old:no-inputs
                                        main
                                        old:empty-expansion)))))
        (match (Pair (predicted-stop directory new) old)
          ((Pair (None) _) (Uncompared "the outline predicts no problem with it"))
          ((Pair (Some feedback) (Ok _)) (only-new-stops feedback))
          ((Pair (Some feedback) (Err stop)) (stop-comparison feedback stop)))))

    ;; The comparison runs no producer program, and says so.
    (: no-producer (All (T) (impl (Fn String -> T ! old:compile))))
    (define (no-producer directory)
      (old:compile-error (old:Loc directory 0 0) "the comparison runs no producer"))

    ;; The first problem the old expander finds with what was outlined: the
    ;; outline's own, or else the first imported library, which is missing,
    ;; or a library's first export, when it imports nothing and defines
    ;; nothing, or the producer a generated library asks for.
    (: predicted-stop
       (impl (Fn String (Result Outline (List Feedback)) -> (Option (List Feedback)))))
    (define (predicted-stop directory new)
      (match new
        ((Err feedback) (Some feedback))
        ((Ok outline)
         (match (imported-libraries outline)
           ((Cons first _) (Some (list (missing-library (::library first) (::loc first)))))
           ((Nil) (unimported-stop directory outline))))))

    (: unimported-stop (impl (Fn String Outline -> (Option (List Feedback)))))
    (define (unimported-stop directory outline)
      (match outline
        ((Written (Defined _ _ (Cons first-export _) (Nil) _))
         (Some (list (undefined-export (::identifier first-export)))))
        ((Generated _ _ _ _)
         (Some (list (Feedback (Loc directory 0 0) "the comparison runs no producer"))))
        (_ (None))))

    (: undefined-export (impl (Fn Identifier -> Feedback)))
    (define (undefined-export identifier)
      (Feedback (::loc identifier)
                (string-append "exported name is not defined: " (::name identifier))))

    ;; Headers that are malformed, or that the outline accepts and the
    ;; expander then stops on. Each has one problem, or its first problem
    ;; is in its first import set: the expander loads each set's library
    ;; before it reads the next set, and reads exports after the body, so
    ;; of two problems it may meet the outline's second first.
    (: malformed-headers (List Header))
    (define malformed-headers
      (list (LibraryHeader "")
            (LibraryHeader "(define-library (sample header)) (begin)")
            (LibraryHeader "(begin)")
            (LibraryHeader "(define-library)")
            (LibraryHeader "(generate-library (sample header) (x) e)")
            (LibraryHeader "(generate-library (sample header) (import))")
            (LibraryHeader "(define-library sample)")
            (LibraryHeader "(define-library (sample \"header\"))")
            (LibraryHeader "(define-library (sample other))")
            (LibraryHeader "(define-library (sample header extra))")
            (LibraryHeader "(generate-library (sample other) (import) (unit))")
            (LibraryHeader "(define-library (sample header) (include \"x\"))")
            (LibraryHeader "(define-library (sample header) x)")
            (LibraryHeader "(define-library (sample header) ())")
            (LibraryHeader "(define-library (sample header) (cond-expand x))")
            (LibraryHeader "(define-library (sample header) (cond-expand ()))")
            (LibraryHeader
             "(define-library (sample header)\n  (cond-expand (snail-tests (import (a))) (else (bogus))))")
            (LibraryHeader
             "(define-library (sample header)\n  (cond-expand ((and snail-core (not snail-tests)) (export 1))))")
            (LibraryHeader
             "(define-library (sample header)\n  (cond-expand ((or) (bogus)) (snail-core (import (only (a) 1)))))")
            (LibraryHeader "(define-library (sample header) (import (only (a) x 1)))")
            (LibraryHeader "(define-library (sample header) (import (rename (a) (x))))")
            (LibraryHeader "(define-library (sample header) (import (rename x (a b c))))")
            (LibraryHeader "(define-library (sample header) (import (prefix (a))))")
            (LibraryHeader "(define-library (sample header) (import (prefix x p)))")
            (LibraryHeader "(define-library (sample header) (import (except (only) 1)))")
            (LibraryHeader "(define-library (sample header) (import a))")
            (LibraryHeader "(define-library (sample header) (export (rename (x) y)))")
            (LibraryHeader "(define-library (sample header) (export (rename x)))")
            (LibraryHeader "(define-library (sample header) (export \"x\"))")
            (LibraryHeader "(define-library (sample header) (import (only)))")
            (LibraryHeader
             "(define-library (sample header)\n  (import (rename (prefix (only (a 1) x) p:) (p:x y))))")
            (LibraryHeader "(define-library (sample header) (export x (rename y z)))")
            (LibraryHeader "(define-library (sample header) (export (rename y z)))")
            (LibraryHeader
             "(define-library (sample header) (cond-expand (snail-core)) (import (b)))")
            (LibraryHeader "(generate-library (sample header) (import (a)) (unit))")
            (LibraryHeader
             "(define-library (sample header)\n  (import (a))\n  (begin (f (include-bytes \"../included.txt\"))))")
            (LibraryHeader
             "(define-library (sample header) (begin (include-bytes \"missing.bin\")))")
            (ProgramHeader "(import (only (a) 1))")
            (ProgramHeader "(import (only x 1))")
            (ProgramHeader "(import (except x 1))")
            (ProgramHeader "(import (rename x (a)))")
            (ProgramHeader "(import (only (prefix x p) y))")
            (ProgramHeader "(import x)")
            (ProgramHeader "(import (prefix (a) p q))")
            (ProgramHeader "(import (only (a) \"x\"))")
            (ProgramHeader "(generating a) (import (a))")
            (ProgramHeader "(generating \"k\" 1)")
            (ProgramHeader "(generating \"k\") (import (only))")
            (ProgramHeader "(import (except (a b) x y))")
            (ProgramHeader "(import (rename (a) (x y)) (only (b) z))")
            (ProgramHeader "(import) (import (prefix (c) p:))")
            (ProgramHeader "(import ())")
            (ProgramHeader "(import (rename))")
            (ProgramHeader "(import (prefix x))")
            (ProgramHeader "(import (a))\n(define x (include-bytes \"missing.bin\"))")
            (ProgramHeader "(include-bytes)")
            (ProgramHeader "(import (a)) (include-bytes \"included.txt\" \"x\")")
            (ProgramHeader "(import (a)) '(include-bytes \"included.txt\")")
            (ProgramHeader "(include-bytes \"/nonexistent/abs.bin\")")
            (ProgramHeader "(import (only (a) 1)) (include-bytes 1)")))

    ))
