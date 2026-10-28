;; What a build supplies to its compiles, and the requests a compile makes
;; for what it was not supplied. A resident caller consumes a request's typed
;; value; a process caller publishes and parses its datum after compilation
;; unwinds.
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
   CompilerRequest
   GenerateInput
   ArtifactInput
   request->string
   parse-request
   request-input!
   take-input-request!
   publish-input-request!
   generated-syntax
   print-producer
   printed-producer-text
   generating-stack)
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

    (enum CompilerRequest
      (GenerateInput ((key String)))
      (ArtifactInput
       ((name String)
        (source Loc))))

    ;; Private control state for one compiler invocation. A request exits
    ;; immediately; its host consumes it only after the stack has unwound.
    (: pending-request (Ref (Option CompilerRequest)))
    (define pending-request (ref (None)))

    ;; A request is a non-returning exit, as `compile-error` is, and records
    ;; its value through the same unsafe bridge, so a pass that may need an
    ;; input, such as the expander at an `artifact-files` use, keeps a pure
    ;; signature. The cell is observable only at the trusted terminal exit
    ;; that takes it, after the invocation is abandoned; it is not pure.
    (: request-input! (All (A) (-> CompilerRequest A)))
    (define (request-input! request)
      (unsafe-total
       (lambda ()
         (ref-set! pending-request (Some request))
         (panic "compiler requires an input"))))

    (: take-input-request! (-> (Option CompilerRequest) ! mut))
    (define (take-input-request!)
      (let ((request (ref-get pending-request)))
        (ref-set! pending-request (None))
        request))

    (: publish-input-request! (-> String Unit ! mut fs))
    (define (publish-input-request! directory)
      (match (take-input-request!)
        ((Some request)
         (write-file (string-append directory "/request.datum") (request->string request)))
        ((None) (unit))))

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

    (: parse-request (-> String String CompilerRequest))
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
    (: generated-syntax (-> String (List String) (List String) (List Syntax) Bytes ! fs))
    (define (generated-syntax directory directories loading forms)
      (let* ((key (producer-key (producer-text directories forms)))
             (output (string-append directory "/" key ".syntax")))
        (if (file-exists? output)
            (read-bytes output)
            (begin (print-producer (string-append directory "/" key ".sld") loading forms)
                   (request-input! (GenerateInput key))))))

    ;; Prints the producer `forms` as the program at `path`, beginning with
    ;; the libraries `loading` when it was reached.
    (: print-producer (-> String (List String) (List Syntax) Unit ! fs))
    (define (print-producer path loading forms)
      (write-file path (string-append (generating-line loading) "\n" (program-text forms))))

    ;; The text of the producer printed at `path`, as `producer-text` gave
    ;; it for the forms it was printed from.
    (: printed-producer-text (-> (List String) String String ! fs))
    (define (printed-producer-text directories path)
      (producer-text directories
                     (Pair-second (generating-stack (read-text (read-file path) path)))))

    (: generating-line (-> (List String) String))
    (define (generating-line loading)
      (string-append "(generating"
                     (string-concatenate
                      (map (lambda (key) (string-append " " (quoted key))) loading))
                     ")"))

    ;; The libraries a program's first form says were loading when it was
    ;; printed, and the forms after it. A program that does not begin with
    ;; `generating` starts with nothing loading.
    (: generating-stack (-> (List Syntax) (Pair (List String) (List Syntax))))
    (define (generating-stack forms)
      (match forms
        ((Cons (Form (Cons (Ident "generating" _ _) keys) _) rest)
         (Pair (map loading-key keys) rest))
        (_ (Pair (Nil) forms))))

    (: loading-key (-> Syntax String))
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
     (only (scheme base) guard error-object-message list)
     (only (chibi string) string-contains)
     (snail stage0 testing))
    (begin
      (define (input-error text)
        (guard (failure (#t (error-object-message failure)))
          (parse-request text "input.datum")
          "accepted"))

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
        (test-generated-inputs))

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
