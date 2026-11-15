;; `snail-scheme lsp`, the language server editors start: the Language Server
;; Protocol over standard input and output, for one project, the folder the
;; editor opened, whose project.datum names its targets. Zed starts it
;; through editors/zed; any editor that speaks the protocol can.
;;
;; It answers from the project's development build, the one `snail-scheme watch`
;; makes, built in this process when the editor opens the project and each
;; time it saves a file. The build reads the disk, so what it reports is
;; what was saved:
;;
;; - diagnostics: each failure the build met, at its place;
;; - hover: a name's type where it is used, as the checker instantiated it;
;; - definition: where a name used is defined, a global's definition or
;;   the form that binds a local;
;; - formatting: the open text as (snail shell format) formats it, which
;;   needs no build.
;;
;; The server does one thing at a time: a request that arrives during a
;; build waits for it. Only messages from the editor drive it, and it ends
;; when its input does or the editor says to exit.
(define-library (snail shell lsp)
  (export
   serve-language)
  (import
   (snail core base)
   (snail core io)
   (snail core table)
   (snail shell json)
   (snail shell json read)
   (snail shell utf8)
   (only (snail shell text) string-downcase)
   (only (snail shell format) format-source format-width)
   (only (snail shell highlight) highlight-range)
   (only (snail shell compiler read)
         Loc
         SourceDiagnostic
         diagnostics->list
         diagnostic->string)
   (only (snail shell compiler core)
         Type
         type->string
         Expr
         Term
         Var
         Lambda
         Let
         Item
         Define
         expr-children
         short-name
         local-name
         name-owner)
   (only (snail shell compiler check) Typed)
   (only (snail shell project) target-name)
   (only (snail shell process) process)
   (snail shell project build))
  (begin

    ;; ---- Messages ----

    ;; What standard input held next: a message, text that was not one, or
    ;; its end. Each message is headers, a blank line, and a body of as many
    ;; bytes of UTF-8 JSON as its Content-Length says.
    (enum Incoming
      (Message ((json Json)))
      (Malformed)
      (Ended))

    (define (read-message) (→ Incoming) (! input-port)
      (match (read-headers (None))
        ((None) (Ended))
        ((Some length)
         (match (string->json (read-body length))
           ((Some json) (Message json))
           ((None) (Malformed))))))

    ;; The Content-Length, once the blank line after the headers is read,
    ;; or None if the input ends first. Each header line ends in CR LF.

    (define (read-headers (length (Option I64))) (→ (Option I64)) (! input-port)
      (match (read-line)
        ((None) (None))
        ((Some line)
         (let ((header (without-return line)))
           (cond
            ((string=? header "") (match length ((Some _) length) ((None) (read-headers length))))
            ((has-prefix? (string-downcase header) "content-length:")
             (read-headers (string->i64 (trimmed (substring header 15 (string-length header))))))
            (else (read-headers length)))))))

    ;; Characters until their UTF-8 encoding is `length` bytes long.

    (define (read-body (length I64)) (→ String) (! input-port)
      (let loop ((left length) (chars (Nil)))
        (if (<= left 0)
            (list->string (reverse chars))
            (match (read-char)
              ((Some char) (loop (- left (utf8-length char)) (Cons char chars)))
              ((None) (list->string (reverse chars)))))))

    (define (utf8-length (char Char)) (→ I64)
      (let ((code (char->i32 char)))
        (cond ((< code 128) 1)
              ((< code 2048) 2)
              ((< code 65536) 3)
              (else 4))))

    (define (write-message (json Json)) (→ Unit) (! output-port)
      (let ((text (json->string json)))
        (write-string (string-append "Content-Length: "
                                     (show (vector-length (string->utf8 text)))
                                     "\r\n\r\n"
                                     text))))

    (define (respond (id Json) (result Json)) (→ Unit) (! output-port)
      (write-message (object (list (field "jsonrpc" (JsonString "2.0"))
                                   (field "id" id)
                                   (field "result" result)))))

    (define (refuse (id Json) (code I64) (message String)) (→ Unit) (! output-port)
      (write-message
       (object (list (field "jsonrpc" (JsonString "2.0"))
                     (field "id" id)
                     (field "error" (object (list (field "code" (JsonInteger code))
                                                  (field "message" (JsonString message)))))))))

    (define (notify (method String) (params Json)) (→ Unit) (! output-port)
      (write-message (object (list (field "jsonrpc" (JsonString "2.0"))
                                   (field "method" (JsonString method))
                                   (field "params" params)))))

    ;; ---- JSON ----

    (define (object (members (List (Pair String Json)))) (→ Json)
      (JsonObject members))

    (define (field (name String) (value Json)) (→ (Pair String Json))
      (new Pair (first name) (second value)))

    (define (member-at (json Json) (path (List String))) (→ (Option Json))
      (match path
        ((Nil) (Some json))
        ((Cons name rest)
         (match (json-member json name)
           ((Some inner) (member-at inner rest))
           ((None) (None))))))

    (define (text-at (json Json) (path (List String))) (→ (Option String))
      (match (member-at json path)
        ((Some (JsonString text)) (Some text))
        (_ (None))))

    (define (integer-at (json Json) (path (List String))) (→ I64)
      (match (member-at json path)
        ((Some (JsonInteger value)) value)
        (_ 0)))

    ;; ---- Text ----

    (define (without-return (line String)) (→ String)
      (let ((length (string-length line)))
        (if (and (> length 0) (char=? (string-ref line (- length 1)) #\return))
            (substring line 0 (- length 1))
            line)))

    (define (trimmed (text String)) (→ String)
      (list->string (filter (lambda (char) (not (char-whitespace? char))) (string->list text))))

    (define (has-prefix? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; ---- Documents ----

    ;; A file the editor has open, by its path, with the text it holds,
    ;; which formatting reads and positions are counted in.
    (record Document
      ((path String)
       (text String)))

    ;; A file URI's path: `file://` and then the path, with each `%XX` the
    ;; byte it stands for.

    (define (uri->path (uri String)) (→ (Option String))
      (if (has-prefix? uri "file://")
          (match (utf8->string (list->vector (percent-decoded (string->list (substring uri
                                                                                       7
                                                                                       (string-length
                                                                                        uri))))))
            ((Ok path) (Some path))
            ((Err _) (None)))
          (None)))

    (define (percent-decoded (chars (List Char))) (→ (List U8))
      (match chars
        ((Nil) (Nil))
        ((Cons #\% (Cons high (Cons low rest)))
         (match (new Pair (first (hex-value high)) (second (hex-value low)))
           ((Pair (Some high) (Some low))
            (Cons (i32->u8 (+ (* high 16) low)) (percent-decoded rest)))
           (_ (append (vector->list (string->utf8 "%"))
                      (percent-decoded (Cons high (Cons low rest)))))))
        ((Cons char rest)
         (append (vector->list (string->utf8 (make-string 1 char))) (percent-decoded rest)))))

    (define (hex-value (char Char)) (→ (Option I32))
      (let ((code (char->i32 char)))
        (cond ((and (>= code 48) (<= code 57)) (Some (- code 48)))
              ((and (>= code 65) (<= code 70)) (Some (- code 55)))
              ((and (>= code 97) (<= code 102)) (Some (- code 87)))
              (else (None)))))

    ;; A path's URI, each byte that is not unreserved, nor a slash, as `%XX`.

    (define (path->uri (path String)) (→ String)
      (string-append "file://"
                     (string-concatenate (map uri-byte (vector->list (string->utf8 path))))))

    (define (uri-byte (byte U8)) (→ String)
      (let ((code (u8->i32 byte)))
        (if (or (and (>= code 48) (<= code 57))
                (and (>= code 65) (<= code 90))
                (and (>= code 97) (<= code 122))
                (member? code (list 45 46 47 95 126)))
            (make-string 1 (i32->char code))
            (string-append "%" (hex-digit (quotient code 16)) (hex-digit (remainder code 16))))))

    (define (hex-digit (value I32)) (→ String)
      (make-string 1 (string-ref "0123456789ABCDEF" (i32->i64 value))))

    (define (document-text (documents (List Document)) (path String)) (→ (Option String)) (! fs)
      (match (find (lambda (document) (string=? (● document path) path)) documents)
        ((Some document) (Some (● document text)))
        ((None)
         (match (read-text-file path 67108864)
           ((Ok text) (Some text))
           ((Err _) (None))))))

    ;; ---- Positions ----

    ;; The protocol counts a line's characters in UTF-16 code units; the
    ;; compiler counts a Loc's columns in characters from 1, and its lines
    ;; from 1. These convert between those and an index into the text.

    (define (code-units (char Char)) (→ I64)
      (if (>= (char->i32 char) 65536) 2 1))

    (define (line-start (chars (Vector Char)) (line I64)) (→ I64)
      (let loop ((index 0) (line line))
        (cond ((<= line 0) index)
              ((>= index (vector-length chars)) index)
              ((char=? (vector-ref chars index) #\newline) (loop (+ index 1) (- line 1)))
              (else (loop (+ index 1) line)))))

    ;; The index of a position's character, at most the end of its line.

    (define (position->index (chars (Vector Char)) (line I64) (units I64)) (→ I64)
      (let loop ((index (line-start chars line)) (left units))
        (cond ((<= left 0) index)
              ((>= index (vector-length chars)) index)
              ((char=? (vector-ref chars index) #\newline) index)
              (else (loop (+ index 1) (- left (code-units (vector-ref chars index))))))))

    (define (index->position (chars (Vector Char)) (index I64)) (→ Json)
      (let loop ((at 0) (line 0) (units 0))
        (cond ((or (>= at index) (>= at (vector-length chars)))
               (object
                (list (field "line" (JsonInteger line)) (field "character" (JsonInteger units)))))
              ((char=? (vector-ref chars at) #\newline) (loop (+ at 1) (+ line 1) 0))
              (else (loop (+ at 1) line (+ units (code-units (vector-ref chars at))))))))

    (define (loc->index (chars (Vector Char)) (loc Loc)) (→ I64)
      (min (vector-length chars)
           (+ (line-start chars (- (● loc line) 1)) (max 0 (- (● loc column) 1)))))

    (define (index->loc (chars (Vector Char)) (file String) (index I64)) (→ Loc)
      (let loop ((at 0) (line 1) (column 1))
        (cond ((>= at index) (new Loc (file file) (line line) (column column)))
              ((char=? (vector-ref chars at) #\newline) (loop (+ at 1) (+ line 1) 1))
              (else (loop (+ at 1) line (+ column 1))))))

    (define (range (chars (Vector Char)) (start I64) (end I64)) (→ Json)
      (object (list (field "start" (index->position chars start))
                    (field "end" (index->position chars end)))))

    ;; The token a compiler point names, as the editor should mark it: the
    ;; name, literal or bracketed datum that starts there.

    (define (loc-range (text String) (loc Loc)) (→ Json)
      (let* ((chars (string->vector text)) (marked (highlight-range text (loc->index chars loc))))
        (range chars (● marked first) (● marked second))))

    ;; ---- Diagnostics ----

    ;; A failure as the editor shows it: in a file, at a point or at its
    ;; start, with a message.
    (record Report
      ((file String)
       (loc (Option Loc))
       (message String)))

    ;; A diagnostic about no file, or a file that is not there, or a failure
    ;; of the build's own work, is the project's, and shows on its
    ;; project.datum. One in line 0 is about its file as a whole.

    (define (failure-reports (project String) (failure Failure)) (→ (List Report)) (! fs)
      (match failure
        ((CompileFailure diagnostics)
         (map (lambda (diagnostic) (diagnostic-report project diagnostic))
              (diagnostics->list diagnostics)))
        ((BuildFailure message) (list (project-report project message)))))

    (define (diagnostic-report (project String) (diagnostic SourceDiagnostic)) (→ Report) (! fs)
      (let ((loc (● diagnostic loc)))
        (cond ((= (string-length (● loc file)) 0) (project-report project (● diagnostic message)))
              ((not (file-exists? (absolute project (● loc file))))
               (project-report project (diagnostic->string diagnostic)))
              ((> (● loc line) 0)
               (new Report (file (absolute project (● loc file))) (loc (Some loc))
                    (message (● diagnostic message))))
              (else
               (new Report (file (absolute project (● loc file))) (loc (None))
                    (message (diagnostic->string diagnostic)))))))

    (define (project-report (project String) (message String)) (→ Report)
      (new Report (file (string-append project "/project.datum")) (loc (None)) (message message)))

    (define (absolute (project String) (file String)) (→ String)
      (if (has-prefix? file "/") file (string-append project "/" file)))

    ;; Each file's reports, and an empty list for each file reported before
    ;; that has none now, so the editor clears it. Answers the files
    ;; reported.

    (define (publish (documents (List Document)) (before (List String)) (reports (List Report)))
      (→ (List String))
      (! fs output-port)
      (let ((files (delete-duplicates string=? (map (lambda (report) (● report file)) reports))))
        (for-each (lambda (file)
                    (publish-file documents
                                  file
                                  (filter (lambda (report) (string=? (● report file) file))
                                          reports)))
                  (append files (filter (lambda (file) (not (member? file files))) before)))
        files))

    (define (publish-file (documents (List Document)) (file String) (reports (List Report)))
      (→ Unit)
      (! fs output-port)
      (let ((text (match (document-text documents file) ((Some text) text) ((None) ""))))
        (notify "textDocument/publishDiagnostics"
                (object (list (field "uri" (JsonString (path->uri file)))
                              (field "diagnostics"
                                     (JsonArray (map (lambda (report) (report->json text report))
                                                     reports))))))))

    (define (report->json (text String) (report Report)) (→ Json)
      (object (list (field "range" (match (● report loc)
                                     ((Some loc) (loc-range text loc))
                                     ((None) (range (string->vector text) 0 0))))
                    (field "severity" (JsonInteger 1))
                    (field "source" (JsonString "snail-scheme"))
                    (field "message" (JsonString (● report message))))))

    ;; ---- Names ----

    ;; What the checker knows of each name in the build's programs: each
    ;; use, by the point it is at, with its type there, and where each name
    ;; is bound. Names are the checker's unique ones, `library:name` for a
    ;; global and `name.N` for a local, so a use leads to one binding.
    (record Use
      ((name String)
       (type Type)))

    (record Index
      ((uses (Table Use))
       (bindings (Table Loc))))

    (define (empty-index) (→ Index)
      (new Index (uses (empty-table)) (bindings (empty-table))))

    (define (loc-key (loc Loc)) (→ String)
      (string-append (● loc file) ":" (show (● loc line)) ":" (show (● loc column))))

    ;; A definition's name is bound at its value, which starts at the form
    ;; that defines it; a local at the form that binds it.

    (define (index-programs (programs (List Typed))) (→ Index)
      (fold-left (lambda (index typed) (fold-left index-item index (● typed items)))
                 (empty-index)
                 programs))

    (define (index-item (index Index) (item Item)) (→ Index)
      (match item
        ((Define name value) (index-expr (bound index name (● value loc)) value))
        (_ index)))

    (define (bound (index Index) (name String) (loc Loc)) (→ Index)
      (Index-bindings-set index (table-set (● index bindings) name loc)))

    (define (index-expr (index Index) (expr Expr)) (→ Index)
      (let ((index (match (● expr term)
                     ((Var name _ _)
                      (Index-uses-set index
                                      (table-set (● index uses)
                                                 (loc-key (● expr loc))
                                                 (new Use (name name) (type (● expr type))))))
                     ((Let name _ _) (bound index name (● expr loc)))
                     ((Lambda params _)
                      (fold-left (lambda (index param) (bound index param (● expr loc)))
                                 index
                                 params))
                     (_ index))))
        (fold-left index-expr index (expr-children expr))))

    ;; The use whose name starts at or runs through `index` in `text`. The
    ;; text there must still spell it: an open text edited since the build
    ;; may have moved another token to the point the use was at.

    (define (use-at (names Index) (path String) (text String) (index I64)) (→ (Option Use))
      (let* ((chars (string->vector text)) (start (name-start chars index)))
        (match (table-ref (● names uses) (loc-key (index->loc chars path start)))
          ((Some use)
           (if (written-at? chars start (string->vector (source-name (● use name))))
               (Some use)
               (None)))
          ((None) (None)))))

    (define (name-start (chars (Vector Char)) (index I64)) (→ I64)
      (if (and (> index 0) (not (delimiter? (vector-ref chars (- index 1)))))
          (name-start chars (- index 1))
          index))

    (define (delimiter? (char Char)) (→ Bool)
      (or (char-whitespace? char) (member? char (string->list "()[]\";'"))))

    (define (source-name (name String)) (→ String)
      (if (string=? (name-owner name) "") (local-name name) (short-name name)))

    ;; ---- The server ----

    ;; The project is the folder the editor opened, once it says which;
    ;; `reported` the files whose diagnostics were last published; `names`
    ;; the last successful build's.
    (record Server
      ((tools Tools)
       (project (Option String))
       (documents (List Document))
       (reported (List String))
       (names Index)
       (exiting Bool)))

    (define (serve-language (tools Tools)) (→ Unit) (! mut fs clock process input-port output-port)
      (serve (new Server (tools tools) (project (None)) (documents (Nil)) (reported (Nil))
                  (names (empty-index)) (exiting #f))))

    (define (serve (server Server)) (→ Unit) (! mut fs clock process input-port output-port)
      (match (read-message)
        ((Ended) (unit))
        ((Malformed)
         (refuse (JsonNull) -32700 "the message is not JSON")
         (serve server))
        ((Message json)
         (let ((next (receive server json)))
           (unless (● next exiting) (serve next))))))

    ;; A message with an id is a request, answered; one without, a
    ;; notification. A reply to a request of the server's has no method,
    ;; and the server sends none.

    (define (receive (server Server) (json Json)) (→ Server) (! mut fs clock process output-port)
      (let ((params (match (json-member json "params") ((Some params) params) ((None) (JsonNull)))))
        (match (new Pair (first (json-member json "id")) (second (text-at json (list "method"))))
          ((Pair (Some id) (Some method)) (request server id method params))
          ((Pair (None) (Some method)) (notified server method params))
          (_ server))))

    (define (request (server Server) (id Json) (method String) (params Json))
      (→ Server)
      (! fs output-port)
      (cond ((string=? method "initialize")
             (respond id (capabilities))
             (Server-project-set server (project-of params)))
            ((string=? method "shutdown") (respond id (JsonNull)) server)
            ((string=? method "textDocument/formatting")
             (respond id (formatting server params))
             server)
            ((string=? method "textDocument/hover")
             (respond id (hover server params))
             server)
            ((string=? method "textDocument/definition")
             (respond id (definition server params))
             server)
            (else (refuse id -32601 (string-append "snail-scheme lsp does not answer " method))
                  server)))

    (define (notified (server Server) (method String) (params Json))
      (→ Server)
      (! mut fs clock process output-port)
      (cond ((string=? method "initialized") (checked server))
            ((string=? method "textDocument/didOpen")
             (opened server (text-at params (list "textDocument" "uri"))
                     (text-at params (list "textDocument" "text"))))
            ((string=? method "textDocument/didChange")
             (opened server (text-at params (list "textDocument" "uri")) (changed-text params)))
            ((string=? method "textDocument/didClose") (closed server params))
            ((string=? method "textDocument/didSave") (checked server))
            ((string=? method "exit") (Server-exiting-set server #t))
            (else server)))

    ;; Full text in every change, as the capabilities ask: the last change
    ;; holds the document.

    (define (capabilities) (→ Json)
      (object
       (list (field "capabilities"
                    (object (list (field "textDocumentSync"
                                         (object (list (field "openClose" (JsonBool #t))
                                                       (field "change" (JsonInteger 1))
                                                       (field "save" (JsonBool #t)))))
                                  (field "documentFormattingProvider" (JsonBool #t))
                                  (field "hoverProvider" (JsonBool #t))
                                  (field "definitionProvider" (JsonBool #t)))))
             (field "serverInfo" (object (list (field "name" (JsonString "snail-scheme"))))))))

    ;; The folder opened: the first workspace folder, the root URI, or the
    ;; root path, the protocol's names for it from newest to oldest.

    (define (project-of (params Json)) (→ (Option String))
      (match (member-at params (list "workspaceFolders"))
        ((Some (JsonArray (Cons folder _)))
         (match (text-at folder (list "uri")) ((Some uri) (uri->path uri)) ((None) (None))))
        (_
         (match (text-at params (list "rootUri"))
           ((Some uri) (uri->path uri))
           ((None) (text-at params (list "rootPath")))))))

    (define (changed-text (params Json)) (→ (Option String))
      (match (member-at params (list "contentChanges"))
        ((Some (JsonArray changes))
         (match (reverse changes)
           ((Cons change _) (text-at change (list "text")))
           ((Nil) (None))))
        (_ (None))))

    (define (opened (server Server) (uri (Option String)) (text (Option String))) (→ Server)
      (match (new Pair
               (first (match uri ((Some uri) (uri->path uri)) ((None) (None))))
               (second text))
        ((Pair (Some path) (Some text))
         (Server-documents-set server
                               (Cons (new Document (path path) (text text))
                                     (without-document (● server documents) path))))
        (_ server)))

    (define (closed (server Server) (params Json)) (→ Server)
      (match (match (text-at params (list "textDocument" "uri"))
               ((Some uri) (uri->path uri))
               ((None) (None)))
        ((Some path) (Server-documents-set server (without-document (● server documents) path)))
        ((None) server)))

    (define (without-document (documents (List Document)) (path String)) (→ (List Document))
      (filter (lambda (document) (not (string=? (● document path) path))) documents))

    ;; ---- Building ----

    ;; Builds every target of the project, as `snail-scheme watch` does, then
    ;; publishes what failed and keeps the programs' names. A build that
    ;; failed keeps the names of the last that did not. The generations go
    ;; once their programs are read: the server publishes nothing.

    (define (checked (server Server)) (→ Server) (! mut fs clock process output-port)
      (match (● server project)
        ((None) server)
        ((Some project)
         (if (file-exists? (string-append project "/project.datum"))
             (let* ((built (project-build (● server tools) project))
                    (reported (publish (● server documents) (● server reported) (● built first))))
               (Server-reported-set (match (● built second)
                                      ((Some names) (Server-names-set server names))
                                      ((None) server))
                                    reported))
             server))))

    (define (project-build (tools Tools) (project String))
      (→ (Pair (List Report) (Option Index)))
      (! mut fs clock process)
      (match (read-project project)
        ((Err failure) (new Pair (first (failure-reports project failure)) (second (None))))
        ((Ok description)
         (match (build-project tools project description (map target-name (● description builds))
                               (Development) (string-append (● tools root) "/build/snail-run")
                               ".snail-lsp-")
           ((Err failure) (new Pair (first (failure-reports project failure)) (second (None))))
           ((Ok candidate)
            (discard-candidate candidate)
            (new Pair (first (Nil))
                 (second (Some (index-programs (programs-of candidate))))))))))

    (define (programs-of (candidate Candidate)) (→ (List Typed))
      (fold-right (lambda (output programs)
                    (match (● output typed)
                      ((Some typed) (Cons typed programs))
                      ((None) programs)))
                  (Nil)
                  (● candidate outputs)))

    ;; ---- Requests ----

    ;; The document a request names, with its path, if the editor has it
    ;; open.

    (define (requested (server Server) (params Json)) (→ (Option Document))
      (match (match (text-at params (list "textDocument" "uri"))
               ((Some uri) (uri->path uri))
               ((None) (None)))
        ((Some path) (find (lambda (document) (string=? (● document path) path))
                           (● server documents)))
        ((None) (None))))

    ;; One edit that replaces the whole text, or none when it is formatted.

    (define (formatting (server Server) (params Json)) (→ Json)
      (match (requested server params)
        ((Some document)
         (let* ((text (● document text)) (formatted (format-source text (format-width))))
           (if (string=? text formatted)
               (JsonArray (Nil))
               (JsonArray
                (list (object (list (field "range"
                                           (range (string->vector text) 0 (string-length text)))
                                    (field "newText" (JsonString formatted)))))))))
        ((None) (JsonNull))))

    (define (requested-use (server Server) (params Json)) (→ (Option Use))
      (match (requested server params)
        ((Some document)
         (let ((chars (string->vector (● document text))))
           (use-at (● server names)
                   (● document path)
                   (● document text)
                   (position->index chars
                                    (integer-at params (list "position" "line"))
                                    (integer-at params (list "position" "character"))))))
        ((None) (None))))

    ;; A global shows the library it is from.

    (define (hover (server Server) (params Json)) (→ Json)
      (match (requested-use server params)
        ((Some use)
         (let ((name (● use name)))
           (object
            (list (field "contents"
                         (object (list (field "kind" (JsonString "markdown"))
                                       (field "value"
                                              (JsonString
                                               (string-append "```snail\n" (source-name name) " : "
                                                              (type->string (● use type)) "\n```"
                                                              (if (string=? (name-owner name) "")
                                                                  ""
                                                                  (string-append "\n\nfrom `"
                                                                                 (name-owner name)
                                                                                 "`"))))))))))))
        ((None) (JsonNull))))

    (define (definition (server Server) (params Json)) (→ Json) (! fs)
      (match (requested-use server params)
        ((Some use)
         (match (table-ref (● (● server names) bindings) (● use name))
           ((Some loc)
            (match (document-text (● server documents) (● loc file))
              ((Some text)
               (object (list (field "uri" (JsonString (path->uri (● loc file))))
                             (field "range" (name-range text loc (source-name (● use name)))))))
              ((None) (JsonNull))))
           ((None) (JsonNull))))
        ((None) (JsonNull))))

    ;; A binding's point is the form that binds the name; the editor marks
    ;; the name itself, the first token in the form that is written as it.

    (define (name-range (text String) (loc Loc) (name String)) (→ Json)
      (let* ((chars (string->vector text))
             (form (highlight-range text (loc->index chars loc)))
             (written (string->vector name)))
        (match (find (lambda (start) (written-at? chars start written))
                     (map (lambda (offset) (+ (● form first) offset))
                          (iota (max 0 (- (● form second) (● form first))))))
          ((Some start) (range chars start (+ start (vector-length written))))
          ((None) (range chars (● form first) (● form second))))))

    ;; Whether the token at `start` is `written`, delimited on both sides.

    (define (written-at? (chars (Vector Char)) (start I64) (written (Vector Char))) (→ Bool)
      (let ((end (+ start (vector-length written))))
        (and (<= end (vector-length chars))
             (or (= start 0) (delimiter? (vector-ref chars (- start 1))))
             (or (= end (vector-length chars)) (delimiter? (vector-ref chars end)))
             (every? (lambda (offset)
                       (char=? (vector-ref chars (+ start offset)) (vector-ref written offset)))
                     (iota (vector-length written))))))))
