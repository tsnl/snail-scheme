;; Loading: the outline of a program and of every library its imports
;; reach. The walk (snail compiler integrate walk) decides what to read
;; and in what order; this reads each file it asks for with `read`, then
;; `include`, with the bytes of the files `included-paths` names, then
;; `outline`, as the library it was found by. A library is found in the
;; first search directory that holds its file. Loading stops at the first
;; problem, whose feedback is the old expander's: what reading a file,
;; finding a library or following an import reports.
(define-library (snail compiler integrate load)
  (export
   load-program
   load-libraries)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler read pass)
   (snail compiler include paths)
   (snail compiler include pass)
   (snail compiler outline language)
   (snail compiler outline pass)
   (only (snail compiler outline names) written-name)
   (snail compiler integrate files)
   (snail compiler integrate walk))
  (begin

    ;; ---- Programs ----

    ;; The program at `path` and the libraries its imports reach, found in
    ;; `directories`.
    (: load-program (impl (Fn (List String) String -> (Result Loaded (List Feedback)) ! fs)))
    (define (load-program directories path)
      (result-let* ((program (outlined-file path (AsProgram))))
        (loaded-walk directories (start-walk program))))

    ;; The libraries `names` reach, each wanted at `loc`, loaded as a
    ;; program importing them would load them, without the program.
    (: load-libraries
       (impl (Fn (List String) (List LibraryName) Loc -> (Result Loaded (List Feedback)) ! fs)))
    (define (load-libraries directories names loc)
      (let ((wanting (Outlined ""
                               (Written (Program (Nil)
                                                 (None)
                                                 (map (lambda (name) (Whole name loc)) names)
                                                 (Nil))))))
        (result-let* ((loaded (loaded-walk directories (start-walk wanting))))
          (Ok (Loaded
               (filter (lambda (outlined) (not (string=? (::file outlined) ""))) (::files loaded))
               (::waiting loaded))))))

    (: loaded-walk (impl (Fn (List String) Walk -> (Result Loaded (List Feedback)) ! fs)))
    (define (loaded-walk directories walk)
      (match (next-step walk)
        ((Done loaded) (Ok loaded))
        ((Stopped feedback) (Err feedback))
        ((ReadLibrary library loc next)
         (result-let* ((outlined (library-outline directories library loc)))
           (loaded-walk directories (entered next outlined))))))

    ;; ---- Files ----

    ;; The library `name`, imported at `loc`.
    (: library-outline
       (impl (Fn (List String) LibraryName Loc -> (Result Outlined (List Feedback)) ! fs)))
    (define (library-outline directories name loc)
      (match (library-file directories name)
        ((Some path) (outlined-file path (AsLibrary name)))
        ((None) (fail loc (string-append "library not found: " (written-name name))))))

    ;; The file at `path`, read with its inclusions and outlined as
    ;; `reading` says.
    (: outlined-file (impl (Fn String Reading -> (Result Outlined (List Feedback)) ! fs)))
    (define (outlined-file path reading)
      (result-let* ((text (source-text path))
                    (forms (read path text))
                    (included (include forms (existing-files (included-paths forms))))
                    (file-outline (outline reading path included)))
        (Ok (Outlined path file-outline))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-load)
    (import
     (only (chibi filesystem) create-directory*)
     (snail compiler read language)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-load directory)
        (create-directory* (string-append directory "/sample"))
        (test-loaded directory)
        (test-problems directory))

      (define (write-files directory files)
        (for-each
         (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
         files))

      (define (files-of loaded)
        (match loaded
          ((Ok result) (Ok (Pair (map ::file (::files result)) (::waiting result))))
          ((Err feedback) (Err feedback))))

      ;; Libraries come after what they import, each once, with their
      ;; inclusions; a generated library is where it is reached.
      (define (test-loaded directory)
        (define (in file)
          (string-append directory "/" file))
        (write-files directory
                     (list (Pair "sample/a.sld"
                                 "(define-library (sample a) (import (sample c))\n  (begin (include-bytes \"a.bin\")))")
                           (Pair "sample/a.bin" "AB")
                           (Pair "sample/b.sld"
                                 "(define-library (sample b) (import (snail core forms) (only (sample c) x)))")
                           (Pair "sample/c.sld" "(define-library (sample c))")
                           (Pair "sample/made.sld"
                                 "(generate-library (sample made) (import (sample a)) (unit))")
                           (Pair "main.sld" "(import (sample a) (sample b) (sample a))\n(f)")
                           (Pair "producer.sld" "(import (sample made) (sample c))")))
        (expect (files-of (load-program (list directory) (in "main.sld")))
                (Ok (Pair (list (in "sample/c.sld")
                                (in "sample/a.sld")
                                (in "sample/b.sld")
                                (in "main.sld"))
                          (list))))
        (match (load-program (list directory) (in "main.sld"))
          ((Ok result)
           (match (::outline (list-ref (::files result) 1))
             ((Written (Defined _ _ _ (Cons (Atom (ByteVector bytes) _) (Nil)) _))
              (expect bytes (list->vector (list 65 66))))
             (other (expect other "sample a with its bytes"))))
          ((Err feedback) (expect feedback "a loaded program")))
        (expect (files-of (load-program (list directory) (in "producer.sld")))
                (Ok (Pair (list (in "sample/made.sld") (in "sample/c.sld") (in "producer.sld"))
                          (list (list "sample" "made"))))))

      ;; A missing program or library, a cycle, and a problem in a
      ;; library's header each stop loading where the old expander does.
      (define (test-problems directory)
        (define (in file)
          (string-append directory "/" file))
        (write-files directory
                     (list (Pair "missing.sld" "(import (sample c) (prefix (sample gone) p:))")
                           (Pair "sample/self.sld"
                                 "(define-library (sample self) (import (sample self)))")
                           (Pair "self.sld" "(import (sample self))")
                           (Pair "sample/wrong.sld" "(define-library (sample other))")
                           (Pair "wrong.sld" "(import (sample wrong))")
                           (Pair "keyed.sld" "(generating \"sample.c\")\n(import (sample c))")))
        (expect (load-program (list directory) (in "absent.sld"))
                (fail (Loc (in "absent.sld") 0 0) "no such file or directory"))
        (expect (load-program (list directory) (in "missing.sld"))
                (fail (Loc (in "missing.sld") 1 28) "library not found: (sample gone)"))
        (expect (load-program (list) (in "missing.sld"))
                (fail (Loc (in "missing.sld") 1 9) "library not found: (sample c)"))
        (expect (load-program (list directory) (in "self.sld"))
                (fail (Loc (in "sample/self.sld") 1 39) "library import cycle through sample.self"))
        (expect (load-program (list directory) (in "wrong.sld"))
                (fail (Loc (in "sample/wrong.sld") 1 1) "library name does not match its path"))
        (expect (load-program (list directory) (in "keyed.sld"))
                (fail (Loc (in "keyed.sld") 2 9) "library import cycle through sample.c")))))
   (else)))
