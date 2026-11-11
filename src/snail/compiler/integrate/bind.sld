;; Binding an expanded library: the files of the targets it asks for are
;; found among those the caller supplied, the files it links are found
;; beside the files that name them, read and digested, and then the pass
;; `bind` runs. A target the caller did not supply is no failure of the
;; program: the library waits for it, as the old compiler asks its caller
;; for an input. Two problems are the old expander's, with its messages
;; and places: two links that write one path but find different files,
;; and a linked file that is not there. They come in the old expander's
;; order, which asks for a target and finds two links clashing while it
;; expands the body, and reads the linked files once the body is done.
;; What to read and what it means is decided without the file system.
(define-library (snail compiler integrate bind)
  (export
   BindOutcome
   BoundLibrary
   WantsTargets
   bind-expanded)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName Written Program)
   (only (snail compiler outline names) library-key)
   (only (snail compiler expand language) Expanded)
   (snail compiler expand links)
   (snail compiler expand targets)
   (only (snail compiler bind language) Bound)
   (snail compiler bind supply)
   (snail compiler bind pass)
   (snail compiler integrate files)
   (snail compiler integrate sha256)
   (snail compiler integrate walk))
  (begin

    ;; ---- Binding ----

    ;; A library bound, or the targets it waits for: each it asks for that
    ;; the caller did not supply, in the order it first asks.
    (enum BindOutcome
      (BoundLibrary
       ((bound Bound)))
      (WantsTargets
       ((requests (List TargetRequest)))))

    ;; `expanded`, the library `name` read from `outlined`, bound with the
    ;; files of the targets `supplied` holds, by target.
    (: bind-expanded
       (impl (Fn Outlined LibraryName Expanded (Table (List TargetFile))
                 -> (Result BindOutcome (List Feedback))
                 !
                 fs)))
    (define (bind-expanded outlined name expanded supplied)
      (match (targets-supplied (requested-targets expanded) supplied)
        ((Unsupplied requests) (Ok (WantsTargets requests)))
        ((Supplied targets)
         (result-let* ((requests (link-requests outlined (linked-files expanded)))
                       (links (found-links name requests (existing-files (map ::file requests)))))
           (Ok (BoundLibrary (bind expanded (Supply links targets))))))))

    ;; ---- Targets ----

    (enum TargetsFound
      (Supplied
       ((targets (List TargetFiles))))
      (Unsupplied
       ((requests (List TargetRequest)))))

    ;; The files of each target `requests` names, when the caller supplied
    ;; every one; else each request it did not supply, in order.
    (: targets-supplied (impl (Fn (List TargetRequest) (Table (List TargetFile)) -> TargetsFound)))
    (define (targets-supplied requests supplied)
      (let loop ((requests requests)
                 (found (Nil))
                 (missing (Nil)))
        (match requests
          ((Nil) (if (null? missing) (Supplied (reverse found)) (Unsupplied (reverse missing))))
          ((Cons request rest)
           (match (table-ref supplied (::target request))
             ((Some files) (loop rest (Cons (TargetFiles (::target request) files) found) missing))
             ((None) (loop rest found (Cons request missing))))))))

    ;; ---- Linked files ----

    ;; A path a library links: the file it names, and where the library
    ;; first writes it.
    (struct LinkRequest
      ((path (List String))
       (file String)
       (loc Loc)))

    ;; Each path the links write, once, in the order first written, with
    ;; the file it names beside the file that writes it. Two links of one
    ;; path that name different files, as a macro's template beside
    ;; another library and a use beside this one may, are a problem at the
    ;; second.
    (: link-requests
       (impl (Fn Outlined (List Link) -> (Result (List LinkRequest) (List Feedback)))))
    (define (link-requests outlined links)
      (let loop ((links links)
                 (requests (Nil)))
        (match links
          ((Nil) (Ok (reverse requests)))
          ((Cons link rest)
           (result-let* ((more (with-request requests (link-request outlined link))))
             (loop rest more))))))

    (: link-request (impl (Fn Outlined Link -> LinkRequest)))
    (define (link-request outlined link)
      (LinkRequest (::path link)
                   (beside (written-in outlined (::written link)) (path-text (::path link)))
                   (::written link)))

    ;; `requests`, latest first, with `request` among them once.
    (: with-request
       (impl (Fn (List LinkRequest) LinkRequest -> (Result (List LinkRequest) (List Feedback)))))
    (define (with-request requests request)
      (match (find (lambda (other) (same-link-path? (::path other) (::path request))) requests)
        ((None) (Ok (Cons request requests)))
        ((Some other)
         (if (string=? (::file other) (::file request))
             (Ok requests)
             (fail (::loc request)
                   (string-append "two files link as "
                                  (path-text (::path request))
                                  ": "
                                  (::file other)
                                  " and "
                                  (::file request)))))))

    ;; The file a path written at `loc` is beside: the file it is written
    ;; in, but that a producer program's printed copy stands for its
    ;; recipe, so a recipe names files beside itself wherever its producer
    ;; is printed.
    (: written-in (impl (Fn Outlined Loc -> String)))
    (define (written-in outlined loc)
      (match (::outline outlined)
        ((Written (Program _ (Some recipe) _ _))
         (if (string=? (::file loc) (::file outlined)) recipe (::file loc)))
        (_ (::file loc))))

    ;; A linked path as the old expander's messages write it.
    (: path-text (impl (Fn (List String) -> String)))
    (define (path-text path)
      (string-join path "/"))

    ;; Each requested file with the digest of its bytes, which `contents`
    ;; holds for each file that is there. The first file that is not there
    ;; fails the library, where it is first named.
    (: found-links
       (impl (Fn LibraryName (List LinkRequest) (Table Bytes)
                 -> (Result (List FoundLink) (List Feedback)))))
    (define (found-links name requests contents)
      (map-results (lambda (request) (found-link name request contents)) requests))

    (: found-link
       (impl (Fn LibraryName LinkRequest (Table Bytes) -> (Result FoundLink (List Feedback)))))
    (define (found-link name request contents)
      (match (table-ref contents (::file request))
        ((Some bytes)
         (Ok (FoundLink (::path request)
                        (bytes->hex (sha256 bytes))
                        (::file request)
                        (::loc request))))
        ((None)
         (fail (::loc request)
               (string-append "the library "
                              (library-key name)
                              " links "
                              (path-text (::path request))
                              ", but there is no file at "
                              (::file request))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-bind-expanded)
    (import
     (only (chibi filesystem) create-directory*)
     (prefix (snail compiler expand language) expanded-)
     (prefix (only (snail compiler bind language) Program LinkImport Define Call TopRef) bound-)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-bind-expanded directory)
        (test-targets)
        (test-requests)
        (test-found)
        (test-bound directory))

      (define (at file column)
        (Loc file 1 column))

      (define (bytes text)
        (list->vector (map (lambda (char) (i32->u8 (i64->i32 (char->integer char))))
                           (string->list text))))

      (define (program-file name)
        (Outlined name (Written (Program (list) (None) (list) (list)))))

      ;; A target the caller supplied is found, by name; any it did not is
      ;; asked for, in the order requested, and nothing is found.
      (define (test-targets)
        (let ((supplied (table-set empty-table "site" (list (TargetFile "a" (bytes "A")))))
              (site (TargetRequest "site" (at "a.sld" 1)))
              (docs (TargetRequest "docs" (at "a.sld" 2)))
              (api (TargetRequest "api" (at "a.sld" 3))))
          (expect (targets-supplied (list) supplied) (Supplied (list)))
          (expect (targets-supplied (list site) supplied)
                  (Supplied (list (TargetFiles "site" (list (TargetFile "a" (bytes "A")))))))
          (expect (targets-supplied (list docs site api) supplied) (Unsupplied (list docs api)))))

      ;; A path is found beside the file that writes it, once however many
      ;; links write it; a producer's printed copy stands for its recipe.
      ;; Two links of one path that find different files are a problem.
      (define (test-requests)
        (let ((main (program-file "lib/main.sld"))
              (copy (Outlined "build/p.sld"
                              (Written (Program (list "k") (Some "lib/r.sld") (list) (list)))))
              (link (lambda (path file column) (Link path (at file column)))))
          (expect (link-requests main
                                 (list (link (list "x.bin") "lib/main.sld" 1)
                                       (link (list "d" "y.bin") "lib/main.sld" 2)
                                       (link (list "x.bin") "lib/main.sld" 3)))
                  (Ok (list (LinkRequest (list "x.bin") "lib/x.bin" (at "lib/main.sld" 1))
                            (LinkRequest (list "d" "y.bin") "lib/d/y.bin" (at "lib/main.sld" 2)))))
          (expect (link-requests copy
                                 (list (link (list "x.bin") "build/p.sld" 1)
                                       (link (list "y.bin") "other/m.sld" 2)))
                  (Ok (list (LinkRequest (list "x.bin") "lib/x.bin" (at "build/p.sld" 1))
                            (LinkRequest (list "y.bin") "other/y.bin" (at "other/m.sld" 2)))))
          (expect (link-requests main
                                 (list (link (list "x.bin") "other/m.sld" 1)
                                       (link (list "x.bin") "lib/main.sld" 2)))
                  (fail (at "lib/main.sld" 2)
                        "two files link as x.bin: other/x.bin and lib/x.bin"))))

      ;; A file read is named by its digest; the first that is not there
      ;; fails the library, naming it and the path.
      (define (test-found)
        (let ((requests (list (LinkRequest (list "a.txt") "lib/a.txt" (at "lib/m.sld" 1))
                              (LinkRequest (list "d" "b.txt") "lib/d/b.txt" (at "lib/m.sld" 2)))))
          (expect (found-links (list "sample" "m")
                               requests
                               (table-set (table-set empty-table "lib/a.txt" (bytes "abc"))
                                          "lib/d/b.txt"
                                          (bytes "")))
                  (Ok (list (FoundLink (list "a.txt")
                                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                       "lib/a.txt"
                                       (at "lib/m.sld" 1))
                            (FoundLink (list "d" "b.txt")
                                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                                       "lib/d/b.txt"
                                       (at "lib/m.sld" 2)))))
          (expect
           (found-links (list "sample" "m") requests (table-set empty-table "lib/a.txt" (bytes "")))
           (fail (at "lib/m.sld" 2)
                 "the library sample.m links d/b.txt, but there is no file at lib/d/b.txt"))))

      ;; A library is bound with the files it links, read from the
      ;; directory, or waits for the targets it was not supplied.
      (define (test-bound directory)
        (create-directory* (string-append directory "/data"))
        (write-file (string-append directory "/data/x.txt") "abc")
        (let* ((main (string-append directory "/main.sld"))
               (link-loc (at main 20))
               (global (expanded-Global (list "main") "x" 0))
               (program (lambda (value)
                          (expanded-Program (list (expanded-Define global value (at main 1)))
                                            (None)
                                            3)))
               (linking (program (expanded-LinkedFile (list "data" "x.txt") link-loc (at main 10))))
               (missing (program (expanded-LinkedFile (list "absent.bin") link-loc (at main 10))))
               (requesting (program (expanded-ArtifactFiles "site"
                                                            (expanded-Literal (expanded-UnitValue)
                                                                              (at main 30))
                                                            (expanded-Literal (expanded-UnitValue)
                                                                              (at main 31))
                                                            (expanded-Literal (expanded-UnitValue)
                                                                              (at main 32))
                                                            (at main 29))))
               (handle (expanded-Global (list "main") "link-handle" 3)))
          (expect (bind-expanded (program-file main) (list "main") linking empty-table)
                  (Ok (BoundLibrary
                       (bound-Program
                        (list (bound-LinkImport
                               handle
                               (list "data" "x.txt")
                               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                               (string-append directory "/data/x.txt")
                               link-loc)
                              (bound-Define global
                                            (bound-Call
                                             (bound-TopRef (expanded-TopGlobal handle) (at main 10))
                                             (list)
                                             (at main 10))
                                            (at main 1)))
                        (None)
                        4))))
          (expect (bind-expanded (program-file main) (list "main") missing empty-table)
                  (fail link-loc
                        (string-append "the library main links absent.bin, but there is no file at "
                                       directory
                                       "/absent.bin")))
          (expect (bind-expanded (program-file main) (list "main") requesting empty-table)
                  (Ok (WantsTargets (list (TargetRequest "site" (at main 29))))))))))
   (else)))
