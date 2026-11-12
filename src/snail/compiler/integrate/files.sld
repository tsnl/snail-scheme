;; The integrator's reads of the file system: a source's text, where a
;; library's file is, the bytes of the files a source includes or a
;; library links, and the output a producer wrote. These are the
;; compiler's only functions that perform `fs`, and each answers what it
;; found as data, so the decisions about it are made elsewhere.
(define-library (snail compiler integrate files)
  (export
   source-text
   library-file
   existing-files
   produced-output)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler names libraries))
  (begin

    ;; ---- Sources ----

    ;; The text of the file at `path`. A file that is not there, as an
    ;; entry an editor has just deleted, is feedback about the file as a
    ;; whole.
    (: source-text (impl (Fn String -> (Result String (List Feedback)) ! fs)))
    (define (source-text path)
      (if (file-exists? path)
          (Ok (read-file path))
          (fail (Loc path 0 0) "no such file or directory")))

    ;; ---- Libraries ----

    ;; The file of the library `name` in the first of `directories` that
    ;; holds one: (snail core base) is `snail/core/base.sld` there.
    (: library-file (impl (Fn (List String) LibraryName -> (Option String) ! fs)))
    (define (library-file directories name)
      (find file-exists? (map (lambda (directory) (library-path directory name)) directories)))

    (: library-path (impl (Fn String LibraryName -> String)))
    (define (library-path directory name)
      (string-append directory "/" (string-join name "/") ".sld"))

    ;; ---- Included and linked files ----

    ;; The bytes of each file of `paths` that exists, by path. One that is
    ;; not there is left out, and what named it reports it where it is
    ;; named: `include` an included file, the integrator a linked one.
    (: existing-files (impl (Fn (List String) -> (Table Bytes) ! fs)))
    (define (existing-files paths)
      (fold-left (lambda (files path)
                   (if (file-exists? path) (table-set files path (read-bytes path)) files))
                 empty-table
                 paths))

    ;; ---- Producers' outputs ----

    ;; The bytes the producer with `key` wrote, GENERATED/KEY.syntax in the
    ;; directory `generated` that the caller names, if they are there.
    (: produced-output (impl (Fn String String -> (Option Bytes) ! fs)))
    (define (produced-output generated key)
      (let ((path (string-append generated "/" key ".syntax")))
        (if (file-exists? path) (Some (read-bytes path)) (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-files)
    (import
     (only (chibi filesystem) create-directory*)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-files directory)
        (let ((first (string-append directory "/first"))
              (second (string-append directory "/second")))
          (create-directory* (string-append first "/sample"))
          (create-directory* (string-append second "/sample"))
          (write-file (string-append first "/sample/a.sld") "first a")
          (write-file (string-append second "/sample/a.sld") "second a")
          (write-file (string-append second "/sample/b.sld") "second b")
          (write-file (string-append first "/blob.bin") "AB")
          (write-file (string-append first "/12.syntax") "AB")
          (expect (library-path "dir" (list "snail" "core" "base")) "dir/snail/core/base.sld")
          (expect (library-file (list first second) (list "sample" "a"))
                  (Some (string-append first "/sample/a.sld")))
          (expect (library-file (list first second) (list "sample" "b"))
                  (Some (string-append second "/sample/b.sld")))
          (expect (library-file (list first second) (list "sample" "c")) (None))
          (expect (library-file (list) (list "sample" "a")) (None))
          (expect (source-text (string-append second "/sample/b.sld")) (Ok "second b"))
          (expect (source-text (string-append first "/missing.sld"))
                  (fail (Loc (string-append first "/missing.sld") 0 0) "no such file or directory"))
          (expect (existing-files (list (string-append first "/blob.bin")
                                        (string-append first "/missing.bin")))
                  (table-set empty-table
                             (string-append first "/blob.bin")
                             (list->vector (list 65 66))))
          (expect (produced-output first "12") (Some (list->vector (list 65 66))))
          (expect (produced-output first "13") (None))
          (expect (produced-output (string-append first "/absent") "12") (None))))))
   (else)))
