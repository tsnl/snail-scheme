;; The development loop: watch an application's or a program's sources,
;; build it again when they change, and tell its open pages, or run it
;; again. A build goes through a compile session (snail-core compiler session), so
;; it recompiles only the libraries an edit changed, each to its own module.
;; A build is planned first (snail-core compiler plan), so the producers of
;; the program's generated libraries run before it.
;; bootstrap/develop.sld exposes its entry points as WebAssembly under Node.
;; The loop does its own file work, through (snail-core io), and the
;; host/native/develop.mjs host performs the `develop` commands, such as
;; watching a directory or serving a page, and reports events. This older
;; application loop remains behind serve/watch while native project
;; development and the editor use host/native/project-develop.mjs.
(define-library (snail-core develop)
  (export
   develop
   develop-character
   develop-event
   start-development!)
  (import
   (snail-core base)
   (snail-core io)
   (snail-core sha256)
   (only (snail-core compiler read) Syntax)
   (only (snail-core compiler core) fnv-1a)
   (only (snail-core compiler inputs) Inputs supply-generated producer-text)
   (snail-core compiler session)
   (snail-core compiler plan))
  (begin

    ;; ---- Host commands ----

    ;; What Snail-Core cannot do alone: watch files, schedule a timer,
    ;; assemble a module, serve pages and run a program. A command is a name
    ;; with string arguments, sent a character at a time, and a number; the
    ;; host answers with a number. Each host names its commands as these
    ;; functions do.
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

    ;; Asks for the timer event after `milliseconds`, replacing any earlier
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

    ;; Runs the producer a modules.json names to write `output`, and waits
    ;; for it: whether it exited successfully. The host adds what it printed
    ;; to the build's diagnostics.
    (: produce-command! (-> String String Bool ! develop))
    (define (produce-command! manifest output)
      (= (host-command "produce" (list manifest output) 0) 0))

    ;; ---- Files ----

    ;; The loop's own file work. A failure it cannot go on from fails the
    ;; build, naming the path and the reason, and the pages keep the build
    ;; they have.
    (: checked (All (T) (-> String String (Result T FileError) T)))
    (define (checked doing path result)
      (match result
        ((Ok value) value)
        ((Err error) (panic (string-append "cannot " doing " " path ": " (show error))))))

    (: make-directories! (-> String Unit ! fs))
    (define (make-directories! directory)
      (checked "make the directory" directory (make-directories directory)))

    ;; Removes a file if one is there.
    (: discard-file! (-> String Unit ! fs))
    (define (discard-file! path)
      (match (remove-file path)
        ((Err (NotFound)) (unit))
        (removed (checked "remove" path removed))))

    ;; The names in a directory, or none if it is missing, as an
    ;; application's public/ may be.
    (: directory-names (-> String (List String) ! fs))
    (define (directory-names directory)
      (match (list-directory directory)
        ((Err (NotFound)) (Nil))
        (listed (checked "list" directory listed))))

    ;; The parent may serve a published path while the compiler works. One
    ;; serial writer owns its neighboring staging file; a failed write or
    ;; rename leaves the preceding complete file visible.
    (: write-published-file! (-> String String Unit ! fs))
    (define (write-published-file! path text)
      (let ((staging (string-append path ".next")))
        (write-file staging text)
        (checked "publish" path (rename-file staging path))))

    ;; Copies a file's bytes, making the directory it goes to, and renames
    ;; the copy over what was there, so a page reading `to` sees all of one
    ;; file or of the other.
    (: place-file! (-> String String Unit ! fs))
    (define (place-file! from to)
      (let ((staging (string-append to ".next")))
        (make-directories! (directory-name to))
        (write-bytes staging (read-bytes from))
        (checked "place" to (rename-file staging to))))

    ;; A digest of the bytes a read of `path` gives, which changes when they
    ;; do: their SHA-256, or "none" for what no read gives, as for a
    ;; directory in public/. place-file! and the server read through
    ;; symbolic links, so the digest follows them too, and an edit to the
    ;; file a link names changes it. Every path digested was just listed or
    ;; checked, so one that is not there is a link to nothing, which fails
    ;; the build, naming the link.
    (: digest (-> String String ! fs))
    (define (digest path)
      (match (FileStatus-kind (checked "read" path (followed-status path)))
        ((RegularFile) (bytes->hex (sha256 (read-bytes path))))
        (_ "none")))

    ;; Milliseconds since `started`, a reading of the monotonic clock.
    (: milliseconds-since (-> I64 String ! clock))
    (define (milliseconds-since started)
      (i64->string (quotient (- (monotonic-nanoseconds) started) 1000000)))

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
        ((Cons "watch" (Cons source rest))
         (Watch source (take-while-not "--" rest) (after "--" rest)))
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
    ;; latest build's, which a failed build leaves in place, and `previous`
    ;; names the module files of the build before it.
    (struct Loop
      ((root String)
       (runtime String)
       (client String)
       (request Request)
       (session (Ref Session))
       (output String)
       (manifest (Ref String))
       (previous (Ref (List String)))))

    ;; `arguments` are the root, the runtime, the reload client and the
    ;; request.
    (: new-loop (-> (List String) Loop ! mut))
    (define (new-loop arguments)
      (match arguments
        ((Cons root (Cons runtime (Cons client words)))
         (let ((request (parse-request words)))
           (Loop root
                 runtime
                 client
                 request
                 (ref (new-session root request))
                 (output root request)
                 (ref "(files) (modules)")
                 (ref (Nil)))))
        (_ (panic "usage: develop ROOT RUNTIME CLIENT REQUEST ..."))))

    ;; Pages are served before the first build, from a placeholder that
    ;; waits for it, so a first build that fails is shown like any other.
    (: start-loop! (-> Loop Unit ! mut fs develop))
    (define (start-loop! loop)
      (make-directories! (string-append (Loop-output loop) "/modules"))
      (make-directories! (producers-directory loop))
      (match (Loop-request loop)
        ((Serve port app) (serve-pages! loop port app))
        ((Watch _ _ _) (unit)))
      (for-each watch! (watched (Loop-root loop) (Loop-request loop)))
      ;; The native host installs every watch before returning this timer
      ;; event to its compiler worker. No startup handshake is needed.
      (schedule! 0))

    (: new-session (-> String Request Session))
    (define (new-session root request)
      (make-session (match request
                      ((Serve _ app) (list (string-append app "/src") (string-append root "/src")))
                      ((Watch _ directories _)
                       (append directories (list (string-append root "/src")))))))

    (: output (-> String Request String))
    (define (output root request)
      (match request
        ((Serve _ app) (string-append root "/build/serve/" (base-name app)))
        ((Watch _ _ _) (string-append root "/build/watch"))))

    (: watched (-> String Request (List String)))
    (define (watched root request)
      (match request
        ((Serve _ app) (list app (string-append root "/src") (host-directory root)))
        ((Watch source directories _)
         (Cons (directory-name source) (append directories (list (string-append root "/src")))))))

    (: main-source (-> Request String))
    (define (main-source request)
      (match request
        ((Serve _ app) (string-append app "/main.sld"))
        ((Watch source _ _) source)))

    (: serving? (-> Request Bool))
    (define (serving? request)
      (match request
        ((Serve _ _) #t)
        ((Watch _ _ _) #f)))

    ;; The browser host's files, which pages load beside their own.
    (: host-directory (-> String String))
    (define (host-directory root)
      (string-append root "/host/browser"))

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
      (or (starts-with? path (string-append root "/build/")) (contains-segment? path ".git")
          (temporary? (base-name path))))

    ;; An editor's temporary file: a lock, an autosave or a swap file, a
    ;; backup, or the numbered file Vim writes to test a directory. An
    ;; Emacs lock is a symbolic link to nothing.
    (: temporary? (-> String Bool))
    (define (temporary? name)
      (or (starts-with? name ".")
          (starts-with? name "#")
          (ends-with? name "~")
          (all-digits? name)))

    ;; A build that panics, with the compiler's message, which the host
    ;; caught; the pages keep the build they have.
    (: build-failed! (-> Loop String Unit ! mut develop))
    (define (build-failed! loop message)
      (broadcast!
       (string-append "(failed " (quoted message) " " (ref-get (Loop-manifest loop)) ")")))

    ;; The host's events, by number, as both hosts send them: 1 is a changed
    ;; file, with its path; 2 the timer the loop asked for; 3 a build that
    ;; panicked, with the panic's message.
    (: deliver-event! (-> Loop I32 String Unit ! mut fs console clock develop))
    (define (deliver-event! loop kind text)
      (case kind
        ((1) (source-changed! loop text))
        ((2) (build! loop))
        ((3) (build-failed! loop text))
        (else (panic (string-append "the development loop has no event " (i32->string kind))))))

    ;; ---- Builds ----

    ;; A build digests the pages' files, places the files the program
    ;; links, writes its modules and modules.json, then shows the pages the
    ;; new build or runs the program again, and only then removes the module
    ;; files no page can still be loading. A build that fails to compile or
    ;; assemble, or finds a link to nothing, stops before modules.json, the
    ;; page or any module a page may still load changes.
    (: build! (-> Loop Unit ! mut fs console clock develop))
    (define (build! loop)
      (let ((started (monotonic-nanoseconds)))
        (broadcast! (string-append "(building " (ref-get (Loop-manifest loop)) ")"))
        (let* ((builds (next-build! loop (main-source (Loop-request loop))))
               (files (page-files loop))
               (modules (write-modules! loop builds)))
          (match (Loop-request loop)
            ((Serve _ app)
             (publish-pages! loop app files modules started)
             (report-built! app builds started))
            ((Watch _ _ arguments) (run! (manifest-path loop) arguments)))
          (remove-old-modules! loop
                               (map (lambda (module) (base-name (Pair-second module))) modules)))))

    ;; Builds through the loop's session, which the build replaces with the
    ;; session the next build starts from, once the plan has run the
    ;; producers the program reaches. The loop declares no project targets,
    ;; so the plan's one build is the program's own, its last phase.
    (: next-build! (-> Loop String (List Built) ! mut fs develop))
    (define (next-build! loop source)
      (let* ((session (ref-get (Loop-session loop)))
             (program
              (Target "main" (serving? (Loop-request loop)) source (Session-directories session)))
             (inputs (produced! loop
                                (plan-build (Nil)
                                            (list program)
                                            no-inputs
                                            (producers-directory loop))
                                no-inputs)))
        (match (build-session session source unplanned-producer inputs)
          ((Pair builds next) (ref-set! (Loop-session loop) next) builds))))

    ;; Runs the producers of each wave, refining the plan with what they
    ;; wrote, until no phase is left, and returns the inputs that hold it.
    (: produced! (-> Loop Plan Inputs Inputs ! mut fs develop))
    (define (produced! loop plan inputs)
      (let* ((wave (next-phases plan))
             (inputs (fold-left (lambda (inputs entry)
                                  (match (Pair-second entry)
                                    ((ProducePhase producer) (produce! loop producer inputs))
                                    (_ inputs)))
                                inputs (Pair-first wave))))
        (if (phases-left? (Pair-second wave))
            (produced! loop (refine-plan (Pair-second wave) inputs) inputs)
            inputs)))

    ;; Every compile runs after the plan has run each producer it reaches.
    (: unplanned-producer (-> (List String) (List Syntax) Bytes))
    (define (unplanned-producer loading forms)
      (panic "internal error: the build plan did not run this producer"))

    ;; Places the files the program links, then writes each module that
    ;; changed, assembled, and modules.json, which names them in program
    ;; order. Returns each library's name with its module's location.
    (: write-modules! (-> Loop (List Built) (List (Pair String String)) ! fs develop))
    (define (write-modules! loop builds)
      (place-links! (Loop-output loop) builds)
      (let ((modules
             (map (lambda (built) (Pair (Built-name built) (module-file! loop built))) builds)))
        (write-published-file! (manifest-path loop) (modules-json (runtime-path loop) modules))
        modules))

    (: manifest-path (-> Loop String))
    (define (manifest-path loop)
      (string-append (Loop-output loop) "/modules.json"))

    ;; A module's file is named for what it loads, so a page fetches it
    ;; again only when that changed.
    (: module-file! (-> Loop Built String ! fs develop))
    (define (module-file! loop built)
      (module-url loop
                  (string-append "modules/"
                                 (assembled-module! (string-append (Loop-output loop) "/modules")
                                                    built))))

    ;; The name of a library's module file in `directory`, which is
    ;; assembled there unless it already is. It is named for the module's
    ;; text and the contents of the files the library links, so the page
    ;; relinks from the module when either changed, and relinking a module
    ;; reads its files again.
    (: assembled-module! (-> String Built String ! fs develop))
    (define (assembled-module! directory built)
      (let* ((stamp (string-concatenate
                     (map (lambda (link) (string-append "\n" (digest (LinkedFile-path link))))
                          (Built-links built))))
             (file (string-append (Built-name built)
                                  "-"
                                  (i64->string (fnv-1a (string-append (Built-text built) stamp)))
                                  ".wasm"))
             (path (string-append directory "/" file)))
        (unless (file-exists? path)
          (write-file (string-append path ".wat") (Built-text built))
          (unless (assemble! (string-append path ".wat") path)
            (panic (string-append "could not assemble the module of " (Built-name built)))))
        file))

    ;; Pages fetch from the server's root; a program reads files.
    (: module-url (-> Loop String String))
    (define (module-url loop file)
      (if (serving? (Loop-request loop))
          (string-append "/" file)
          (string-append (Loop-output loop) "/" file)))

    (: runtime-path (-> Loop String))
    (define (runtime-path loop)
      (if (serving? (Loop-request loop)) "/.snail/runtime.wasm" (Loop-runtime loop)))

    ;; Since module files are named for their text, earlier builds' files
    ;; pile up. Once a build is written and announced, the files of its
    ;; modules and of the build before it stay, the latter for a page still
    ;; relinking from it, and everything else under modules/ goes, including
    ;; the text each module was assembled from.
    (: remove-old-modules! (-> Loop (List String) Unit ! mut fs))
    (define (remove-old-modules! loop current)
      (let ((directory (string-append (Loop-output loop) "/modules"))
            (kept (append current (ref-get (Loop-previous loop)))))
        (for-each (lambda (name)
                    (unless (member? name kept) (discard-file! (string-append directory "/" name))))
                  (directory-names directory))
        (ref-set! (Loop-previous loop) current)))

    ;; ---- Producers ----

    ;; Where producers are printed, compiled to modules, run from a
    ;; manifest, and write their libraries. A module is named for its text,
    ;; as the program's are, so an unchanged library is not assembled again.
    (: producers-directory (-> Loop String))
    (define (producers-directory loop)
      (string-append (Loop-output loop) "/producers"))

    ;; A producer is compiled one library at a time, as the program is, and
    ;; run by the host. What it writes is an input of every compile after.
    (: produce! (-> Loop Producer Inputs Inputs ! mut fs develop))
    (define (produce! loop producer inputs)
      (let ((manifest (producer-manifest! loop producer inputs))
            (output
             (string-append (producers-directory loop) "/" (Producer-key producer) ".syntax"))
            (name
             (string-append "the producer of (" (string-join (Producer-library producer) " ") ")")))
        (discard-file! output)
        (cond ((not (produce-command! manifest output)) (panic (string-append name " failed")))
              ((not (file-exists? output))
               (panic (string-append name " did not write its generated library")))
              (else (supply-generated inputs
                                      (producer-text (Producer-directories producer)
                                                     (Producer-forms producer))
                                      (read-bytes output))))))

    ;; Compiles the producer afresh from the source the plan printed, and
    ;; writes the manifest it runs from.
    (: producer-manifest! (-> Loop Producer Inputs String ! mut fs develop))
    (define (producer-manifest! loop producer inputs)
      (let* ((directory (producers-directory loop))
             (built (build-session (make-session (Producer-directories producer))
                                   (Producer-source producer)
                                   unplanned-producer
                                   inputs))
             (manifest (string-append directory "/" (Producer-key producer) ".json")))
        (place-links! directory (Pair-first built))
        (write-file manifest (modules-json (Loop-runtime loop)
                                           (map (lambda (module)
                                                  (Pair (Built-name module)
                                                        (string-append directory
                                                                       "/"
                                                                       (assembled-module! directory
                                                                                          module))))
                                                (Pair-first built))))
        manifest))

    ;; ---- Linked files ----

    ;; Each file the program links goes to resources/NAME in `directory`,
    ;; beside the manifest it runs from, where pages and programs read it
    ;; before they start. Editing a linked file recompiles nothing, so every
    ;; build places them, copying a file only when it changed.
    (: place-links! (-> String (List Built) Unit ! fs))
    (define (place-links! directory builds)
      (for-each (lambda (link) (place-link! directory link))
                (concatenate (map Built-links builds))))

    (: place-link! (-> String LinkedFile Unit ! fs))
    (define (place-link! directory link)
      (let ((from (LinkedFile-path link))
            (to (string-append directory "/resources/" (LinkedFile-name link))))
        (unless (and (file-exists? to) (string=? (digest to) (digest from)))
          (place-file! from to))))

    ;; ---- Pages ----

    ;; Writes the page for the new build and tells every open page about it.
    (: publish-pages!
       (-> Loop String (List (Pair String String)) (List (Pair String String)) I64 Unit
           ! mut fs clock develop))
    (define (publish-pages! loop app files modules started)
      (let ((manifest (page-manifest files modules)))
        (write-published-file! (string-append (Loop-output loop) "/index.html")
                               (string-append (app-page app) (page-client manifest)))
        (ref-set! (Loop-manifest loop) manifest)
        (broadcast! (string-append "(built " (milliseconds-since started) " " manifest ")"))))

    (: report-built! (-> String (List Built) I64 Unit ! console clock))
    (define (report-built! app builds started)
      (write-line
       (string-append "built " (base-name app) " in " (milliseconds-since started) " ms: "
                      (i64->string (length (filter Built-compiled? builds)))
                      " of "
                      (i64->string (length builds))
                      " modules compiled")))

    ;; What a page runs, which its reload client compares with each event's
    ;; to learn what changed: every file it loads with a digest, and the
    ;; modules in program order.
    (: page-manifest (-> (List (Pair String String)) (List (Pair String String)) String))
    (define (page-manifest files modules)
      (string-append "(files"
                     (quoted-pairs files)
                     ") (modules"
                     (quoted-pairs modules)
                     ")"))

    (: quoted-pairs (-> (List (Pair String String)) String))
    (define (quoted-pairs pairs)
      (string-concatenate (map (lambda (pair)
                                 (string-append " ("
                                                (quoted (Pair-first pair))
                                                " "
                                                (quoted (Pair-second pair))
                                                ")"))
                               pairs)))

    ;; Each page file's name and digest: the page itself, every file of the
    ;; browser host, and the application's public files. A program has no
    ;; pages.
    (: page-files (-> Loop (List (Pair String String)) ! fs))
    (define (page-files loop)
      (match (Loop-request loop)
        ((Serve _ app)
         (Cons (Pair "index.html" (i64->string (fnv-1a (app-page app))))
               (append (file-digests (host-directory (Loop-root loop)))
                       (filter (lambda (file) (not (string=? (Pair-first file) "index.html")))
                               (file-digests (string-append app "/public"))))))
        ((Watch _ _ _) (Nil))))

    ;; Editors' temporary files are left out: no page loads one, and
    ;; digesting an Emacs lock would fail the build.
    (: file-digests (-> String (List (Pair String String)) ! fs))
    (define (file-digests directory)
      (map (lambda (name) (Pair name (digest (string-append directory "/" name))))
           (filter (lambda (name) (not (temporary? name))) (directory-names directory))))

    ;; The application's page, or an empty one for a project without it,
    ;; as the IDE may open.
    (: app-page (-> String String ! fs))
    (define (app-page app)
      (let ((path (string-append app "/public/index.html")))
        (if (file-exists? path) (read-file path) "<!doctype html>\n<meta charset=\"utf-8\">\n")))

    ;; The manifest the page was built from, and the reload client that
    ;; reads it.
    (: page-client (-> String String))
    (define (page-client manifest)
      (string-append "<script type=\"application/snail-manifest\" id=\"snail-manifest\">"
                     manifest
                     "</script>"
                     "<meta name=\"snail-modules\" content=\"/modules.json\">"
                     "<script type=\"module\" src=\"/.snail/reload.mjs\"></script>\n"))

    ;; Starts serving the placeholder page and the routes.
    (: serve-pages! (-> Loop I32 String Unit ! mut fs develop))
    (define (serve-pages! loop port app)
      (let ((routes (string-append (Loop-output loop) "/routes.json")))
        (write-published-file! (string-append (Loop-output loop) "/index.html")
                               (string-append
                                "<!doctype html>\n<meta charset=\"utf-8\">\n<title>Building</title>\n"
                                (page-client (ref-get (Loop-manifest loop)))))
        (write-file routes (routes-json loop app))
        (serve! routes (base-name app) port)))

    ;; A request is served from the first route with the file: its exact
    ;; path, then each directory whose prefix the path starts with, in
    ;; order. The page, the modules, the linked files and the runtime come
    ;; from the build; any file of the browser host comes from its
    ;; directory, at the root for the application's page and under /.snail/
    ;; for the reload client; and the application's public files come from
    ;; its public/.
    (: routes-json (-> Loop String String))
    (define (routes-json loop app)
      (let ((output (Loop-output loop))
            (host (string-append (host-directory (Loop-root loop)) "/")))
        (string-append
         "{\"files\": "
         (json-pairs (list (Pair "/" (string-append output "/index.html"))
                           (Pair "/index.html" (string-append output "/index.html"))
                           (Pair "/modules.json" (manifest-path loop))
                           (Pair "/.snail/runtime.wasm" (Loop-runtime loop))
                           (Pair "/.snail/reload.wasm" (Loop-client loop))))
         ", \"directories\": "
         (json-pairs (list (Pair "/modules/" (string-append output "/modules/"))
                           (Pair "/resources/" (string-append output "/resources/"))
                           (Pair "/.snail/" host)
                           (Pair "/" host)
                           (Pair "/" (string-append app "/public/"))))
         ", \"types\": " content-types ", \"events\": \"/.snail/events\"}\n")))

    (: content-types String)
    (define content-types
      "{\".html\": \"text/html; charset=utf-8\", \".mjs\": \"text/javascript\", \".js\": \"text/javascript\", \".css\": \"text/css\", \".wasm\": \"application/wasm\", \".json\": \"application/json\", \".svg\": \"image/svg+xml\", \".png\": \"image/png\", \".jpg\": \"image/jpeg\", \".woff2\": \"font/woff2\", \".ico\": \"image/x-icon\", \".txt\": \"text/plain; charset=utf-8\"}")

    ;; ---- Entry points ----

    ;; A program that runs the loop exposes `develop-character` as
    ;; "develop_character" and `develop-event` as "develop_event", then
    ;; calls `start-development!`:
    ;;
    ;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
    ;;   develop ROOT RUNTIME CLIENT watch SOURCE DIRECTORY ... -- ARGUMENT ...
    ;;
    ;; The host sends an event's text, a path or a panic's message, a
    ;; character at a time, then the event's number (deliver-event!).
    (: current (Ref (Option Loop)))
    (define current (ref (None)))

    (: input (Ref (List Char)))
    (define input (ref (Nil)))

    (: develop-character (-> I32 Unit ! mut))
    (define (develop-character code)
      (ref-set! input (Cons (i32->char code) (ref-get input))))

    (: develop-event (-> I32 Unit ! mut fs console clock develop))
    (define (develop-event kind)
      (let ((text (list->string (reverse (ref-get input)))))
        (ref-set! input (Nil))
        (match (ref-get current)
          ((Some loop) (deliver-event! loop kind text))
          ((None) (unit)))))

    ;; The loop is kept before it starts, so a first build that panics
    ;; leaves it ready for the next event.
    (: start-development! (-> Unit ! mut fs develop))
    (define (start-development!)
      (match (command-line)
        ((Cons _ arguments)
         (let ((loop (new-loop arguments)))
           (ref-set! current (Some loop))
           (start-loop! loop)))
        ((Nil) (panic "usage: develop ROOT RUNTIME CLIENT REQUEST ..."))))

    ;; ---- Text ----

    (: modules-json (-> String (List (Pair String String)) String))
    (define (modules-json runtime modules)
      (string-append "{\"runtime\": " (quoted runtime) ", \"modules\": ["
                     (string-join (map (lambda (entry)
                                         (string-append "{\"name\": "
                                                        (quoted (Pair-first entry))
                                                        ", \"file\": "
                                                        (quoted (Pair-second entry))
                                                        "}"))
                                       modules)
                                  ", ")
                     "]}\n"))

    ;; Pairs of strings as a JSON array of two-element arrays.
    (: json-pairs (-> (List (Pair String String)) String))
    (define (json-pairs pairs)
      (string-append "["
                     (string-join (map (lambda (pair)
                                         (string-append "["
                                                        (quoted (Pair-first pair))
                                                        ", "
                                                        (quoted (Pair-second pair))
                                                        "]"))
                                       pairs)
                                  ", ")
                     "]"))

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

    (: base-name (-> String String))
    (define (base-name path)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) path)
              ((char=? (string-ref path index) #\/)
               (substring path (+ index 1) (string-length path)))
              (else (loop (- index 1))))))

    (: directory-name (-> String String))
    (define (directory-name path)
      (substring path 0 (max 0 (- (string-length path) (+ (string-length (base-name path)) 1)))))

    (: starts-with? (-> String String Bool))
    (define (starts-with? text prefix)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (: ends-with? (-> String String Bool))
    (define (ends-with? text suffix)
      (and (>= (string-length text) (string-length suffix))
           (string=?
            (substring text (- (string-length text) (string-length suffix)) (string-length text))
            suffix)))

    (: contains-segment? (-> String String Bool))
    (define (contains-segment? path segment)
      (any? (lambda (part) (string=? part segment)) (split-path path)))

    (: split-path (-> String (List String)))
    (define (split-path path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (: all-digits? (-> String Bool))
    (define (all-digits? name)
      (and (> (string-length name) 0) (every? char-numeric? (string->list name))))

    (: i32->string (-> I32 String))
    (define (i32->string number)
      (i64->string (i32->i64 number)))

    ))
