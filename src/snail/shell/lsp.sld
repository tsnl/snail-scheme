;; `snail-scheme lsp`, the language server editors start: the Language Server
;; Protocol over standard input and output, for one workspace, the folder the
;; editor opened. Zed and VS Code start it through
;; editors/zed and editors/vscode; any editor that speaks the protocol can.
;;
;; It answers from checking each document the editor has open, in this
;; process, as a build would, whenever the editor opens or saves a file: a
;; script for the platform it is built for, a page when a public/ folder is
;; beside it and Node otherwise, and a library under src/ as the program
;; that imports it. A check reads the disk, so what it reports is what was
;; saved:
;;
;; - diagnostics: each failure a check met, at its place;
;; - hover: a name's type where it is used, as the checker instantiated it;
;; - definition: where a name used is defined, a global's definition or
;;   the form that binds a local;
;; - formatting: the open text as (snail shell format) formats it, which
;;   needs no check;
;; - colours: the open text's tokens as (snail shell highlight) classes
;;   them, which needs no check either.
;;
;; The server does one thing at a time: a request that arrives during a
;; check waits for it. Only messages from the editor drive it, and it ends
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
   (only (snail shell format) format-source format-width)
   (only (snail shell highlight)
         Class
         Comment
         StringLiteral
         CharacterLiteral
         NumberLiteral
         BooleanLiteral
         Keyword
         TypeName
         DefinedName
         Token
         highlight-tokens
         highlight-range)
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
   (only (snail shell process) Processes)
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

    (define (read-message (in InputPort)) (→ Incoming)
      (match (read-headers in (None))
        ((None) (Ended))
        ((Some length)
         (match (string->json (read-body in length))
           ((Some json) (Message json))
           ((None) (Malformed))))))

    ;; The Content-Length, once the blank line after the headers is read,
    ;; or None if the input ends first. Each header line ends in CR LF.

    (define (read-headers (in InputPort) (length (Option I64))) (→ (Option I64))
      (match (read-line in)
        ((None) (None))
        ((Some line)
         (let ((header (without-return line)))
           (cond
            ((string=? header "")
             (match length ((Some _) length) ((None) (read-headers in length))))
            ((has-prefix? (ascii-downcase header) "content-length:")
             (read-headers in (string->i64 (trimmed (substring header 15 (string-length header))))))
            (else (read-headers in length)))))))

    ;; ASCII letters lowered and every other scalar kept: header names
    ;; are ASCII, and Unicode's mapping would also lower the Kelvin sign.

    (define (ascii-downcase (text String)) (→ String)
      (string-generate (string-length text)
                       (lambda (index)
                         (let ((char (string-ref text index)))
                           (if (and (>= char #\A) (<= char #\Z))
                               (integer->char (+ (char->integer char) 32))
                               char)))))

    ;; Characters until their UTF-8 encoding is `length` bytes long.

    (define (read-body (in InputPort) (length I64)) (→ String)
      (let loop ((left length) (chars (Nil)))
        (if (<= left 0)
            (list->string (reverse chars))
            (match ((● in read-char))
              ((Some char) (loop (- left (utf8-length char)) (Cons char chars)))
              ((None) (list->string (reverse chars)))))))

    (define (utf8-length (char Char)) (→ I64)
      (let ((code (char->i32 char)))
        (cond ((< code 128) 1)
              ((< code 2048) 2)
              ((< code 65536) 3)
              (else 4))))

    (define (write-message (out OutputPort) (json Json)) (→ Unit)
      (let ((text (json->string json)))
        ((● out write-string) (string-append "Content-Length: "
                                             (show (array-length (string->utf8 text)))
                                             "\r\n\r\n"
                                             text))))

    (define (respond (out OutputPort) (id Json) (result Json)) (→ Unit)
      (write-message out (object (list (field "jsonrpc" (JsonString "2.0"))
                                       (field "id" id)
                                       (field "result" result)))))

    (define (refuse (out OutputPort) (id Json) (code I64) (message String)) (→ Unit)
      (write-message out
                     (object (list (field "jsonrpc" (JsonString "2.0"))
                                   (field "id" id)
                                   (field "error" (object (list (field "code" (JsonInteger code))
                                                                (field "message"
                                                                       (JsonString message)))))))))

    (define (notify (out OutputPort) (method String) (params Json)) (→ Unit)
      (write-message out (object (list (field "jsonrpc" (JsonString "2.0"))
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
          (match (utf8->string (list->array (percent-decoded (string->list (substring uri
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
           (_ (append (array->list (string->utf8 "%"))
                      (percent-decoded (Cons high (Cons low rest)))))))
        ((Cons char rest)
         (append (array->list (string->utf8 (make-string 1 char))) (percent-decoded rest)))))

    (define (hex-value (char Char)) (→ (Option I32))
      (let ((code (char->i32 char)))
        (cond ((and (>= code 48) (<= code 57)) (Some (- code 48)))
              ((and (>= code 65) (<= code 70)) (Some (- code 55)))
              ((and (>= code 97) (<= code 102)) (Some (- code 87)))
              (else (None)))))

    ;; A path's URI, each byte that is not unreserved, nor a slash, as `%XX`.

    (define (path->uri (path String)) (→ String)
      (string-append "file://"
                     (string-concatenate (map uri-byte (array->list (string->utf8 path))))))

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

    (define (document-text (fs Fs) (documents (List Document)) (path String))
      (→ (Option String))
      (match (find (lambda (document) (string=? (● document path) path)) documents)
        ((Some document) (Some (● document text)))
        ((None)
         (match (read-text-file fs path 67108864)
           ((Ok text) (Some text))
           ((Err _) (None))))))

    ;; ---- Positions ----

    ;; The protocol counts a line's characters in UTF-16 code units; the
    ;; compiler counts a Loc's columns in characters from 1, and its lines
    ;; from 1. These convert between those and an index into the text.

    (define (code-units (char Char)) (→ I64)
      (if (>= (char->i32 char) 65536) 2 1))

    (define (line-start (chars (Array Char)) (line I64)) (→ I64)
      (let loop ((index 0) (line line))
        (cond ((<= line 0) index)
              ((>= index (array-length chars)) index)
              ((char=? (array-ref chars index) #\newline) (loop (+ index 1) (- line 1)))
              (else (loop (+ index 1) line)))))

    ;; The index of a position's character, at most the end of its line.

    (define (position->index (chars (Array Char)) (line I64) (units I64)) (→ I64)
      (let loop ((index (line-start chars line)) (left units))
        (cond ((<= left 0) index)
              ((>= index (array-length chars)) index)
              ((char=? (array-ref chars index) #\newline) index)
              (else (loop (+ index 1) (- left (code-units (array-ref chars index))))))))

    (define (index->position (chars (Array Char)) (index I64)) (→ Json)
      (let loop ((at 0) (line 0) (units 0))
        (cond ((or (>= at index) (>= at (array-length chars)))
               (object
                (list (field "line" (JsonInteger line)) (field "character" (JsonInteger units)))))
              ((char=? (array-ref chars at) #\newline) (loop (+ at 1) (+ line 1) 0))
              (else (loop (+ at 1) line (+ units (code-units (array-ref chars at))))))))

    (define (loc->index (chars (Array Char)) (loc Loc)) (→ I64)
      (min (array-length chars)
           (+ (line-start chars (- (● loc line) 1)) (max 0 (- (● loc column) 1)))))

    (define (index->loc (chars (Array Char)) (file String) (index I64)) (→ Loc)
      (let loop ((at 0) (line 1) (column 1))
        (cond ((>= at index) (new Loc (file file) (line line) (column column)))
              ((char=? (array-ref chars at) #\newline) (loop (+ at 1) (+ line 1) 1))
              (else (loop (+ at 1) line (+ column 1))))))

    (define (range (chars (Array Char)) (start I64) (end I64)) (→ Json)
      (object (list (field "start" (index->position chars start))
                    (field "end" (index->position chars end)))))

    ;; The token a compiler point names, as the editor should mark it: the
    ;; name, literal or bracketed datum that starts there.

    (define (loc-range (text String) (loc Loc)) (→ Json)
      (let* ((chars (string->array text)) (marked (highlight-range text (loc->index chars loc))))
        (range chars (● marked first) (● marked second))))

    ;; ---- Diagnostics ----

    ;; A failure as the editor shows it: in a file, at a point or at its
    ;; start, with a message.
    (record Report
      ((file String)
       (loc (Option Loc))
       (message String)))

    ;; A diagnostic about no file, or a file that is not there, or a failure
    ;; of the check's own work, shows on the document checked. One in line 0
    ;; is about its file as a whole.

    (define (failure-reports (fs Fs) (document String) (failure Failure)) (→ (List Report))
      (match failure
        ((CompileFailure diagnostics)
         (map (lambda (diagnostic) (diagnostic-report fs document diagnostic))
              (diagnostics->list diagnostics)))
        ((BuildFailure message) (list (whole-report document message)))))

    (define (diagnostic-report (fs Fs) (document String) (diagnostic SourceDiagnostic))
      (→ Report)
      (let* ((loc (● diagnostic loc)) (file (● loc file)))
        (cond ((or (= (string-length file) 0) (not (file-exists? fs file)))
               (whole-report document (diagnostic->string diagnostic)))
              ((> (● loc line) 0)
               (new Report (file file) (loc (Some loc)) (message (● diagnostic message))))
              (else (whole-report file (diagnostic->string diagnostic))))))

    (define (whole-report (file String) (message String)) (→ Report)
      (new Report (file file) (loc (None)) (message message)))

    ;; Documents that share a library report its failures once.

    (define (distinct-reports (reports (List Report))) (→ (List Report))
      (let ((key (lambda (report)
                   (string-append (● report file)
                                  (match (● report loc) ((Some loc) (loc-key loc)) ((None) ""))
                                  " "
                                  (● report message)))))
        (delete-duplicates (lambda (a b) (string=? (key a) (key b))) reports)))

    ;; Each file's reports, and an empty list for each file reported before
    ;; that has none now, so the editor clears it. Answers the files
    ;; reported.

    (define (publish (fs Fs)
                     (out OutputPort)
                     (documents (List Document))
                     (before (List String))
                     (reports (List Report)))
      (→ (List String))
      (let ((files (delete-duplicates string=? (map (lambda (report) (● report file)) reports))))
        (for-each (lambda (file)
                    (publish-file fs out documents
                                  file
                                  (filter (lambda (report) (string=? (● report file) file))
                                          reports)))
                  (append files (filter (lambda (file) (not (member? file files))) before)))
        files))

    (define (publish-file (fs Fs)
                          (out OutputPort)
                          (documents (List Document))
                          (file String)
                          (reports (List Report)))
      (→ Unit)
      (let ((text (match (document-text fs documents file) ((Some text) text) ((None) ""))))
        (notify out "textDocument/publishDiagnostics"
                (object (list (field "uri" (JsonString (path->uri file)))
                              (field "diagnostics"
                                     (JsonArray (map (lambda (report) (report->json text report))
                                                     reports))))))))

    (define (report->json (text String) (report Report)) (→ Json)
      (object (list (field "range" (match (● report loc)
                                     ((Some loc) (loc-range text loc))
                                     ((None) (range (string->array text) 0 0))))
                    (field "severity" (JsonInteger 1))
                    (field "source" (JsonString "snail-scheme"))
                    (field "message" (JsonString (● report message))))))

    ;; ---- Names ----

    ;; What the checker knows of each name in the checked programs: each
    ;; use, by the point it is at, with its type there, and where each name
    ;; is bound. Names are the checker's unique ones, `library:name` for a
    ;; global and `name.N` for a local, so a use leads to one binding.
    (record Use
      ((name String)
       (type Type)))

    (record Index
      ((uses (Table Use))
       (bindings (Table Loc))))

    (define empty-index (→ Index)
      (new Index (uses (empty-table)) (bindings (empty-table))))

    (define (loc-key (loc Loc)) (→ String)
      (string-append (● loc file) ":" (show (● loc line)) ":" (show (● loc column))))

    ;; A definition's name is bound at its value, which starts at the form
    ;; that defines it; a local at the form that binds it.

    (define (index-programs (programs (List Typed))) (→ Index)
      (fold-left (lambda (index typed) (fold-left index-item index (● typed items)))
                 empty-index
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
    ;; text there must still spell it: an open text edited since the check
    ;; may have moved another token to the point the use was at.

    (define (use-at (names Index) (path String) (text String) (index I64)) (→ (Option Use))
      (let* ((chars (string->array text)) (start (name-start chars index)))
        (match (table-ref (● names uses) (loc-key (index->loc chars path start)))
          ((Some use)
           (if (written-at? chars start (string->array (source-name (● use name))))
               (Some use)
               (None)))
          ((None) (None)))))

    (define (name-start (chars (Array Char)) (index I64)) (→ I64)
      (if (and (> index 0) (not (delimiter? (array-ref chars (- index 1)))))
          (name-start chars (- index 1))
          index))

    (define (delimiter? (char Char)) (→ Bool)
      (or (char-whitespace? char) (member? char (string->list "()[]\";'"))))

    (define (source-name (name String)) (→ String)
      (if (string=? (name-owner name) "") (local-name name) (short-name name)))

    ;; ---- The server ----

    ;; The workspace is the folder the editor opened, once it says which;
    ;; `reported` the files whose diagnostics were last published; `names`
    ;; those of the programs the last checks typed.
    (record Server
      ((tools Tools)
       (workspace (Option String))
       (documents (List Document))
       (reported (List String))
       (names Index)
       (exiting Bool)))

    (define (serve-language (processes Processes)
                            (fs Fs)
                            (clock Clock)
                            (in InputPort)
                            (out OutputPort)
                            (tools Tools))
      (→ Unit)
      (serve processes
             fs
             clock
             in
             out
             (new Server (tools tools) (workspace (None)) (documents (Nil)) (reported (Nil))
                  (names empty-index) (exiting #f))))

    (define (serve (processes Processes)
                   (fs Fs)
                   (clock Clock)
                   (in InputPort)
                   (out OutputPort)
                   (server Server))
      (→ Unit)
      (match (read-message in)
        ((Ended) (unit))
        ((Malformed)
         (refuse out (JsonNull) -32700 "the message is not JSON")
         (serve processes fs clock in out server))
        ((Message json)
         (let ((next (receive processes fs clock out server json)))
           (unless (● next exiting) (serve processes fs clock in out next))))))

    ;; A message with an id is a request, answered; one without, a
    ;; notification. A reply to a request of the server's has no method,
    ;; and the server sends none.

    (define (receive (processes Processes)
                (fs Fs)
              (clock Clock)
              (out OutputPort)
              (server Server)
              (json Json))
      (→ Server)
      (let ((params (match (json-member json "params") ((Some params) params) ((None) (JsonNull)))))
        (match (new Pair (first (json-member json "id")) (second (text-at json (list "method"))))
          ((Pair (Some id) (Some method)) (request fs out server id method params))
          ((Pair (None) (Some method)) (notified processes fs clock out server method params))
          (_ server))))

    (define (request (fs Fs)
                     (out OutputPort)
                     (server Server)
                     (id Json)
                     (method String)
                     (params Json))
      (→ Server)
      (cond ((string=? method "initialize")
             (respond out id capabilities)
             (Server-workspace-set server (opened-folder params)))
            ((string=? method "shutdown") (respond out id (JsonNull)) server)
            ((string=? method "textDocument/formatting")
             (respond out id (formatting server params))
             server)
            ((string=? method "textDocument/hover")
             (respond out id (hover server params))
             server)
            ((string=? method "textDocument/definition")
             (respond out id (definition fs server params))
             server)
            ((string=? method "textDocument/semanticTokens/full")
             (respond out id (colours server params))
             server)
            (else (refuse out id -32601 (string-append "snail-scheme lsp does not answer " method))
                  server)))

    (define (notified (processes Processes)
                      (fs Fs)
                      (clock Clock)
                      (out OutputPort)
                      (server Server)
                      (method String)
                      (params Json))
      (→ Server)
      (cond ((string=? method "initialized") (checked processes fs clock out server))
            ((string=? method "textDocument/didOpen")
             (checked processes fs clock out (opened server
                                                     (text-at params
                                                              (list "textDocument" "uri"))
                                                     (text-at params
                                                              (list "textDocument" "text")))))
            ((string=? method "textDocument/didChange")
             (opened server (text-at params (list "textDocument" "uri")) (changed-text params)))
            ((string=? method "textDocument/didClose") (closed server params))
            ((string=? method "textDocument/didSave") (checked processes fs clock out server))
            ((string=? method "exit") (Server-exiting-set server #t))
            (else server)))

    ;; Full text in every change, as the capabilities ask: the last change
    ;; holds the document.

    (define capabilities (→ Json)
      (object
       (list (field "capabilities"
                    (object (list (field "textDocumentSync"
                                         (object (list (field "openClose" (JsonBool #t))
                                                       (field "change" (JsonInteger 1))
                                                       (field "save" (JsonBool #t)))))
                                  (field "documentFormattingProvider" (JsonBool #t))
                                  (field "hoverProvider" (JsonBool #t))
                                  (field "definitionProvider" (JsonBool #t))
                                  (field "semanticTokensProvider"
                                         (object (list (field "legend" legend)
                                                       (field "full" (JsonBool #t))))))))
             (field "serverInfo" (object (list (field "name" (JsonString "snail-scheme"))))))))

    ;; The folder opened: the first workspace folder, the root URI, or the
    ;; root path, the protocol's names for it from newest to oldest.

    (define (opened-folder (params Json)) (→ (Option String))
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

    ;; ---- Checking ----

    ;; What a document is checked as: a script, for the platform it is
    ;; built for, or a library of a workspace, by its name.
    (enum Check
      (ScriptCheck
       ((script Script)
        (platform Platform)))
      (LibraryCheck
       ((workspace String)
        (name (List String)))))

    ;; A .scm file is a script, a page when a public/ folder is beside it;
    ;; an .sld file under its workspace's src/ is the library its path
    ;; there names. A document uses the same workspace discovery as a build.

    (define (document-check (fs Fs) (workspace String) (path String)) (→ (Option Check))
      (if (and (has-prefix? path (string-append workspace "/")) (file-exists? fs path))
          (match (find-script fs path)
            ((Some script) (check-in-workspace fs script))
            ((None) (None)))
          (None)))

    (define (check-in-workspace (fs Fs) (script Script)) (→ (Option Check))
      (let* ((path (● script file)) (root (● script workspace)) (src (string-append root "/src/")))
        (cond ((has-suffix? path ".scm") (Some (ScriptCheck script (platform-beside fs path))))
              ((and (has-suffix? path ".sld") (has-prefix? path src))
               (Some (LibraryCheck root (split-name (substring path (string-length src)
                                                               (- (string-length path) 4))))))
              (else (None)))))

    (define (platform-beside (fs Fs) (path String)) (→ Platform)
      (if (file-exists? fs (string-append (parent path) "/public")) (Browser) (Node)))

    (define (parent (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 index))
              (else (loop (- index 1))))))

    (define (split-name (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-name (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (define (has-suffix? (text String) (suffix String)) (→ Bool)
      (and (>= (string-length text) (string-length suffix))
           (string=?
            (substring text (- (string-length text) (string-length suffix)) (string-length text))
            suffix)))

    ;; A document's check: what failed, at its places, or the program as
    ;; the checker typed it.

    (define (check-document (processes Processes)
                            (fs Fs)
                            (clock Clock)
                            (tools Tools)
                            (workspace String)
                            (path String))
      (→ (Pair (List Report) (Option Typed)))
      (match (document-check fs workspace path)
        ((None) (new Pair (first (Nil)) (second (None))))
        ((Some check)
         (match (match check
                  ((ScriptCheck script platform)
                   (check-script processes fs clock tools script platform))
                  ((LibraryCheck owner name)
                   (check-library processes fs clock tools owner name)))
           ((Ok typed) (new Pair (first (Nil)) (second (Some typed))))
           ((Err failure) (new Pair (first (failure-reports fs path failure)) (second (None))))))))

    ;; Checks every open document, then publishes what failed and keeps the
    ;; checked programs' names; when every check failed, those of the last
    ;; that did not stay.

    (define (checked
             (processes Processes)
             (fs Fs)
             (clock Clock)
             (out OutputPort)
             (server Server))
      (→ Server)
      (match (● server workspace)
        ((None) server)
        ((Some workspace)
         (let* ((results (map (lambda (document)
                                (check-document processes
                                                fs
                                                clock
                                                (● server tools)
                                                workspace
                                                (● document path)))
                              (● server documents)))
                (programs (fold-right (lambda (result programs)
                                        (match (● result second)
                                          ((Some typed) (Cons typed programs))
                                          ((None) programs)))
                                      (Nil)
                                      results))
                (reports (distinct-reports (concatenate (map (lambda (result) (● result first))
                                                             results)))))
           (Server-reported-set (if (null? programs)
                                    server
                                    (Server-names-set server (index-programs programs)))
                                (publish fs
                                         out
                                         (● server documents)
                                         (● server reported)
                                         reports))))))

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
         (let* ((text (● document text)) (formatted (format-source text format-width)))
           (if (string=? text formatted)
               (JsonArray (Nil))
               (JsonArray
                (list (object (list (field "range"
                                           (range (string->array text) 0 (string-length text)))
                                    (field "newText" (JsonString formatted)))))))))
        ((None) (JsonNull))))

    (define (requested-use (server Server) (params Json)) (→ (Option Use))
      (match (requested server params)
        ((Some document)
         (let ((chars (string->array (● document text))))
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

    (define (definition (fs Fs) (server Server) (params Json)) (→ Json)
      (match (requested-use server params)
        ((Some use)
         (match (table-ref (● (● server names) bindings) (● use name))
           ((Some loc)
            (match (document-text fs (● server documents) (● loc file))
              ((Some text)
               (object (list (field "uri" (JsonString (path->uri (● loc file))))
                             (field "range" (name-range text loc (source-name (● use name)))))))
              ((None) (JsonNull))))
           ((None) (JsonNull))))
        ((None) (JsonNull))))

    ;; A binding's point is the form that binds the name; the editor marks
    ;; the name itself, the first token in the form that is written as it.

    (define (name-range (text String) (loc Loc) (name String)) (→ Json)
      (let* ((chars (string->array text))
             (form (highlight-range text (loc->index chars loc)))
             (written (string->array name)))
        (match (find (lambda (start) (written-at? chars start written))
                     (map (lambda (offset) (+ (● form first) offset))
                          (iota (max 0 (- (● form second) (● form first))))))
          ((Some start) (range chars start (+ start (array-length written))))
          ((None) (range chars (● form first) (● form second))))))

    ;; Whether the token at `start` is `written`, delimited on both sides.

    (define (written-at? (chars (Array Char)) (start I64) (written (Array Char))) (→ Bool)
      (let ((end (+ start (array-length written))))
        (and (<= end (array-length chars))
             (or (= start 0) (delimiter? (array-ref chars (- start 1))))
             (or (= end (array-length chars)) (delimiter? (array-ref chars end)))
             (every? (lambda (offset)
                       (char=? (array-ref chars (+ start offset)) (array-ref written offset)))
                     (iota (array-length written))))))

    ;; ---- Colours ----

    ;; Each token (snail shell highlight) classes, as the protocol's
    ;; semantic tokens: a type from the legend, by its index, and whether the
    ;; token declares the name. Names used, brackets and blanks take the
    ;; editor's plain colour.

    (define legend (→ Json)
      (object (list (field "tokenTypes"
                           (JsonArray (map JsonString
                                           (list "comment" "string" "number" "keyword" "type"
                                                 "function"))))
                    (field "tokenModifiers" (JsonArray (list (JsonString "declaration")))))))

    (define (token-type (class Class)) (→ (Option I64))
      (match class
        ((Comment) (Some 0))
        ((StringLiteral) (Some 1))
        ((CharacterLiteral) (Some 1))
        ((NumberLiteral) (Some 2))
        ((BooleanLiteral) (Some 3))
        ((Keyword) (Some 3))
        ((TypeName) (Some 4))
        ((DefinedName) (Some 5))
        (_ (None))))

    ;; A token's piece on one line, since a client need not take a token
    ;; that spans lines: where it starts, in UTF-16 units, its length, its
    ;; type and modifiers.
    (record Span
      ((line I64)
       (column I64)
       (length I64)
       (type I64)
       (modifiers I64)))

    ;; Where a walk of the text has reached: an index, and the line and
    ;; UTF-16 column it is at.
    (record Cursor
      ((at I64)
       (line I64)
       (column I64)))

    (define (colours (server Server) (params Json)) (→ Json)
      (match (requested server params)
        ((Some document)
         (object
          (list (field "data" (JsonArray (map JsonInteger (encoded (spans (● document text)))))))))
        ((None) (JsonNull))))

    ;; The tokens tile the text, so walking each one's characters in turn
    ;; keeps the cursor at the next one's start; a token with no colour
    ;; moves it and adds no span.

    (define (spans (text String)) (→ (List Span))
      (let ((chars (string->array text)))
        (let loop ((tokens (highlight-tokens text))
                   (cursor (new Cursor (at 0) (line 0) (column 0)))
                   (out (Nil)))
          (match tokens
            ((Nil) (reverse out))
            ((Cons token rest)
             (let ((walked (token-spans chars cursor token)))
               (loop rest (● walked first) (append (reverse (● walked second)) out))))))))

    (define (step (chars (Array Char)) (cursor Cursor)) (→ Cursor)
      (let ((char (array-ref chars (● cursor at))))
        (if (char=? char #\newline)
            (new Cursor (at (+ (● cursor at) 1)) (line (+ (● cursor line) 1)) (column 0))
            (new Cursor (at (+ (● cursor at) 1)) (line (● cursor line))
                 (column (+ (● cursor column) (code-units char)))))))

    ;; The token's pieces, a line each, and the cursor at its end. A
    ;; newline ends a piece and is in none.

    (define (token-spans (chars (Array Char)) (start Cursor) (token Token))
      (→ (Pair Cursor (List Span)))
      (let ((type (token-type (● token class)))
            (modifiers (match (● token class) ((DefinedName) 1) (_ 0))))
        (let loop ((from start) (cursor start) (out (Nil)))
          (let ((piece (lambda () (spanned from cursor type modifiers out))))
            (cond
             ((>= (● cursor at) (● token end)) (new Pair (first cursor) (second (reverse (piece)))))
             ((char=? (array-ref chars (● cursor at)) #\newline)
              (let ((next (step chars cursor))) (loop next next (piece))))
             (else (loop from (step chars cursor) out)))))))

    (define (spanned (from Cursor)
                     (to Cursor)
                     (type (Option I64))
                     (modifiers I64)
                     (out (List Span)))
      (→ (List Span))
      (let ((length (- (● to column) (● from column))))
        (match type
          ((Some type)
           (if (and (= (● to line) (● from line)) (> length 0))
               (Cons (new Span (line (● from line)) (column (● from column)) (length length)
                          (type type) (modifiers modifiers))
                     out)
               out))
          ((None) out))))

    ;; Five numbers a span: its line and column relative to the span before,
    ;; the column only on the same line, then its length, type and modifiers.

    (define (encoded (spans (List Span))) (→ (List I64))
      (let loop ((spans spans) (line 0) (column 0) (out (Nil)))
        (match spans
          ((Nil) (reverse out))
          ((Cons span rest)
           (let ((same (= (● span line) line)))
             (loop rest (● span line) (● span column)
                   (append (reverse (list (- (● span line) line)
                                          (if same (- (● span column) column) (● span column))
                                          (● span length) (● span type) (● span modifiers)))
                           out)))))))))
