;; How loading proceeds, decided without the file system: which library
;; to read next, which imports need nothing, when an import leads back to
;; a library still loading, and the order the libraries come in. The walk
;; visits imports depth first, in the order they are written, as the old
;; expander loads them. It asks for each library it needs, and the loader
;; (snail compiler integrate load) reads the library and hands its outline
;; back.
(define-library (snail compiler integrate walk)
  (export
   Outlined
   Loaded
   Walk
   Step
   ReadLibrary
   Done
   Stopped
   start-walk
   next-step
   entered)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler outline names))
  (begin

    ;; ---- Loaded programs ----

    ;; A file, read with its inclusions and outlined.
    (struct Outlined
      ((file String)
       (outline Outline)))

    ;; What loading a program found. `files` holds the outline of every
    ;; library its imports reach, except (snail core forms), which has no
    ;; file: each library once, after every library it imports, and the
    ;; program last. A generated library is there, but nothing its
    ;; producer's output would import, since loading reads no output yet:
    ;; `waiting` names each generated library reached, in loading order,
    ;; and the program is loaded completely when it is empty.
    (struct Loaded
      ((files (List Outlined))
       (waiting (List LibraryName))))

    (: loaded (impl (Fn (List Outlined) -> Loaded)))
    (define (loaded files)
      (Loaded files (concatenate (map generated-name files))))

    (: generated-name (impl (Fn Outlined -> (List LibraryName))))
    (define (generated-name outlined)
      (match (::outline outlined)
        ((Generated name _ _ _) (list name))
        (_ (Nil))))

    ;; ---- Walks ----

    ;; A file loading, and its imports not yet visited.
    (struct Frame
      ((outlined Outlined)
       (pending (List Imported))))

    ;; The files loading, innermost first and the program outermost; the
    ;; keys of the libraries a producer program says were loading as it
    ;; starts; and the files loaded, latest first.
    (struct Walk
      ((frames (List Frame))
       (keys (List String))
       (finished (List Outlined))))

    ;; What the loader does next: read a library, whose import is at `loc`,
    ;; and hand its outline to `entered` with `walk`; or nothing more.
    (enum Step
      (ReadLibrary
       ((library LibraryName)
        (loc Loc)
        (walk Walk)))
      (Done
       ((loaded Loaded)))
      (Stopped
       ((feedback (List Feedback)))))

    (: start-walk (impl (Fn Outlined -> Walk)))
    (define (start-walk program)
      (Walk (list (frame-of program)) (program-keys (::outline program)) (Nil)))

    (: program-keys (impl (Fn Outline -> (List String))))
    (define (program-keys outline)
      (match outline
        ((Written (Program loading _ _ _)) loading)
        (_ (Nil))))

    ;; The walk once the library it asked for is read: that library's
    ;; imports are visited next.
    (: entered (impl (Fn Walk Outlined -> Walk)))
    (define (entered walk library)
      (Walk-frames-set walk (Cons (frame-of library) (::frames walk))))

    (: frame-of (impl (Fn Outlined -> Frame)))
    (define (frame-of outlined)
      (Frame outlined (imported-libraries (::outline outlined))))

    ;; The next import that needs a library read, after loading every file
    ;; whose imports are all visited.
    (: next-step (impl (Fn Walk -> Step)))
    (define (next-step walk)
      (match (::frames walk)
        ((Nil) (Done (loaded (reverse (::finished walk)))))
        ((Cons frame outer)
         (match (::pending frame)
           ((Nil)
            (next-step (Walk outer (::keys walk) (Cons (::outlined frame) (::finished walk)))))
           ((Cons imported rest)
            (visit (Walk-frames-set walk (Cons (Frame-pending-set frame rest) outer)) imported))))))

    (: visit (impl (Fn Walk Imported -> Step)))
    (define (visit walk imported)
      (match (import-decision walk (::library imported))
        ((SkipImport) (next-step walk))
        ((ImportCycle) (Stopped (list (cycle-feedback imported))))
        ((LoadImport) (ReadLibrary (::library imported) (::loc imported) walk))))

    ;; ---- Imports ----

    ;; What an import needs, decided in the old expander's order: nothing
    ;; for (snail core forms), which the compiler provides; a cycle when
    ;; the library is still loading; nothing when it is loaded; and else
    ;; its library read.
    (enum Decision
      (SkipImport)
      (ImportCycle)
      (LoadImport))

    (: import-decision (impl (Fn Walk LibraryName -> Decision)))
    (define (import-decision walk name)
      (cond ((same-library? name (list "snail" "core" "forms")) (SkipImport))
            ((loading? walk name) (ImportCycle))
            ((any? (lambda (outlined) (names? outlined name)) (::finished walk)) (SkipImport))
            (else (LoadImport))))

    ;; A library is loading while a frame holds it, or when a producer
    ;; program names it as loading as it starts. The old driver prints a
    ;; producer's keys as dotted text, so (a.b) and (a b) are one key there,
    ;; as they are to the old compiler, until the integrator prints them.
    (: loading? (impl (Fn Walk LibraryName -> Bool)))
    (define (loading? walk name)
      (or (any? (lambda (frame) (names? (::outlined frame) name)) (::frames walk))
          (member? (library-key name) (::keys walk))))

    (: names? (impl (Fn Outlined LibraryName -> Bool)))
    (define (names? outlined name)
      (match (::outline outlined)
        ((Written (Defined declared _ _ _ _)) (same-library? declared name))
        ((Written (Program _ _ _ _)) #f)
        ((Generated declared _ _ _) (same-library? declared name))))

    (: cycle-feedback (impl (Fn Imported -> Feedback)))
    (define (cycle-feedback imported)
      (Feedback (::loc imported)
                (string-append "library import cycle through " (library-key (::library imported)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-walk)
    (import
     (only (snail compiler read language) Form)
     (snail stage0 testing))
    (begin
      (define (test-walk)
        (test-order)
        (test-decisions)
        (test-cycles)
        (test-generated)
        (test-requests))

      ;; ---- Helpers ----

      ;; The file of a library, where its imports are written.
      (define (file-of name)
        (string-append (string-join name "/") ".sld"))

      (define (at file)
        (Loc file 1 1))

      (define (defined name imports)
        (Outlined (file-of name)
                  (Written (Defined name
                             (map (lambda (imported) (Whole imported (at (file-of name)))) imports)
                             (list)
                             (list)
                             (at (file-of name))))))

      ;; A generated library, whose expression the walk never reads.
      (define (generated name)
        (Outlined (file-of name) (Generated name (list) (Form (list) (at "")) (at (file-of name)))))

      (define (program loading imports)
        (Outlined "main.sld"
                  (Written (Program loading
                                    (None)
                                    (map (lambda (imported) (Whole imported (at "main.sld")))
                                         imports)
                                    (list)))))

      ;; The walk from `main` run to its end, reading each library from
      ;; `files`. A library not there stops it, as a missing file would.
      (define (walked files main)
        (let loop ((walk (start-walk main)))
          (match (next-step walk)
            ((Done result) (Ok result))
            ((Stopped feedback) (Err feedback))
            ((ReadLibrary library loc next)
             (match (find (lambda (outlined) (names? outlined library)) files)
               ((Some outlined) (loop (entered next outlined)))
               ((None) (fail loc "not among the files")))))))

      (define (order files main)
        (match (walked files main)
          ((Ok result) (Ok (map ::file (::files result))))
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
                  (Ok
                   (Loaded (list (defined c (list)) (defined a (list c)) (program (list) (list a)))
                           (list))))))

      ;; Checked in the old expander's order: the builtin library, then a
      ;; library loading, then one loaded.
      (define (test-decisions)
        (let ((walk (Walk (list (Frame (defined a (list b)) (list))
                                (Frame (program (list "k.l") (list a)) (list)))
                          (list "k.l")
                          (list (defined c (list))))))
          (expect (import-decision walk forms) (SkipImport))
          (expect (import-decision walk a) (ImportCycle))
          (expect (import-decision walk (list "k" "l")) (ImportCycle))
          (expect (import-decision walk (list "k.l")) (ImportCycle))
          (expect (import-decision walk c) (SkipImport))
          (expect (import-decision walk b) (LoadImport))
          (expect (import-decision walk (list "main")) (LoadImport))
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
         (Ok (list "x/y.sld" "main.sld"))))

      ;; A generated library comes where it is reached, with nothing it
      ;; would import, and says the program waits on it.
      (define (test-generated)
        (let ((files (list (generated b) (defined a (list b c)) (defined c (list)))))
          (expect (walked files (program (list) (list b a)))
                  (Ok (Loaded (list (generated b)
                                    (defined c (list))
                                    (defined a (list b c))
                                    (program (list) (list b a)))
                              (list b))))))

      ;; A library is asked for where its name is written, and only when
      ;; it is needed.
      (define (test-requests)
        (match (next-step (start-walk (program (list) (list forms a))))
          ((ReadLibrary library loc _) (expect (Pair library loc) (Pair a (at "main.sld"))))
          (other (expect other "a request to read (a)")))
        (expect (walked (list) (program (list) (list a)))
                (fail (at "main.sld") "not among the files")))))
   (else)))
