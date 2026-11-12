;; Binding an expanded library: the files its links name, as (snail
;; compiler bind linked) answers them, are read, those that are there are
;; digested, and the pass `bind` is handed the digests by file and every
;; target's files the caller supplied. The integrator decides nothing
;; about the library: `bind` decides what a missing file or target means,
;; and its answer is relayed.
(define-library (snail compiler integrate bind)
  (export
   bind-expanded)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (only (snail compiler outline language) Program)
   (only (snail compiler expand language) Expanded)
   (snail compiler bind supply)
   (snail compiler bind linked)
   (snail compiler bind pass)
   (snail compiler integrate files)
   (snail compiler integrate sha256)
   (snail compiler integrate walk))
  (begin

    ;; `expanded`, the library `loaded` holds, bound with the files of the
    ;; targets `targets` holds, by target.
    (: bind-expanded
       (impl (Fn LoadedFile Expanded (Table (List TargetFile))
                 -> (Result BindOutcome (List Feedback))
                 !
                 fs)))
    (define (bind-expanded loaded expanded targets)
      (let* ((printed (printed-copy loaded))
             (files (named-files printed expanded)))
        (bind expanded (Supply printed (digests files (existing-files files)) targets))))

    ;; A producer program's printed copy, and the recipe it was printed
    ;; from, as its outline records them.
    (: printed-copy (impl (Fn LoadedFile -> (Option PrintedCopy))))
    (define (printed-copy loaded)
      (match (::library loaded)
        ((Program _ (Some recipe) _ _) (Some (PrintedCopy (::file loaded) recipe)))
        (_ (None))))

    ;; The digest of each of `files` that `contents` holds, by file.
    (: digests (impl (Fn (List String) (Table Bytes) -> (Table String))))
    (define (digests files contents)
      (fold-left (lambda (found file)
                   (match (table-ref contents file)
                     ((Some bytes) (table-set found file (bytes->hex (sha256 bytes))))
                     ((None) found)))
                 empty-table
                 files))

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
     (only (snail compiler expand targets) TargetRequest)
     (snail stage0 testing))
    (begin
      ;; A library is bound with the files it links, read from the
      ;; directory, a printed copy's beside its recipe; a file that is not
      ;; there is a problem, and a target not supplied is waited for.
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-bind-expanded directory)
        (create-directory* (string-append directory "/data"))
        (create-directory* (string-append directory "/recipe/data"))
        (write-file (string-append directory "/data/x.txt") "abc")
        (write-file (string-append directory "/recipe/data/x.txt") "")
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
               (printed (LoadedFile main
                                    (Program (list "k")
                                             (Some (string-append directory "/recipe/r.sld"))
                                             (list)
                                             (list)))))
          (expect (bind-expanded (program-file main) linking empty-table)
                  (Ok (BoundLibrary (bound-program linking-digest
                                                   (string-append directory "/data/x.txt")
                                                   main))))
          (expect (bind-expanded printed linking empty-table)
                  (Ok (BoundLibrary (bound-program empty-digest
                                                   (string-append directory "/recipe/data/x.txt")
                                                   main))))
          (expect (bind-expanded (program-file main) missing empty-table)
                  (fail link-loc
                        (string-append "the library main links absent.bin, but there is no file at "
                                       directory
                                       "/absent.bin")))
          (expect (bind-expanded (program-file main) requesting empty-table)
                  (Ok (WantsTargets (list (TargetRequest "site" (at main 29))))))))

      (define linking-digest "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

      (define empty-digest "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

      (define (at file column)
        (Loc file 1 column))

      (define (program-file name)
        (LoadedFile name (Program (list) (None) (list) (list))))

      ;; The program `linking` bound, its file found at `file`.
      (define (bound-program digest file main)
        (let ((handle (expanded-Global (list "main") "link-handle" 3)))
          (bound-Program
           (list (bound-LinkImport handle (list "data" "x.txt") digest file (at main 20))
                 (bound-Define (expanded-Global (list "main") "x" 0)
                               (bound-Call (bound-TopRef (expanded-TopGlobal handle) (at main 10))
                                           (list)
                                           (at main 10))
                               (at main 1)))
           (None)
           4)))))
   (else)))
