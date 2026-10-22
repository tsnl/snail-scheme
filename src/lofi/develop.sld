;; The development loop: watch an application's or a program's sources,
;; build it again when they change, and tell its open pages, or run it
;; again. A build goes through a compile session (lofi compiler session), so
;; it recompiles only the libraries an edit changed, each to its own module.
;; The loop runs as WebAssembly (bootstrap/develop.sld, or src/ide/develop.sld
;; in the IDE) and decides everything; its host (scripts/develop.mjs, or
;; src/ide/toolchain.mjs) performs the commands of the `develop` effect, such
;; as watching a directory or serving a page, and reports what happened as
;; events.
(define-library (lofi develop)
  (export
   develop
   Loop
   new-loop
   start-loop!
   deliver-event!)
  (import
   (lofi base)
   (lofi io)
   (only (lofi compiler core) fnv-1a)
   (lofi compiler session))
  (begin

    ;; ---- Host commands ----

    ;; What Lofi cannot do alone: watch files, keep time, assemble a module,
    ;; serve pages and run a program. A command is a name with string
    ;; arguments, sent a character at a time, and a number; the host answers
    ;; with a number. Each host names its commands as these functions do.
    (effect develop
      ((argument-character (-> Char Unit))
       (argument-end (-> Unit))
       (command (-> I32 I32)))
      (host "snail.develop"
            ((argument-character "argument-character")
             (argument-end "argument-end")
             (command "command"))))

    (: host-command (-> String (List String) I32 I32 ! develop))
    (define (host-command name arguments number)
      (for-each send-argument (Cons name arguments))
      (command number))

    (: send-argument (-> String Unit ! develop))
    (define (send-argument text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character (string-ref text index))
          (loop (+ index 1))))
      (argument-end))

    (: watch! (-> String Unit ! develop))
    (define (watch! directory)
      (host-command "watch" (list directory) 0)
      (unit))

    ;; Asks for `timer-fired!` after `milliseconds`, replacing any earlier
    ;; request.
    (: schedule! (-> I32 Unit ! develop))
    (define (schedule! milliseconds)
      (host-command "schedule" (Nil) milliseconds)
      (unit))

    (: assemble! (-> String String Bool ! develop))
    (define (assemble! text-path module-path)
      (= (host-command "assemble" (list text-path module-path) 0) 0))

    ;; Serves the routes the file names, on `port`, or any free port for 0;
    ;; the host announces where, under `name`.
    (: serve! (-> String String I32 Unit ! develop))
    (define (serve! routes name port)
      (host-command "serve" (list routes name) port)
      (unit))

    ;; Sends an event to every open page; a page that connects later gets the
    ;; latest.
    (: broadcast! (-> String Unit ! develop))
    (define (broadcast! event)
      (host-command "broadcast" (list event) 0)
      (unit))

    ;; Runs the program a modules.json names, once the run before it has
    ;; stopped.
    (: run! (-> String (List String) Unit ! develop))
    (define (run! manifest arguments)
      (host-command "run" (Cons manifest arguments) 0)
      (unit))

    ;; A digest of a file's bytes, which change when the file does.
    (: digest (-> String I32 ! develop))
    (define (digest path)
      (host-command "digest" (list path) 0))

    (: now (-> I32 ! develop))
    (define (now)
      (host-command "now" (Nil) 0))

    ;; Writes the names of a directory's files, one to a line, to `output`.
    (: list-directory! (-> String String Unit ! develop))
    (define (list-directory! directory output)
      (host-command "list-directory" (list directory output) 0)
      (unit))

    ;; Creates a directory and any missing parents.
    (: make-directory! (-> String Unit ! develop))
    (define (make-directory! directory)
      (host-command "make-directory" (list directory) 0)
      (unit))

    ;; ---- Requests ----

    ;; `serve PORT APP-DIRECTORY` serves an application; `watch SOURCE
    ;; DIRECTORY ... -- ARGUMENT ...` runs a program, finding its libraries
    ;; in the directories.
    (enum Request
      (Serve ((port I32) (app String)))
      (Watch ((source String) (directories (List String)) (arguments (List String)))))

    (: parse-request (-> (List String) Request))
    (define (parse-request words)
      (match words
        ((Cons "serve" (Cons port (Cons app (Nil))))
         (match (string->i64 port)
           ((Some number) (Serve (i64->i32 number) app))
           ((None) (panic "usage: serve PORT APP-DIRECTORY"))))
        ((Cons "watch" (Cons source rest)) (Watch source (take-while-not "--" rest) (after "--" rest)))
        (_ (panic "usage: serve PORT APP-DIRECTORY | watch SOURCE DIRECTORY ... -- ARGUMENT ..."))))

    (: take-while-not (-> String (List String) (List String)))
    (define (take-while-not stop words)
      (match words
        ((Cons word rest) (if (string=? word stop) (Nil) (Cons word (take-while-not stop rest))))
        ((Nil) (Nil))))

    (: after (-> String (List String) (List String)))
    (define (after stop words)
      (match words
        ((Cons word rest) (if (string=? word stop) rest (after stop rest)))
        ((Nil) (Nil))))

    ;; ---- The loop ----

    ;; `root` is the repository's; `runtime` and `client` are the runtime
    ;; and the reload client the host built for pages. `manifest` is the
    ;; latest build's, which a failed build leaves in place.
    (struct Loop
      ((root String)
       (runtime String)
       (client String)
       (request Request)
       (session (Ref Session))
       (output String)
       (manifest (Ref String))))

    ;; `arguments` are the root, the runtime, the reload client and the
    ;; request.
    (: new-loop (-> (List String) Loop ! mut))
    (define (new-loop arguments)
      (match arguments
        ((Cons root (Cons runtime (Cons client words)))
         (let ((request (parse-request words)))
           (Loop root runtime client request (ref (new-session root request)) (output root request) (ref "(files) (modules)"))))
        (_ (panic "usage: develop ROOT RUNTIME CLIENT REQUEST ..."))))

    ;; Pages are served before the first build, from a placeholder that
    ;; waits for it, so a first build that fails is shown like any other.
    (: start-loop! (-> Loop Unit ! mut fs console develop))
    (define (start-loop! loop)
      (make-directory! (string-append (Loop-output loop) "/modules"))
      (when (serving? (Loop-request loop)) (serve-pages! loop))
      (for-each watch! (watched (Loop-root loop) (Loop-request loop)))
      (build! loop))

    (: new-session (-> String Request Session ! mut))
    (define (new-session root request)
      (make-session (match request
                      ((Serve _ app) (list (string-append app "/src") (string-append root "/lib")))
                      ((Watch _ directories _) (append directories (list (string-append root "/lib")))))
                    (lambda (forms) (panic "lofi serve and lofi watch cannot build a generate-library yet"))))

    (: output (-> String Request String))
    (define (output root request)
      (match request
        ((Serve _ app) (string-append root "/build/serve/" (base-name app)))
        ((Watch _ _ _) (string-append root "/build/watch"))))

    (: watched (-> String Request (List String)))
    (define (watched root request)
      (match request
        ((Serve _ app) (list app (string-append root "/lib") (string-append root "/src/app")))
        ((Watch source directories _) (Cons (directory-name source) (append directories (list (string-append root "/lib")))))))

    (: serving? (-> Request Bool))
    (define (serving? request)
      (match request
        ((Serve _ _) #t)
        ((Watch _ _ _) #f)))

    ;; ---- Events ----

    ;; Editors save in steps, through temporary files, renames and backups,
    ;; so a build starts once changes have been quiet for 100 milliseconds.
    ;; Their temporary files never start one, and neither does anything under
    ;; build/, where builds write.
    (: source-changed! (-> Loop String Unit ! develop))
    (define (source-changed! loop path)
      (unless (ignored? (Loop-root loop) path)
        (schedule! 100)))

    (: ignored? (-> String String Bool))
    (define (ignored? root path)
      (let ((name (base-name path)))
        (or (starts-with? path (string-append root "/build/")) (contains-segment? path ".git")
            (starts-with? name ".") (starts-with? name "#") (ends-with? name "~") (all-digits? name))))

    (: timer-fired! (-> Loop Unit ! mut fs console develop))
    (define (timer-fired! loop)
      (build! loop))

    ;; A build that panics, with the compiler's message, which the host
    ;; caught; the pages keep the build they have.
    (: build-failed! (-> Loop String Unit ! mut develop))
    (define (build-failed! loop message)
      (broadcast! (string-append "(failed " (quoted message) " " (ref-get (Loop-manifest loop)) ")")))

    ;; The host's events, numbered as its hosts number them: 1 is a changed
    ;; file, with its path; 2 the timer the loop asked for; 3 a build that
    ;; panicked, with the panic's message.
    (: deliver-event! (-> Loop I32 String Unit ! mut fs console develop))
    (define (deliver-event! loop kind text)
      (case kind
        ((1) (source-changed! loop text))
        ((2) (timer-fired! loop))
        (else (build-failed! loop text))))

    ;; ---- Builds ----

    (: build! (-> Loop Unit ! mut fs console develop))
    (define (build! loop)
      (let ((started (now)))
        (broadcast! (string-append "(building " (ref-get (Loop-manifest loop)) ")"))
        (match (Loop-request loop)
          ((Serve _ app) (build-pages! loop app started))
          ((Watch source _ arguments) (run! (write-modules! loop (next-build! loop source)) arguments)))))

    ;; Builds through the loop's session, which the build replaces with the
    ;; session the next build starts from.
    (: next-build! (-> Loop String (List Built) ! mut fs))
    (define (next-build! loop source)
      (match (build-session (ref-get (Loop-session loop)) source)
        ((Pair builds session) (ref-set! (Loop-session loop) session) builds)))

    ;; Writes each module that changed, assembled, and modules.json, which
    ;; names them in program order. A module's file is named for its text,
    ;; so a page fetches it again only when it changed.
    (: write-modules! (-> Loop (List Built) String ! mut fs develop))
    (define (write-modules! loop builds)
      (let ((files (map (lambda (built) (Pair (Built-name built) (module-file! loop built))) builds))
            (manifest (string-append (Loop-output loop) "/modules.json")))
        (write-file manifest (modules-json (runtime-path loop) files))
        manifest))

    (: module-file! (-> Loop Built String ! fs develop))
    (define (module-file! loop built)
      (let* ((file (string-append "modules/" (Built-name built) "-" (i64->string (fnv-1a (Built-text built))) ".wasm"))
             (path (string-append (Loop-output loop) "/" file)))
        (unless (file-exists? path)
          (write-file (string-append path ".wat") (Built-text built))
          (unless (assemble! (string-append path ".wat") path)
            (panic (string-append "could not assemble the module of " (Built-name built)))))
        (module-url loop file)))

    ;; Pages fetch from the server's root; a program reads files.
    (: module-url (-> Loop String String))
    (define (module-url loop file)
      (if (serving? (Loop-request loop)) (string-append "/" file) (string-append (Loop-output loop) "/" file)))

    (: runtime-path (-> Loop String))
    (define (runtime-path loop)
      (if (serving? (Loop-request loop)) "/.lofi/runtime.wasm" (Loop-runtime loop)))

    ;; ---- Pages ----

    (: build-pages! (-> Loop String I32 Unit ! mut fs console develop))
    (define (build-pages! loop app started)
      (let* ((builds (next-build! loop (string-append app "/main.sld")))
             (modules (map (lambda (built) (Pair (Built-name built) (module-file! loop built))) builds)))
        (write-file (string-append (Loop-output loop) "/modules.json") (modules-json (runtime-path loop) modules))
        (let ((manifest (page-manifest loop app modules)))
          (write-file (string-append (Loop-output loop) "/index.html")
                      (string-append (app-page app) (page-client manifest)))
          (ref-set! (Loop-manifest loop) manifest)
          (broadcast! (string-append "(built " (i32->string (- (now) started)) " " manifest ")"))
          (write-line (string-append "built " (base-name app) " in " (i32->string (- (now) started)) " ms: "
                                     (i64->string (length (filter Built-compiled? builds))) " of " (i64->string (length builds))
                                     " modules compiled")))))

    ;; What a page runs, which its reload client compares with each event's
    ;; to learn what changed: every file it loads with a digest, and the
    ;; modules in program order.
    (: page-manifest (-> Loop String (List (Pair String String)) String ! fs develop))
    (define (page-manifest loop app modules)
      (string-append "(files" (string-concatenate (map (lambda (entry) (string-append " (" (quoted (Pair-first entry)) " " (quoted (Pair-second entry)) ")"))
                                                       (page-files loop app)))
                     ") (modules" (string-concatenate (map (lambda (entry) (string-append " (" (quoted (Pair-first entry)) " " (quoted (Pair-second entry)) ")"))
                                                           modules))
                     ")"))

    ;; Each page file's name and digest: the page itself, the browser host's
    ;; files, and the application's public files.
    (: page-files (-> Loop String (List (Pair String String)) ! fs develop))
    (define (page-files loop app)
      (concatenate
       (list (list (Pair "index.html" (i64->string (fnv-1a (app-page app)))))
             (map (lambda (file) (Pair file (i32->string (digest (string-append (Loop-root loop) "/src/app/" file))))) host-files)
             (map (lambda (file) (Pair file (i32->string (digest (string-append app "/public/" file))))) (public-files loop app)))))

    ;; The application's page, or an empty one for a project without it,
    ;; as the IDE may open.
    (: app-page (-> String String ! fs))
    (define (app-page app)
      (let ((path (string-append app "/index.html")))
        (if (file-exists? path) (read-file path) "<!doctype html>\n<meta charset=\"utf-8\">\n")))

    (: host-files (List String))
    (define host-files
      (list "host.mjs" "renderer.mjs" "hud.mjs" "pictures.mjs" "storage.mjs" "load.mjs" "style.css"))

    (: public-files (-> Loop String (List String) ! fs develop))
    (define (public-files loop app)
      (let ((listing (string-append (Loop-output loop) "/public-files")))
        (list-directory! (string-append app "/public") listing)
        (filter (lambda (line) (not (string=? line ""))) (lines (read-file listing)))))

    ;; The manifest the page was built from, and the reload client that
    ;; reads it.
    (: page-client (-> String String))
    (define (page-client manifest)
      (string-append "<script type=\"application/lofi-manifest\" id=\"lofi-manifest\">" manifest "</script>"
                     "<meta name=\"lofi-modules\" content=\"/modules.json\">"
                     "<script type=\"module\" src=\"/.lofi/reload.mjs\"></script>\n"))

    ;; Starts serving the routes: the page with its client, the host's
    ;; files, the modules, the runtime and the reload client, and the
    ;; application's public files under the root.
    (: serve-pages! (-> Loop Unit ! mut fs develop))
    (define (serve-pages! loop)
      (match (Loop-request loop)
        ((Serve port app)
         (let ((routes (string-append (Loop-output loop) "/routes.json")))
           (write-file (string-append (Loop-output loop) "/index.html")
                       (string-append "<!doctype html>\n<meta charset=\"utf-8\">\n<title>Building</title>\n" (page-client (ref-get (Loop-manifest loop)))))
           (write-file routes (routes-json loop app))
           (serve! routes (base-name app) port)))
        ((Watch _ _ _) (unit))))

    (: routes-json (-> Loop String String))
    (define (routes-json loop app)
      (let ((output (Loop-output loop)) (host (string-append (Loop-root loop) "/src/app/")))
        (string-append
         "{\"files\": {"
         (string-join (map (lambda (route) (string-append (json-string (Pair-first route)) ": " (json-string (Pair-second route))))
                           (append (list (Pair "/" (string-append output "/index.html")) (Pair "/index.html" (string-append output "/index.html"))
                                         (Pair "/modules.json" (string-append output "/modules.json")) (Pair "/.lofi/runtime.wasm" (Loop-runtime loop))
                                         (Pair "/.lofi/reload.wasm" (Loop-client loop)) (Pair "/.lofi/reload.mjs" (string-append host "reload.mjs"))
                                         (Pair "/.lofi/reload-client.mjs" (string-append host "reload-client.mjs"))
                                         (Pair "/.lofi/load.mjs" (string-append host "load.mjs")))
                                   (map (lambda (file) (Pair (string-append "/" file) (string-append host file))) host-files)))
                      ", ")
         "}, \"directories\": {\"/modules/\": " (json-string (string-append output "/modules/")) ", \"/\": " (json-string (string-append app "/public/"))
         "}, \"types\": " content-types ", \"events\": \"/.lofi/events\"}\n")))

    (: content-types String)
    (define content-types
      "{\".html\": \"text/html; charset=utf-8\", \".mjs\": \"text/javascript\", \".js\": \"text/javascript\", \".css\": \"text/css\", \".wasm\": \"application/wasm\", \".json\": \"application/json\", \".svg\": \"image/svg+xml\", \".png\": \"image/png\", \".jpg\": \"image/jpeg\", \".woff2\": \"font/woff2\", \".ico\": \"image/x-icon\", \".txt\": \"text/plain; charset=utf-8\"}")

    ;; ---- Text ----

    (: modules-json (-> String (List (Pair String String)) String))
    (define (modules-json runtime modules)
      (string-append "{\"runtime\": " (json-string runtime) ", \"modules\": ["
                     (string-join (map (lambda (entry) (string-append "{\"name\": " (json-string (Pair-first entry)) ", \"file\": " (json-string (Pair-second entry)) "}"))
                                       modules)
                                  ", ")
                     "]}\n"))

    (: json-string (-> String String))
    (define (json-string text)
      (quoted text))

    ;; A string literal, as both Scheme and JSON read it.
    (: quoted (-> String String))
    (define (quoted text)
      (string-append "\"" (string-concatenate (map escape-char (string->list text))) "\""))

    (: escape-char (-> Char String))
    (define (escape-char c)
      (cond ((char=? c #\") "\\\"")
            ((char=? c #\\) "\\\\")
            ((char=? c #\newline) "\\n")
            (else (list->string (list c)))))

    (: lines (-> String (List String)))
    (define (lines text)
      (match (string-index text #\newline)
        ((Some index) (Cons (substring text 0 index) (lines (substring text (+ index 1) (string-length text)))))
        ((None) (list text))))

    (: base-name (-> String String))
    (define (base-name path)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) path)
              ((char=? (string-ref path index) #\/) (substring path (+ index 1) (string-length path)))
              (else (loop (- index 1))))))

    (: directory-name (-> String String))
    (define (directory-name path)
      (substring path 0 (max 0 (- (string-length path) (+ (string-length (base-name path)) 1)))))

    (: starts-with? (-> String String Bool))
    (define (starts-with? text prefix)
      (and (>= (string-length text) (string-length prefix)) (string=? (substring text 0 (string-length prefix)) prefix)))

    (: ends-with? (-> String String Bool))
    (define (ends-with? text suffix)
      (and (>= (string-length text) (string-length suffix))
           (string=? (substring text (- (string-length text) (string-length suffix)) (string-length text)) suffix)))

    (: contains-segment? (-> String String Bool))
    (define (contains-segment? path segment)
      (any? (lambda (part) (string=? part segment)) (split-path path)))

    (: split-path (-> String (List String)))
    (define (split-path path)
      (match (string-index path #\/)
        ((Some index) (Cons (substring path 0 index) (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (: all-digits? (-> String Bool))
    (define (all-digits? name)
      (and (> (string-length name) 0) (every? char-numeric? (string->list name))))

    (: i32->string (-> I32 String))
    (define (i32->string number)
      (i64->string (i32->i64 number)))

    ))
