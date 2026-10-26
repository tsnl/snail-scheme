;; Concrete missing-input requests. A resident caller consumes the typed value;
;; a process caller publishes and parses its datum after compilation unwinds.
(define-library (lofi compiler inputs)
  (export
   CompilerRequest
   GenerateInput
   ArtifactInput
   request->string
   parse-request
   request-input!
   take-input-request!
   publish-input-request!
   generated-syntax)
  (import
   (lofi base)
   (lofi io)
   (lofi compiler read)
   (only (lofi compiler core) fnv-1a))
  (begin

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

    (: request-input! (All (A) (-> CompilerRequest A ! mut)))
    (define (request-input! request)
      (ref-set! pending-request (Some request))
      (panic "compiler requires an input"))

    (: take-input-request! (-> (Option CompilerRequest) ! mut))
    (define (take-input-request!)
      (let ((request (ref-get pending-request)))
        (ref-set! pending-request (None))
        request))

    (: publish-input-request! (-> String Unit ! mut fs))
    (define (publish-input-request! directory)
      (match (take-input-request!)
        ((Some request) (write-file (string-append directory "/request.datum") (request->string request)))
        ((None) (unit))))

    (: request->string (-> CompilerRequest String))
    (define (request->string request)
      (match request
        ((GenerateInput key) (string-append "(generate " (quoted key) ")\n"))
        ((ArtifactInput name source)
         (string-append "(artifact " (quoted name) " " (quoted (Loc-file source)) " "
                        (i64->string (Loc-line source)) " " (i64->string (Loc-column source)) ")\n"))))

    (: parse-request (-> String String CompilerRequest))
    (define (parse-request text filename)
      (match (read-text text filename)
        ((Cons (Form (Cons (Ident "generate" _ _) (Cons (Atom (DString key) _) (Nil))) loc) (Nil))
         (unless (generated-key? key) (compile-error loc "expected a nonempty decimal generator key"))
         (GenerateInput key))
        ((Cons (Form (Cons (Ident "artifact" _ _)
                           (Cons (Atom (DString name) _)
                                 (Cons (Atom (DString file) _)
                                       (Cons (Atom (DInt line) _) (Cons (Atom (DInt column) _) (Nil))))))
                     loc)
               (Nil))
         (unless (and (> line 0) (> column 0)) (compile-error loc "artifact source positions start at one"))
         (ArtifactInput name (Loc file line column)))
        (_ (compile-error (Loc filename 1 1) "expected exactly one generate or artifact compiler request"))))

    (: generated-key? (-> String Bool))
    (define (generated-key? key)
      (and (> (string-length key) 0)
           (every? (lambda (c) (let ((value (char->integer c))) (and (>= value 48) (<= value 57)))) (string->list key))))

    (: quoted (-> String String))
    (define (quoted text)
      (datum->string (DString text)))

    ;; ---- Invocation inputs ----

    (: generated-syntax (-> String (List Syntax) Bytes ! mut fs))
    (define (generated-syntax directory forms)
      (let* ((text (string-join (map syntax->string forms) "\n")) (key (i64->string (fnv-1a text)))
             (output (string-append directory "/" key ".syntax")))
        (if (file-exists? output)
            (read-bytes output)
            (begin (write-file (string-append directory "/" key ".sld") text)
                   (request-input! (GenerateInput key))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-inputs)
    (import
     (only (scheme base) guard error-object-message list)
     (only (chibi string) string-contains)
     (lofi testing))
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
                    (expect (if (string-contains (input-error text) "input.datum:") "rejected" "accepted") "rejected"))
                  '("" "(generate \"\")" "(generate \"../x\")" "(generate \"-1\")" "(generate 123)"
                    "(generate \"123\") ()" "(generate \"123\" extra)" "(artifact \"x\")"
                    "(artifact \"x\" \"file\" 0 1)" "(artifact \"x\" \"file\" 1 -1)")))))
   (else)))
