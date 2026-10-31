;; A browser application's development bundle, as a server mounts it at a
;; path: the page, the files of the latest build, and the files of each
;; build still retained under .snail/builds/EPOCH/. The page at the mount
;; is the latest build's, given a base in that build's directory, so all it
;; names relatively, its scripts and styles, its modules.json and the
;; modules that names, comes from the build it was served from, even once a
;; newer one is published; loading the page again gives the newest. A build
;; that is no longer retained answers 404. The page also carries its
;; build's manifest and the reload client (host/browser/reload.sld), which
;; hears of each build from the server's events and relinks the page from
;; the next build's base. Everything the development server adds lives
;; under .snail/, which a public tree does not use.
;;
;; (snail shell project service) mounts each browser target at /NAME/ on
;; an origin apart from the editor's; an application with a server of its
;; own can mount its bundle at /.
(define-library (snail shell project bundle)
  (export
   BuildDirectory
   BuildDirectory-epoch
   BuildDirectory-directory
   Reloading
   BundleEvent
   BuildUnderway
   BuildPublished
   BuildFailed
   bundle-response
   bundle-event)
  (import
   (snail core base)
   (snail core io)
   (snail shell http)
   (snail shell http exchange)
   (only (snail shell text) string-downcase)
   (snail shell datum)
   (snail shell write)
   (snail shell json)
   (snail shell json read)
   (snail shell utf8))
  (begin

    ;; ---- Builds ----

    ;; A build of the application, by its epoch: the directory of its
    ;; generation, the digests of its files but its modules and linked
    ;; files, by relative name, and how long it took.
    (struct BuildDirectory
      ((epoch I64)
       (directory String)
       (files (List (Pair String String)))
       (milliseconds I64)))

    ;; The reload client's files: the browser host's directory, which holds
    ;; reload.mjs and the modules it imports, and the client's program.
    (struct Reloading
      ((host String)
       (program String)))

    ;; ---- Answering ----

    ;; The response to a GET or HEAD of `path`, the segments of a target
    ;; after the mount, an absolute path ending in a slash, given the builds
    ;; retained, newest first. The server answers .snail/events itself.
    (: bundle-response
       (-> String Reloading (List BuildDirectory) (List String) Response ! fs))
    (define (bundle-response mount reloading builds path)
      (match (Pair builds path)
        ((Pair _ (Cons ".snail" (Cons file (Nil)))) (client-file reloading file))
        ((Pair (Nil) _) (refusal 503 "the application has not been built yet"))
        ((Pair (Cons latest _) path)
         (match path
           ((Nil) (page mount latest))
           ((Cons "" (Nil)) (page mount latest))
           ((Cons "index.html" (Nil)) (page mount latest))
           ((Cons ".snail" (Cons "builds" (Cons epoch rest))) (pinned builds epoch rest))
           (_ (build-file (BuildDirectory-directory latest) path))))))

    (: pinned (-> (List BuildDirectory) String (List String) Response ! fs))
    (define (pinned builds epoch path)
      (match (find (lambda (build) (string=? (show (BuildDirectory-epoch build)) epoch)) builds)
        ((Some build) (build-file (BuildDirectory-directory build) path))
        ((None) (refusal 404 (string-append "build " epoch " is no longer served")))))

    ;; ---- The page ----

    ;; The latest build's page, based in its build's directory, with its
    ;; manifest and the reload client. A page that is not UTF-8 is served as
    ;; it is.
    (: page (-> String BuildDirectory Response ! fs))
    (define (page mount build)
      (let ((path (string-append (BuildDirectory-directory build) "/index.html")))
        (if (regular-file? path)
            (let ((bytes (read-bytes path)))
              (found "index.html"
                     (match (utf8->string bytes)
                       ((Ok text) (string->utf8 (based text mount build)))
                       ((Err _) bytes))))
            (refusal 404 "the application has no index.html"))))

    ;; The page with a base element first, or after the doctype that starts
    ;; it, so the page stays in standards mode, and then the manifest and
    ;; the reload client, which runs whatever the page's own scripts do.
    (: based (-> String String BuildDirectory String ! fs))
    (define (based text mount build)
      (let ((added (string-append "<base href=\""
                                  (build-base mount build)
                                  "\">"
                                  "<script type=\"application/snail-manifest\" id=\"snail-manifest\">"
                                  (manifest-text mount (Some build))
                                  "</script>"
                                  "<script type=\"module\" src=\""
                                  mount
                                  ".snail/reload.mjs\"></script>"))
            (start (doctype-end text)))
        (string-append (substring text 0 start) added (substring text start (string-length text)))))

    (: build-base (-> String BuildDirectory String))
    (define (build-base mount build)
      (string-append mount ".snail/builds/" (show (BuildDirectory-epoch build)) "/"))

    (: doctype-end (-> String I64))
    (define (doctype-end text)
      (if (and (>= (string-length text) 9)
               (string=? (string-downcase (substring text 0 9)) "<!doctype"))
          (match (string-index text #\>)
            ((Some index) (+ index 1))
            ((None) 0))
          0))

    ;; ---- The reload client ----

    ;; reload.mjs and what it imports come from the browser host, beside
    ;; the client's program, so they stay the same across builds.
    (: client-file (-> Reloading String Response ! fs))
    (define (client-file reloading file)
      (cond ((member? file (list "reload.mjs" "reload-client.mjs" "load.mjs"))
             (build-file (Reloading-host reloading) (list file)))
            ((and (string=? file "reload.wasm") (regular-file? (Reloading-program reloading)))
             (found file (read-bytes (Reloading-program reloading))))
            (else (refusal 404 "no such file of the development server"))))

    ;; ---- Manifests and events ----

    ;; What a build serves, as the reload client reads it: the base its
    ;; files are served under, each file with its digest, and each module,
    ;; in program order, with the file it lives in, which names its text.
    ;; modules.json is left out, as the modules stand for it.
    (: manifest-text (-> String (Option BuildDirectory) String ! fs))
    (define (manifest-text mount found)
      (match found
        ((Some build)
         (string-append (datum->string (datum-list (list (SymbolDatum "base")
                                                         (StringDatum (build-base mount build)))))
                        " "
                        (pairs-text "files"
                                    (filter (lambda (file)
                                              (not (string=? (Pair-first file) "modules.json")))
                                            (BuildDirectory-files build)))
                        " "
                        (pairs-text "modules" (build-modules build))))
        ((None) "(files) (modules)")))

    (: pairs-text (-> String (List (Pair String String)) String))
    (define (pairs-text head pairs)
      (datum->string
       (datum-list (Cons (SymbolDatum head)
                         (map (lambda (pair)
                                (datum-list (list (StringDatum (Pair-first pair))
                                                  (StringDatum (Pair-second pair)))))
                              pairs)))))

    ;; Each module's library and file, from the build's modules.json.
    (: build-modules (-> BuildDirectory (List (Pair String String)) ! fs))
    (define (build-modules build)
      (let ((path (string-append (BuildDirectory-directory build) "/modules.json")))
        (match (if (regular-file? path) (string->json (read-file path)) (None))
          ((Some manifest)
           (match (json-member manifest "modules")
             ((Some (JsonArray modules))
              (map (lambda (module) (Pair (json-text module "name") (json-text module "file")))
                   modules))
             (_ (Nil))))
          ((None) (Nil)))))

    (: json-text (-> Json String String))
    (define (json-text json name)
      (match (json-member json name)
        ((Some (JsonString text)) text)
        (_ "")))

    ;; What the server tells a page of a build: that one is under way, that
    ;; one was published, or why one failed. Each names the latest build
    ;; published, none before the first.
    (enum BundleEvent
      (BuildUnderway)
      (BuildPublished)
      (BuildFailed ((message String))))

    (: bundle-event (-> String BundleEvent (Option BuildDirectory) String ! fs))
    (define (bundle-event mount event build)
      (let ((manifest (manifest-text mount build)))
        (match event
          ((BuildUnderway) (string-append "(building " manifest ")"))
          ((BuildPublished)
           (string-append "(built "
                          (match build
                            ((Some found) (show (BuildDirectory-milliseconds found)))
                            ((None) "0"))
                          " "
                          manifest
                          ")"))
          ((BuildFailed message)
           (string-append "(failed " (datum->string (StringDatum message)) " " manifest ")")))))

    ;; ---- Files ----

    ;; A regular file of a build, by the segments of its path under the
    ;; build's directory; a last empty segment names a directory's
    ;; index.html, which is served as it is.
    (: build-file (-> String (List String) Response ! fs))
    (define (build-file directory path)
      (match (relative-path path)
        ((Some relative)
         (let ((file (string-append directory "/" relative)))
           (if (regular-file? file)
               (found relative (read-bytes file))
               (refusal 404 "no such file in the build"))))
        ((None) (refusal 404 "no such file in the build"))))

    (: relative-path (-> (List String) (Option String)))
    (define (relative-path path)
      (let ((names (match (reverse path)
                     ((Cons "" rest) (reverse (Cons "index.html" rest)))
                     (_ path))))
        (if (and (not (null? names)) (every? plain-name? names))
            (Some (string-join names "/"))
            (None))))

    ;; A name a directory can hold: a target's segments are decoded, so one
    ;; may hold a slash or NUL, and `.` and `..` are already resolved.
    (: plain-name? (-> String Bool))
    (define (plain-name? name)
      (and (> (string-length name) 0)
           (not (string=? name "."))
           (not (string=? name ".."))
           (every? (lambda (char) (not (or (char=? char #\/) (char=? char #\null))))
                   (string->list name))))

    ;; A generation holds only regular files and directories, so a link is
    ;; never followed out of it.
    (: regular-file? (-> String Bool ! fs))
    (define (regular-file? path)
      (match (file-status path)
        ((Ok status)
         (match (FileStatus-kind status)
           ((RegularFile) #t)
           (_ #f)))
        ((Err _) #f)))

    ;; ---- Responses ----

    ;; A build's modules and linked files are named for their contents, so
    ;; a browser may keep them for good. Nothing else is cached: `/`
    ;; changes with each build.
    (: found (-> String Bytes Response))
    (define (found name bytes)
      (response 200
                (content-type name)
                (if (content-named? name) "public, max-age=31536000, immutable" "no-store")
                bytes))

    (: content-named? (-> String Bool))
    (define (content-named? name)
      (match (string-index name #\/)
        ((Some end) (member? (substring name 0 end) (list "modules" "resources")))
        ((None) #f)))

    (: refusal (-> I32 String Response))
    (define (refusal status message)
      (response status "text/plain; charset=utf-8" "no-store" (string->utf8 message)))

    (: response (-> I32 String String Bytes Response))
    (define (response status type caching body)
      (Response status
                (list (Header "Content-Type" type)
                      (Header "Cache-Control" caching)
                      (Header "X-Content-Type-Options" "nosniff"))
                body))

    (: content-type (-> String String))
    (define (content-type name)
      (match (find (lambda (type) (ends-with? (string-downcase name) (Pair-first type)))
                   content-types)
        ((Some type) (Pair-second type))
        ((None) "application/octet-stream")))

    (: content-types (List (Pair String String)))
    (define content-types
      (list (Pair ".html" "text/html; charset=utf-8")
            (Pair ".mjs" "text/javascript")
            (Pair ".js" "text/javascript")
            (Pair ".css" "text/css")
            (Pair ".wasm" "application/wasm")
            (Pair ".json" "application/json")
            (Pair ".svg" "image/svg+xml")
            (Pair ".png" "image/png")
            (Pair ".jpg" "image/jpeg")
            (Pair ".woff2" "font/woff2")
            (Pair ".ico" "image/x-icon")
            (Pair ".txt" "text/plain; charset=utf-8")))

    (: ends-with? (-> String String Bool))
    (define (ends-with? text suffix)
      (let ((length (string-length text)) (size (string-length suffix)))
        (and (>= length size) (string=? (substring text (- length size) length) suffix))))))
