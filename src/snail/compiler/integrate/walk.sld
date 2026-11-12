;; How loading proceeds, decided without the file system: which library
;; to read next, which imports need nothing, when an import leads back to
;; a library still loading, what a generated library's producer is and
;; when its library waits for it, and the order the libraries come in.
;; The walk visits imports depth first, in the order they are written, as
;; the old expander loads them. It asks for each library it needs, and the
;; loader (snail compiler integrate load) reads the library and hands its
;; outline back. A generated library's file holds a recipe, not the
;; library, so once it is read the walk asks for its producer's output in
;; turn: the loader hands back the library the output declares, which
;; stands in its place and whose imports are visited next, or says the
;; output is not there yet, and the library waits for its producer while
;; loading goes on past it. Last, once every library is loaded, the walk
;; decides which of them a library's imports reach, and so the offers a
;; library's expansion is handed.
(define-library (snail compiler integrate walk)
  (export
   Outlined
   LoadedFile
   loaded-name
   Producer
   Loaded
   Complete
   Unproduced
   Walk
   Step
   ReadLibrary
   ReadOutput
   Done
   Stopped
   start-walk
   next-step
   entered
   unproduced
   Importer
   reached-libraries
   OfferingLibrary
   reached-offers)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read location)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler names libraries)
   (snail compiler outline producer)
   (only (snail compiler expand offer) Offered Offer))
  (begin

    ;; ---- Loaded programs ----

    ;; A file, read with its inclusions and outlined.
    (struct Outlined
      ((file String)
       (outline Outline)))

    ;; A library loaded: the file it is written in and the library. A
    ;; generated library's is its producer's output, which is placed in its
    ;; recipe's file.
    (struct LoadedFile
      ((file String)
       (library Library)))

    ;; The name of the library a loaded file holds; a program's is the
    ;; library its Globals are of.
    (: loaded-name (impl (Fn LoadedFile -> LibraryName)))
    (define (loaded-name loaded)
      (match (::library loaded)
        ((Defined name _ _ _ _) name)
        ((Program _ _ _ _) program-library)))

    ;; A generated library whose producer's output is not there: the
    ;; library; the key the producer is printed under, GENERATED/KEY.sld,
    ;; and its output read from, GENERATED/KEY.syntax; the text to print;
    ;; and the keys of the libraries loading as the walk reached it,
    ;; innermost first and itself among them, which the text's first line
    ;; names, `(generating "sample.knot" ...)`.
    (struct Producer
      ((library LibraryName)
       (key String)
       (text String)
       (loading (List String))))

    ;; What loading a program found: the program and every library its
    ;; imports reach, except (snail core forms), which has no file, each
    ;; once, after every library it imports, and the program last; or,
    ;; when the output of a generated library it reaches is not there,
    ;; each such library's producer, in the order reached.
    (enum Loaded
      (Complete
       ((files (List LoadedFile))))
      (Unproduced
       ((producers (List Producer)))))

    ;; ---- Walks ----

    ;; A file loading, and its imports not yet visited.
    (struct Frame
      ((outlined Outlined)
       (pending (List Imported))))

    ;; Where the libraries are found, which a producer's key depends on;
    ;; the files loading, innermost first and the program outermost; the
    ;; keys of the libraries a producer program says were loading as it
    ;; starts; the libraries loaded, latest first; and the producers of the
    ;; generated libraries that wait, latest first.
    (struct Walk
      ((directories (List String))
       (frames (List Frame))
       (keys (List String))
       (finished (List LoadedFile))
       (waiting (List Producer))))

    ;; What the loader does next: read a library, whose import is at
    ;; `loc`, and hand its outline to `entered` with `walk`; read the
    ;; output of `producer`, for the generated library in `file`, and hand
    ;; it, decoded at `loc` and outlined as the library, to `entered` with
    ;; `walk`, or else hand `producer` to `unproduced` with `walk`; or
    ;; nothing more.
    (enum Step
      (ReadLibrary
       ((library LibraryName)
        (loc Loc)
        (walk Walk)))
      (ReadOutput
       ((producer Producer)
        (file String)
        (loc Loc)
        (walk Walk)))
      (Done
       ((loaded Loaded)))
      (Stopped
       ((feedback (List Feedback)))))

    ;; The walk of `program`, whose libraries are found in `directories`.
    (: start-walk (impl (Fn (List String) Outlined -> Walk)))
    (define (start-walk directories program)
      (Walk directories (list (frame-of program)) (program-keys (::outline program)) (Nil) (Nil)))

    (: program-keys (impl (Fn Outline -> (List String))))
    (define (program-keys outline)
      (match outline
        ((Written (Program loading _ _ _)) loading)
        (_ (Nil))))

    ;; The walk once the library it asked for is read, or the output it
    ;; asked for: that library's imports are visited next.
    (: entered (impl (Fn Walk Outlined -> Walk)))
    (define (entered walk library)
      (Walk-frames-set walk (Cons (frame-of library) (::frames walk))))

    ;; The walk once the output it asked for of `producer` is not there:
    ;; the library waits for it, and the walk goes on past it. Nothing the
    ;; output would import is known.
    (: unproduced (impl (Fn Walk Producer -> Walk)))
    (define (unproduced walk producer)
      (Walk-waiting-set walk (Cons producer (::waiting walk))))

    (: frame-of (impl (Fn Outlined -> Frame)))
    (define (frame-of outlined)
      (Frame outlined (imported-libraries (::outline outlined))))

    ;; The next import that needs a library read, after loading every file
    ;; whose imports are all visited.
    (: next-step (impl (Fn Walk -> Step)))
    (define (next-step walk)
      (match (::frames walk)
        ((Nil) (Done (loaded walk)))
        ((Cons frame outer)
         (match (::pending frame)
           ((Nil) (file-visited (Walk-frames-set walk outer) (::outlined frame)))
           ((Cons imported rest)
            (visit (Walk-frames-set walk (Cons (Frame-pending-set frame rest) outer)) imported))))))

    ;; A file whose imports are all visited, taken off the walk: a written
    ;; one is loaded, and a generated one needs its producer's output.
    (: file-visited (impl (Fn Walk Outlined -> Step)))
    (define (file-visited walk outlined)
      (match (::outline outlined)
        ((Written library)
         (next-step (Walk-finished-set walk
                                       (Cons (LoadedFile (::file outlined) library)
                                             (::finished walk)))))
        ((Generated name imports expression loc)
         (ReadOutput (producer-of walk
                                  name
                                  (producer-program (::directories walk)
                                                    (::file outlined)
                                                    imports
                                                    expression
                                                    loc))
                     (::file outlined)
                     (syntax-loc expression)
                     walk))))

    (: loaded (impl (Fn Walk -> Loaded)))
    (define (loaded walk)
      (match (::waiting walk)
        ((Nil) (Complete (reverse (::finished walk))))
        (waiting (Unproduced (reverse waiting)))))

    (: visit (impl (Fn Walk Imported -> Step)))
    (define (visit walk imported)
      (match (import-decision walk (::library imported))
        ((SkipImport) (next-step walk))
        ((ImportCycle) (Stopped (list (cycle-feedback imported))))
        ((ProgramImport) (Stopped (list (program-import-feedback imported))))
        ((LoadImport) (ReadLibrary (::library imported) (::loc imported) walk))))

    ;; ---- Producers ----

    ;; The producer of the generated library `name`, its frame just taken
    ;; off `walk`, with the libraries loading as it was reached: itself,
    ;; then those `walk` still loads.
    (: producer-of (impl (Fn Walk LibraryName ProducerProgram -> Producer)))
    (define (producer-of walk name program)
      (let ((loading (Cons (library-key name) (loading-keys walk))))
        (Producer name (::key program) (printed-producer loading program) loading)))

    ;; The keys of the libraries loading, as a printed producer names them:
    ;; each frame's library, innermost first, then the keys a producer
    ;; program says were loading as it starts. A program is no library.
    (: loading-keys (impl (Fn Walk -> (List String))))
    (define (loading-keys walk)
      (append (concatenate (map (lambda (frame)
                                  (match (outlined-name (::outlined frame))
                                    ((Some name) (list (library-key name)))
                                    ((None) (Nil))))
                                (::frames walk)))
              (::keys walk)))

    ;; ---- Imports ----

    ;; What an import needs, decided in the old expander's order: nothing
    ;; for (snail core forms), which the compiler provides; a problem for
    ;; (main), the program's own name, which no library can have, since
    ;; the program's Globals are of that library; a cycle when the library
    ;; is still loading; nothing when it is loaded, or waits for its
    ;; producer; and else its library read.
    (enum Decision
      (SkipImport)
      (ProgramImport)
      (ImportCycle)
      (LoadImport))

    (: import-decision (impl (Fn Walk LibraryName -> Decision)))
    (define (import-decision walk name)
      (cond ((same-library? name forms-library) (SkipImport))
            ((same-library? name program-library) (ProgramImport))
            ((loading? walk name) (ImportCycle))
            ((or (any? (lambda (file) (same-library? (loaded-name file) name)) (::finished walk))
                 (any? (lambda (producer) (same-library? (::library producer) name))
                       (::waiting walk)))
             (SkipImport))
            (else (LoadImport))))

    ;; A library is loading while a frame holds it, or when a producer
    ;; program names it as loading as it starts. The old driver prints a
    ;; producer's keys as dotted text, so (a.b) and (a b) are one key there,
    ;; as they are to the old compiler.
    (: loading? (impl (Fn Walk LibraryName -> Bool)))
    (define (loading? walk name)
      (or (any? (lambda (frame)
                  (match (outlined-name (::outlined frame))
                    ((Some loading) (same-library? loading name))
                    ((None) #f)))
                (::frames walk))
          (member? (library-key name) (::keys walk))))

    ;; The library a file being loaded declares, or generates.
    (: outlined-name (impl (Fn Outlined -> (Option LibraryName))))
    (define (outlined-name outlined)
      (match (::outline outlined)
        ((Written (Defined name _ _ _ _)) (Some name))
        ((Written (Program _ _ _ _)) (None))
        ((Generated name _ _ _) (Some name))))

    (: program-import-feedback (impl (Fn Imported -> Feedback)))
    (define (program-import-feedback imported)
      (Feedback (::loc imported)
                (string-append "the library name "
                               (library-key (::library imported))
                               " is the program's own")))

    (: cycle-feedback (impl (Fn Imported -> Feedback)))
    (define (cycle-feedback imported)
      (Feedback (::loc imported)
                (string-append "library import cycle through " (library-key (::library imported)))))

    ;; ---- Closures ----

    ;; A library loaded, and the libraries it imports.
    (struct Importer
      ((library LibraryName)
       (imports (List LibraryName))))

    ;; The libraries `names` reach among `importers`, each once, in the
    ;; order a walk first reaches them that takes each name, then the
    ;; libraries it imports, before the next name: the libraries whose
    ;; offers a library's passes are handed for its imports. A name no
    ;; importer has is left out, as (snail core forms) is, which has no
    ;; file.
    (: reached-libraries (impl (Fn (List Importer) (List LibraryName) -> (List LibraryName))))
    (define (reached-libraries importers names)
      (reaching importers names (Nil)))

    ;; `found`, in order, and after it what `names` reach that it lacks.
    (: reaching
       (impl (Fn (List Importer) (List LibraryName) (List LibraryName) -> (List LibraryName))))
    (define (reaching importers names found)
      (match names
        ((Nil) found)
        ((Cons name rest)
         (if (any? (lambda (other) (same-library? other name)) found)
             (reaching importers rest found)
             (match (find (lambda (importer) (same-library? (::library importer) name)) importers)
               ((Some importer)
                (reaching importers
                          rest
                          (reaching importers (::imports importer) (append found (list name)))))
               ((None) (reaching importers rest found)))))))

    ;; A library expanded: its name, the libraries it imports, and what it
    ;; offers their expansion.
    (struct OfferingLibrary
      ((library LibraryName)
       (imports (List LibraryName))
       (offer Offer)))

    ;; The offers of the libraries `imports` reach among `libraries`, each
    ;; once, in the order `reached-libraries` reaches them: what the
    ;; expansion of a library with those imports is handed.
    (: reached-offers (impl (Fn (List OfferingLibrary) (List LibraryName) -> (List Offered))))
    (define (reached-offers libraries imports)
      (concatenate
       (map (lambda (name)
              (match (find (lambda (library) (same-library? (::library library) name)) libraries)
                ((Some library) (list (Offered name (::offer library))))
                ((None) (Nil))))
            (reached-libraries
             (map (lambda (library) (Importer (::library library) (::imports library)))
                  libraries)
             imports))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-walk)
    (import
     (snail core table)
     (only (snail compiler read language) Ident Form)
     (only (snail compiler expand offer) TopScope)
     (snail stage0 testing))
    (begin
      (define (test-walk)
        (test-order)
        (test-decisions)
        (test-cycles)
        (test-producers)
        (test-outputs)
        (test-waiting)
        (test-requests)
        (test-closures))

      ;; ---- Helpers ----

      (define directories (list "lib"))

      ;; The file of a library, where its imports are written.
      (define (file-of name)
        (string-append (string-join name "/") ".sld"))

      (define (at file)
        (Loc file 1 1))

      (define (defined-library name imports)
        (Defined name
          (map (lambda (imported) (Whole imported (at (file-of name)))) imports)
          (list)
          (list)
          (at (file-of name))))

      (define (defined name imports)
        (Outlined (file-of name) (Written (defined-library name imports))))

      (define (loaded-file name imports)
        (LoadedFile (file-of name) (defined-library name imports)))

      ;; A generated library, whose recipe imports nothing and returns
      ;; `(make)`, at column 5, or `(remake)`.
      (define (generated name)
        (generated-by name "make"))

      (define (generated-by name maker)
        (Outlined (file-of name)
                  (Generated name (list) (recipe-expression name maker) (at (file-of name)))))

      (define (recipe-expression name maker)
        (Form (list (Ident maker (Loc (file-of name) 1 6))) (Loc (file-of name) 1 5)))

      ;; Its producer, with the libraries `loading` as keys.
      (define (producer-for name loading)
        (producer-by name "make" loading))

      (define (producer-by name maker loading)
        (let ((program (producer-program directories
                                         (file-of name)
                                         (list)
                                         (recipe-expression name maker)
                                         (at (file-of name)))))
          (Producer name (::key program) (printed-producer loading program) loading)))

      (define (program-library-of loading imports)
        (Program loading
                 (None)
                 (map (lambda (imported) (Whole imported (at "main.sld"))) imports)
                 (list)))

      (define (program loading imports)
        (Outlined "main.sld" (Written (program-library-of loading imports))))

      (define (program-file loading imports)
        (LoadedFile "main.sld" (program-library-of loading imports)))

      ;; The walk from `main` run to its end, reading each library from
      ;; `files` and each output from `outputs`, by its producer's key. A
      ;; library not there stops it, as a missing file would; an output
      ;; not there makes its library wait.
      (define (walked-with files outputs main)
        (let loop ((walk (start-walk directories main)))
          (match (next-step walk)
            ((Done result) (Ok result))
            ((Stopped feedback) (Err feedback))
            ((ReadLibrary library loc next)
             (match (find (lambda (outlined) (names? outlined library)) files)
               ((Some outlined) (loop (entered next outlined)))
               ((None) (fail loc "not among the files"))))
            ((ReadOutput producer file loc next)
             (match (find (lambda (output) (string=? (::first output) (::key producer))) outputs)
               ((Some output) (loop (entered next (::second output))))
               ((None) (loop (unproduced next producer))))))))

      ;; `outlined`, as the output of `producer`, under its key.
      (define (output-of producer outlined)
        (Pair (::key producer) outlined))

      (define (walked files main)
        (walked-with files (list) main))

      (define (names? outlined name)
        (match (outlined-name outlined)
          ((Some named) (same-library? named name))
          ((None) #f)))

      (define (order files main)
        (match (walked files main)
          ((Ok (Complete result)) (Ok (map ::file result)))
          ((Ok (Unproduced producers)) (Ok (map ::library producers)))
          ((Err feedback) (Err feedback))))

      (define a (list "a"))
      (define b (list "b"))
      (define c (list "c"))
      (define d (list "d"))
      (define forms (list "snail" "core" "forms"))

      ;; ---- Cases ----

      ;; Each library comes once, after the libraries it imports, in the
      ;; order imports are written; (snail core forms) never comes.
      (define (test-order)
        (let ((files (list (defined a (list c))
                           (defined b (list c d forms))
                           (defined c (list))
                           (defined d (list forms c)))))
          (expect (order files (program (list) (list a b)))
                  (Ok (list "c.sld" "a.sld" "d.sld" "b.sld" "main.sld")))
          (expect (order files (program (list) (list b a forms b)))
                  (Ok (list "c.sld" "d.sld" "b.sld" "a.sld" "main.sld")))
          (expect (order files (program (list) (list))) (Ok (list "main.sld")))
          (expect (order files (program (list) (list forms))) (Ok (list "main.sld")))
          (expect (walked files (program (list) (list a)))
                  (Ok (Complete (list (loaded-file c (list))
                                      (loaded-file a (list c))
                                      (program-file (list) (list a))))))
          (expect (loaded-name (loaded-file a (list))) a)
          (expect (loaded-name (program-file (list) (list))) (list "main"))))

      ;; Checked in the old expander's order: the builtin library, then a
      ;; library loading, then one loaded or waiting.
      (define (test-decisions)
        (let ((walk (Walk directories
                          (list (Frame (defined a (list b)) (list))
                                (Frame (program (list "k.l") (list a)) (list)))
                          (list "k.l")
                          (list (loaded-file c (list)))
                          (list (producer-for d (list "d"))))))
          (expect (import-decision walk forms) (SkipImport))
          (expect (import-decision walk a) (ImportCycle))
          (expect (import-decision walk (list "k" "l")) (ImportCycle))
          (expect (import-decision walk (list "k.l")) (ImportCycle))
          (expect (import-decision walk c) (SkipImport))
          (expect (import-decision walk d) (SkipImport))
          (expect (import-decision walk b) (LoadImport))
          (expect (import-decision walk (list "main")) (ProgramImport))
          (expect (import-decision walk (list)) (LoadImport))))

      ;; A cycle is reported at the import that closes it, by the old
      ;; compiler's name for the library; a producer's keys are loading.
      (define (test-cycles)
        (define (cycle file key)
          (fail (at file) (string-append "library import cycle through " key)))
        (expect (walked (list (defined a (list a))) (program (list) (list a))) (cycle "a.sld" "a"))
        (expect (walked (list (defined a (list b)) (defined b (list c)) (defined c (list a)))
                        (program (list) (list a)))
                (cycle "c.sld" "a"))
        (expect (walked (list (defined (list "x" "y") (list)))
                        (program (list "x.y") (list (list "x" "y"))))
                (cycle "main.sld" "x.y"))
        (expect
         (order (list (defined (list "x" "y") (list))) (program (list "x.z") (list (list "x" "y"))))
         (Ok (list "x/y.sld" "main.sld")))
        ;; (main) is the program's own name, refused where it is imported,
        ;; by a program or by a library.
        (expect (walked (list (defined (list "main") (list))) (program (list) (list (list "main"))))
                (fail (at "main.sld") "the library name main is the program's own"))
        (expect (walked (list (defined a (list (list "main"))) (defined (list "main") (list)))
                        (program (list) (list a)))
                (fail (at "a.sld") "the library name main is the program's own")))

      ;; A generated library's output is asked for once the library is
      ;; read: its producer, with what was loading, innermost first, a
      ;; program's keys last; its recipe's file; and its expression's place.
      (define (test-producers)
        (match (next-step (entered (Walk directories
                                         (list (Frame (defined a (list b)) (list))
                                               (Frame (program (list "k") (list a)) (list)))
                                         (list "k")
                                         (list)
                                         (list))
                                   (generated b)))
          ((ReadOutput producer file loc next)
           (expect producer (producer-for b (list "b" "a" "k")))
           (expect (::loading producer) (list "b" "a" "k"))
           (expect file "b.sld")
           (expect loc (Loc "b.sld" 1 5))
           (expect (map (lambda (frame) (::file (::outlined frame))) (::frames next))
                   (list "a.sld" "main.sld")))
          (other (expect other "a request for the output of (b)"))))

      ;; An output stands in its library's place: its imports are visited
      ;; next, one that leads back to the library is a cycle, and one that
      ;; is generated again is asked for in turn.
      (define (test-outputs)
        (let ((made (output-of (producer-for b (list "b")) (defined b (list c)))))
          (expect (walked-with (list (generated b) (defined c (list)))
                               (list made)
                               (program (list) (list b)))
                  (Ok (Complete (list (loaded-file c (list))
                                      (loaded-file b (list c))
                                      (program-file (list) (list b))))))
          (expect (walked-with (list (generated b) (defined c (list b)))
                               (list made)
                               (program (list) (list b)))
                  (fail (at "c.sld") "library import cycle through b")))
        (expect (walked-with (list (generated b))
                             (list
                              (output-of (producer-for b (list "b")) (generated-by b "remake")))
                             (program (list) (list b)))
                (Ok (Unproduced (list (producer-by b "remake" (list "b")))))))

      ;; A library whose output is not there waits, and loading goes on
      ;; past it; it is loaded once for each import of it, and nothing it
      ;; would import is known.
      (define (test-waiting)
        (let ((files (list (generated b) (defined a (list b c)) (defined c (list)) (generated d))))
          (expect (walked files (program (list "p") (list b a d b)))
                  (Ok (Unproduced (list (producer-for b (list "b" "p"))
                                        (producer-for d (list "d" "p"))))))
          (expect (order files (program (list) (list a)))
                  (Ok (list (list "b"))))))

      ;; A library is asked for where its name is written, and only when
      ;; it is needed.
      (define (test-requests)
        (match (next-step (start-walk directories (program (list) (list forms a))))
          ((ReadLibrary library loc _) (expect (Pair library loc) (Pair a (at "main.sld"))))
          (other (expect other "a request to read (a)")))
        (expect (walked (list) (program (list) (list a)))
                (fail (at "main.sld") "not among the files")))

      ;; A library's imports reach each library once, in the order first
      ;; reached, each before what it imports; one with no file is left
      ;; out.
      (define (test-closures)
        (let ((importers (list (Importer a (list c d))
                               (Importer b (list c))
                               (Importer c (list d))
                               (Importer d (list)))))
          (expect (reached-libraries importers (list b a)) (list b c d a))
          (expect (reached-libraries importers (list forms a b)) (list a c d b))
          (expect (reached-libraries importers (list)) (list))
          (expect (reached-libraries (list) (list a)) (list))
          (expect (map ::library
                       (reached-offers (map (lambda (importer)
                                              (OfferingLibrary (::library importer)
                                                               (::imports importer)
                                                               no-offer))
                                            importers)
                                       (list forms b a)))
                  (list b c d a))))

      (define no-offer
        (Offer (list) (TopScope empty-table empty-table)))))
   (else)))
