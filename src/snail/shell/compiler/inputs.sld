;; What a build supplies to its compiles, and the requests a compile makes
;; for what it was not supplied. A request is the `compile` effect's `need`
;; (snail shell compiler read): a resident caller is sent its record, and a
;; process caller finds its datum, which this library prints and parses.
(define-library (snail shell compiler inputs)
  (export
   ArtifactFiles
   Generated
   Inputs
   Inputs-artifacts
   no-inputs
   supply-artifact
   supply-generated
   producer-text
   producer-key
   generated-output
   request->string
   parse-request
   request-input
   publish-request
   unsupplied
   generated-syntax
   print-producer
   printed-producer-text
   generating-stack
   read-source-file)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler core) fnv-1a))
  (begin

    ;; ---- Build inputs ----

    ;; An immutable snapshot of a completed target's files: relative paths
    ;; with their bytes, in path order. The host loads the files before
    ;; expansion starts, and uses retain these same vectors as exact cache
    ;; evidence, without copying.
    (type ArtifactFiles (List (Pair String Bytes)))

    ;; What a producer wrote, beside the text its key hashes. A lookup
    ;; compares that text, so producers whose keys collide are never
    ;; confused.
    (struct Generated
      ((text String)
       (bytes Bytes)))

    ;; Everything one build supplies to the compiles it runs: each completed
    ;; target's files by target name, and each producer's output by its key.
    (struct Inputs
      ((artifacts (Table ArtifactFiles))
       (generated (Table Generated))))

    (: no-inputs Inputs)
    (define no-inputs (Inputs empty-table empty-table))

    (: supply-artifact (-> Inputs String ArtifactFiles Inputs))
    (define (supply-artifact inputs name files)
      (Inputs-artifacts-set inputs (table-set (Inputs-artifacts inputs) name files)))

    (: supply-generated (-> Inputs String Bytes Inputs))
    (define (supply-generated inputs text bytes)
      (Inputs-generated-set inputs
                            (table-set (Inputs-generated inputs)
                                       (producer-key text)
                                       (Generated text bytes))))

    ;; A producer as a build tells it apart: the library directories its
    ;; imports resolve in, then its program. One table serves every target
    ;; of a build, and two targets with different directories may resolve
    ;; the same recipe's imports to different libraries.
    (: producer-text (-> (List String) (List Syntax) String))
    (define (producer-text directories forms)
      (string-append (string-join (map quoted directories) " ") "\n" (program-text forms)))

    (: producer-key (-> String String))
    (define (producer-key text)
      (i64->string (fnv-1a text)))

    (: program-text (-> (List Syntax) String))
    (define (program-text forms)
      (string-join (map syntax->string forms) "\n"))

    ;; The output supplied for the producer with this text, if any.
    (: generated-output (-> Inputs String (Option Bytes)))
    (define (generated-output inputs text)
      (match (table-ref (Inputs-generated inputs) (producer-key text))
        ((Some generated)
         (if (string=? (Generated-text generated) text) (Some (Generated-bytes generated)) (None)))
        ((None) (None))))

    ;; ---- Requests ----

    ;; A pass that needs an input it was not supplied, such as the expander
    ;; at an `artifact-files` use, asks for it by performing `need`. Nothing
    ;; after the call runs: the entry point's handler takes the request and
    ;; hands it to its caller.
    (: request-input (All (A) (-> CompilerRequest A ! compile)))
    (define (request-input request)
      (absurd (need request)))

    ;; A process caller finds a request as a datum in the compile's
    ;; generated directory once the compiler has exited with status 1.
    (: publish-request (-> String CompilerRequest Unit ! fs))
    (define (publish-request directory request)
      (write-file (string-append directory "/request.datum") (request->string request)))

    ;; A compile whose caller can supply nothing, as a discovery expansion
    ;; or the development loop's: its plan has run every producer it reaches,
    ;; so asking for one's output is an internal error, and only a project
    ;; build has targets whose files a program could embed, so asking for
    ;; them is the program's error, at its use. A source error goes on as it
    ;; came, to the caller's handler.
    (: unsupplied (All (T e) (-> (-> T ! compile e) T ! compile e)))
    (define (unsupplied work)
      (match (compiling work)
        ((Ok value) value)
        ((Err (Requested (GenerateInput key)))
         (panic (string-append "internal error: the plan did not run the producer " key)))
        ((Err (Requested (ArtifactInput name loc)))
         (compile-error loc
                        (string-append "artifact-bundle requires a project build resolver: " name)))
        ((Err (Failed diagnostic)) (absurd (fail diagnostic)))))

    (: request->string (-> CompilerRequest String))
    (define (request->string request)
      (match request
        ((GenerateInput key) (string-append "(generate " (quoted key) ")\n"))
        ((ArtifactInput name source)
         (string-append "(artifact " (quoted name) " " (quoted (Loc-file source)) " "
                        (i64->string (Loc-line source))
                        " "
                        (i64->string (Loc-column source))
                        ")\n"))))

    (: parse-request (-> String String CompilerRequest ! compile))
    (define (parse-request text filename)
      (match (read-text text filename)
        ((Cons (Form (Cons (Ident "generate" _ _) (Cons (Atom (DString key) _) (Nil))) loc) (Nil))
         (unless (generated-key? key)
           (compile-error loc "expected a nonempty decimal generator key"))
         (GenerateInput key))
        ((Cons (Form (Cons (Ident "artifact" _ _)
                           (Cons (Atom (DString name) _)
                                 (Cons (Atom (DString file) _)
                                       (Cons (Atom (DInt line) _)
                                             (Cons (Atom (DInt column) _) (Nil))))))
                     loc)
               (Nil))
         (unless (and (> line 0) (> column 0))
           (compile-error loc "artifact source positions start at one"))
         (ArtifactInput name (Loc file line column)))
        (_ (compile-error (Loc filename 1 1)
                          "expected exactly one generate or artifact compiler request"))))

    (: generated-key? (-> String Bool))
    (define (generated-key? key)
      (and (> (string-length key) 0)
           (every? (lambda (c) (let ((value (char->integer c))) (and (>= value 48) (<= value 57))))
                   (string->list key))))

    (: quoted (-> String String))
    (define (quoted text)
      (datum->string (DString text)))

    ;; ---- Producer programs ----

    ;; A producer the build did not supply, printed into the compile's
    ;; scratch `directory` and requested, or its output once the host has
    ;; written it there. The producer is compiled as a program of its own
    ;; while the library it generates is loading, so its printed source
    ;; begins with the libraries loading then, innermost first:
    ;; `(generating "sample.knot" ...)`. Its expansion starts with them
    ;; loading, which makes a producer that imports, along any chain, the
    ;; library it generates an import cycle. The key is the one the build's
    ;; inputs use, which leaves that line out, since what the producer writes
    ;; does not depend on the chain that reached it.
    (: generated-syntax (-> String (List String) (List String) (List Syntax) Bytes ! fs compile))
    (define (generated-syntax directory directories loading forms)
      (let* ((key (producer-key (producer-text directories forms)))
             (output (string-append directory "/" key ".syntax")))
        (if (file-exists? output)
            (read-bytes output)
            (begin (print-producer (string-append directory "/" key ".sld") loading forms)
                   (request-input (GenerateInput key))))))

    ;; Prints the producer `forms` as the program at `path`, beginning with
    ;; the libraries `loading` when it was reached.
    (: print-producer (-> String (List String) (List Syntax) Unit ! fs))
    (define (print-producer path loading forms)
      (write-file path (string-append (generating-line loading) "\n" (program-text forms))))

    ;; The text of the producer printed at `path`, as `producer-text` gave
    ;; it for the forms it was printed from.
    (: printed-producer-text (-> (List String) String String ! fs compile))
    (define (printed-producer-text directories path)
      (producer-text directories (Pair-second (generating-stack (read-source-file path)))))

    (: generating-line (-> (List String) String))
    (define (generating-line loading)
      (string-append "(generating"
                     (string-concatenate
                      (map (lambda (key) (string-append " " (quoted key))) loading))
                     ")"))

    ;; ---- Source files ----

    ;; The forms of the source file at `path`. One that is not there, as a
    ;; build's entry an editor has just deleted, fails the compile with a
    ;; diagnostic about the file as a whole, so a resident caller reports
    ;; it and builds again once the file is back.
    (: read-source-file (-> String (List Syntax) ! fs compile))
    (define (read-source-file path)
      (if (file-exists? path)
          (read-text (read-file path) path)
          (compile-error (Loc path 0 0) "no such file or directory")))

    ;; The libraries a program's first form says were loading when it was
    ;; printed, and the forms after it. A program that does not begin with
    ;; `generating` starts with nothing loading.
    (: generating-stack (-> (List Syntax) (Pair (List String) (List Syntax)) ! compile))
    (define (generating-stack forms)
      (match forms
        ((Cons (Form (Cons (Ident "generating" _ _) keys) _) rest)
         (Pair (map loading-key keys) rest))
        (_ (Pair (Nil) forms))))

    (: loading-key (-> Syntax String ! compile))
    (define (loading-key key)
      (match key
        ((Atom (DString text) _) text)
        (_ (compile-error (syntax-loc key) "expected a library key string"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-inputs)
    (import
     (only (scheme base) list)
     (only (chibi string) string-contains)
     (snail stage0 testing))
    (begin
      (define (input-error text)
        (or (compile-failure (lambda () (parse-request text "input.datum"))) "accepted"))

      (define (test-inputs)
        (let ((request (ArtifactInput "client\"\n" (Loc "source\\name.sld" 12 7))))
          (expect (parse-request (request->string request) "request.datum") request)
          (expect (parse-request "(generate \"123456\")" "request.datum") (GenerateInput "123456")))
        (for-each (lambda (text)
                    (expect
                     (if (string-contains (input-error text) "input.datum:") "rejected" "accepted")
                     "rejected"))
                  '("" "(generate \"\")" "(generate \"../x\")" "(generate \"-1\")" "(generate 123)"
                    "(generate \"123\") ()" "(generate \"123\" extra)" "(artifact \"x\")"
                    "(artifact \"x\" \"file\" 0 1)" "(artifact \"x\" \"file\" 1 -1)"))
        (test-generating-stack)
        (test-generated-inputs)
        (test-missing-source))

      ;; The printed stack reads back as the same keys, ahead of the
      ;; producer's own forms; a program without one has nothing loading.
      (define (test-generating-stack)
        (let ((printed (generating-stack
                        (read-text (string-append (generating-line (list "sample.knot" "odd\"key"))
                                                  "\n(unit)")
                                   "producer.sld")))
              (plain (generating-stack (read-text "(unit)" "program.sld"))))
          (expect (Pair-first printed) (list "sample.knot" "odd\"key"))
          (expect (length (Pair-second printed)) 1)
          (expect (Pair-first plain) (list))
          (expect (length (Pair-second plain)) 1)))

      ;; A source that is not there is a diagnostic naming the file.
      (define (test-missing-source)
        (expect (compile-failure (lambda () (read-source-file "build/tests/missing/main.sld")))
                "build/tests/missing/main.sld: no such file or directory"))

      ;; A supplied output is found by its producer's text, which reads back
      ;; from the printed producer unchanged. The same program under other
      ;; directories is another producer, and an entry whose text differs
      ;; is never taken for it, even under its key.
      (define (test-generated-inputs)
        (let* ((forms
                (read-text
                 "(import (snail core base) (srfi 1)) (write \"a\\\"b\\nc\" #u8(1 2) 1.50 #\\x)"
                 "producer.sld"))
               (printed
                (string-append (generating-line (list "sample.knot")) "\n" (program-text forms)))
               (text (producer-text (list "/project/src" "/root/src") forms))
               (output (list->vector (list (i32->u8 1) (i32->u8 2))))
               (inputs (supply-generated no-inputs text output)))
          (expect (producer-text (list "/project/src" "/root/src")
                                 (Pair-second (generating-stack (read-text printed "printed.sld"))))
                  text)
          (expect (generated-output inputs text) (Some output))
          (expect (generated-output inputs (producer-text (list "/root/src") forms)) (None))
          (expect (generated-output (Inputs empty-table
                                            (table-set empty-table
                                                       (producer-key text)
                                                       (Generated "other" output)))
                                    text)
                  (None))))))
   (else)))
