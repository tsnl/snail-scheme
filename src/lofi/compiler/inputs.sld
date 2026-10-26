;; The compiler's two concrete requests and replies across a process
;; restart. Framing and field types are parsed once here, on both hosts.
;; The native builder owns artifact path ordering, uniqueness and backing
;; file immutability; this protocol is not a filesystem sandbox.
(define-library (lofi compiler inputs)
  (export
   CompilerRequest
   GenerateInput
   ArtifactInput
   request->string
   parse-request
   ArtifactReply
   ArtifactReply-name
   ArtifactReply-files
   replies->string
   parse-replies
   request-input!
   take-input-request!
   publish-input-request!
   generated-syntax
   read-replies
   load-artifacts)
  (import
   (lofi base)
   (lofi table)
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

    ;; ---- Artifact replies ----

    (struct ArtifactReply
      ((name String)
       (files (List (Pair String String)))))

    (: replies->string (-> (List ArtifactReply) String))
    (define (replies->string replies)
      (string-append "(" (string-join (map reply->string replies) "\n ") ")\n"))

    (: reply->string (-> ArtifactReply String))
    (define (reply->string reply)
      (string-append "(artifact " (quoted (ArtifactReply-name reply))
                     (string-concatenate (map (lambda (file) (string-append " (file " (quoted (Pair-first file)) " " (quoted (Pair-second file)) ")"))
                                              (ArtifactReply-files reply)))
                     ")"))

    (: parse-replies (-> String String (List ArtifactReply)))
    (define (parse-replies text filename)
      (match (read-text text filename)
        ((Cons (Form entries _) (Nil)) (map parse-reply entries))
        (_ (compile-error (Loc filename 1 1) "expected exactly one artifact reply list"))))

    (: parse-reply (-> Syntax ArtifactReply))
    (define (parse-reply syntax)
      (match syntax
        ((Form (Cons (Ident "artifact" _ _) (Cons (Atom (DString name) _) files)) _)
         (ArtifactReply name (map parse-file files)))
        (_ (compile-error (syntax-loc syntax) "expected (artifact name file ...)"))))

    (: parse-file (-> Syntax (Pair String String)))
    (define (parse-file syntax)
      (match syntax
        ((Form (Cons (Ident "file" _ _) (Cons (Atom (DString relative) _) (Cons (Atom (DString path) _) (Nil)))) _)
         (Pair relative path))
        (_ (compile-error (syntax-loc syntax) "expected (file relative-name immutable-path)"))))

    ;; ---- Invocation inputs ----

    (: generated-syntax (-> String (List Syntax) Bytes ! mut fs))
    (define (generated-syntax directory forms)
      (let* ((text (string-join (map syntax->string forms) "\n")) (key (i64->string (fnv-1a text)))
             (output (string-append directory "/" key ".syntax")))
        (if (file-exists? output)
            (read-bytes output)
            (begin (write-file (string-append directory "/" key ".sld") text)
                   (request-input! (GenerateInput key))))))

    (: read-replies (-> String (List ArtifactReply) ! fs))
    (define (read-replies path)
      (if (file-exists? path) (parse-replies (read-file path) path) (Nil)))

    ;; Snapshot every supplied target once before expansion. The resulting
    ;; table has no backing paths or callbacks that can read the filesystem.
    (: load-artifacts (-> String (Table (List (Pair String Bytes))) ! fs))
    (define (load-artifacts directory)
      (fold-left (lambda (inputs reply)
                   (table-set inputs (ArtifactReply-name reply)
                              (map (lambda (file) (Pair (Pair-first file) (read-bytes (Pair-second file))))
                                   (ArtifactReply-files reply))))
                 empty-table (read-replies (string-append directory "/artifacts.datum"))))

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
      (define (input-error parse text)
        (guard (failure (#t (error-object-message failure)))
          (parse text "input.datum")
          "accepted"))

      (define (test-inputs)
        (let ((request (ArtifactInput "client\"\n" (Loc "source\\name.sld" 12 7)))
              (replies (list (ArtifactReply "empty" '())
                             (ArtifactReply "client" (list (Pair "quote\".txt" "/tmp/a\\b") (Pair "line\n.txt" "/tmp/c"))))))
          (expect (parse-request (request->string request) "request.datum") request)
          (expect (parse-replies (replies->string replies) "replies.datum") replies)
          (expect (parse-request "(generate \"123456\")" "request.datum") (GenerateInput "123456")))
        (for-each (lambda (text)
                    (expect (if (string-contains (input-error parse-request text) "input.datum:") "rejected" "accepted") "rejected"))
                  '("" "(generate \"\")" "(generate \"../x\")" "(generate \"-1\")" "(generate 123)"
                    "(generate \"123\") ()" "(generate \"123\" extra)" "(artifact \"x\")"
                    "(artifact \"x\" \"file\" 0 1)" "(artifact \"x\" \"file\" 1 -1)"))
        (for-each (lambda (text)
                    (expect (if (string-contains (input-error parse-replies text) "input.datum:") "rejected" "accepted") "rejected"))
                  '("" "() ()" "((artifact name))" "((artifact \"x\" (file \"a\")))"
                    "((artifact \"x\" (file \"a\" \"b\" extra)))")))))
   (else)))
