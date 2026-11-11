;; A browser application's development bundle, as a server mounts it at a
;; path: the page, the files of the latest build, the files of each
;; build still retained under .snail/builds/EPOCH/, and the objects of the
;; store the builds share, under .snail/builds/.snail-store/, where a
;; manifest's relative reference to it resolves. The page at the mount
;; is the latest build's, given a base in that build's directory, so all it
;; names relatively, its scripts and styles and its modules.json, comes
;; from the build it was served from, even once a newer one is published;
;; loading the page again gives the newest. A build
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
   Reloading
   BundleEvent
   BuildUnderway
   BuildPublished
   BuildFailed
   bundle-response
   bundle-file
   bundle-event)
  (import
   (snail shell project web-app)
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

    (define (bundle-response (mount String)
                             (reloading Reloading)
                             (builds (List BuildDirectory))
                             (path (List String)))
      (→ Response)
      (! fs)
      (match (Pair builds path)
        ((Pair _ (Cons ".snail" (Cons file (Nil)))) (client-file reloading file))
        ((Pair (Nil) _) (refusal 503 "the application has not been built yet"))
        ((Pair (Cons latest _) path)
         (match path
           ((Nil) (page mount latest))
           ((Cons "" (Nil)) (page mount latest))
           ((Cons "index.html" (Nil)) (page mount latest))
           ((Cons ".snail" (Cons "builds" (Cons ".snail-store" rest))) (store-object latest rest))
           ((Cons ".snail" (Cons "builds" (Cons epoch rest))) (pinned builds epoch rest))
           (_ (bundle-file (● latest directory) path))))))

    ;; An object of the store beside the builds' generations, which every
    ;; retained build's manifest names as ../.snail-store/, so its URL never
    ;; changes with the build.

    (define (store-object (build BuildDirectory) (path (List String))) (→ Response) (! fs)
      (match path
        ((Cons "sha256" (Cons digest (Nil)))
         (let ((object (string-append (parent-directory (● build directory))
                                      "/.snail-store/sha256/"
                                      digest)))
           (if (and (plain-name? digest) (regular-file? object))
               (found (string-append "sha256/" digest) (read-bytes object))
               (refusal 404 "no such object in the store"))))
        (_ (refusal 404 "no such object in the store"))))

    (define (parent-directory (path String)) (→ String)
      (let loop ((end (string-length path)))
        (cond ((= end 0) path)
              ((char=? (string-ref path (- end 1)) #\/) (substring path 0 (- end 1)))
              (else (loop (- end 1))))))

    (define (pinned (builds (List BuildDirectory)) (epoch String) (path (List String)))
      (→ Response)
      (! fs)
      (match (find (lambda (build) (string=? (show (● build epoch)) epoch)) builds)
        ((Some build) (bundle-file (● build directory) path))
        ((None) (refusal 404 (string-append "build " epoch " is no longer served")))))

    ;; ---- The page ----

    ;; The latest build's page, based in its build's directory, with its
    ;; manifest and the reload client. A page that is not UTF-8 is served as
    ;; it is.

    (define (page (mount String) (build BuildDirectory)) (→ Response) (! fs)
      (let ((path (string-append (● build directory) "/index.html")))
        (if (regular-file? path)
            (let ((bytes (read-bytes path)))
              (found "index.html"
                     (match (utf8->string bytes)
                       ((Ok text) (string->utf8 (based text mount build)))
                       ((Err _) bytes))))
            (refusal 404 "the application has no index.html"))))

    ;; Typed metadata goes first inside the page's head: a generation base,
    ;; the escaped reload manifest and the reload client. The supplied page
    ;; and its installation identity stay independent of that generation.

    (define (based (raw String) (mount String) (build BuildDirectory)) (→ String) (! fs)
      (insert-metadata (stable-web-app raw mount)
                       (list (PageBase (build-base mount build))
                             (ReloadData (manifest-text mount (Some build)))
                             (ModuleScript (string-append mount ".snail/reload.mjs")))))

    (define (build-base (mount String) (build BuildDirectory)) (→ String)
      (string-append mount ".snail/builds/" (show (● build epoch)) "/"))

    ;; ---- The reload client ----

    ;; reload.mjs and what it imports come from the browser host, beside
    ;; the client's program, so they stay the same across builds.

    (define (client-file (reloading Reloading) (file String)) (→ Response) (! fs)
      (cond ((member? file (list "reload.mjs" "reload-client.mjs" "load.mjs"))
             (bundle-file (● reloading host) (list file)))
            ((and (string=? file "reload.wasm") (regular-file? (● reloading program)))
             (found file (read-bytes (● reloading program))))
            (else (refusal 404 "no such file of the development server"))))

    ;; ---- Manifests and events ----

    ;; What a build serves, as the reload client reads it: the base its
    ;; files are served under, each file with its digest, and each module,
    ;; in program order, with the digest of its bytes. modules.json is left
    ;; out, as the modules stand for it.

    (define (manifest-text (mount String) (found (Option BuildDirectory))) (→ String) (! fs)
      (match found
        ((Some build)
         (string-append (datum->string (datum-list (list (ann (Symbol "base") Any)
                                                         (ann (build-base mount build) Any))))
                        " "
                        (pairs-text "files"
                                    (filter (lambda (file)
                                              (not (string=? (● file first) "modules.json")))
                                            (● build files)))
                        " "
                        (pairs-text "modules" (build-modules build))))
        ((None) "(files) (modules)")))

    (define (pairs-text (head String) (pairs (List (Pair String String)))) (→ String)
      (datum->string
       (datum-list (Cons (ann (Symbol head) Any)
                         (map string-pair-datum pairs)))))

    (define (string-pair-datum (pair (Pair String String))) (→ Any)
      (datum-list (list (ann (● pair first) Any) (ann (● pair second) Any))))

    ;; Each module's library and digest, from the build's modules.json.

    (define (build-modules (build BuildDirectory)) (→ (List (Pair String String))) (! fs)
      (let ((path (string-append (● build directory) "/modules.json")))
        (match (if (regular-file? path) (string->json (read-file path)) (None))
          ((Some manifest)
           (match (json-member manifest "modules")
             ((Some (JsonArray modules))
              (map (lambda (module) (Pair (json-text module "name") (json-text module "digest")))
                   modules))
             (_ (Nil))))
          ((None) (Nil)))))

    (define (json-text (json Json) (name String)) (→ String)
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

    (define (bundle-event (mount String) (event BundleEvent) (build (Option BuildDirectory)))
      (→ String)
      (! fs)
      (let ((manifest (manifest-text mount build)))
        (match event
          ((BuildUnderway) (string-append "(building " manifest ")"))
          ((BuildPublished)
           (string-append "(built "
                          (match build
                            ((Some found) (show (● found milliseconds)))
                            ((None) "0"))
                          " "
                          manifest
                          ")"))
          ((BuildFailed message)
           (string-append "(failed " (datum->string (ann message Any)) " " manifest ")")))))

    ;; ---- Files ----

    ;; A regular file of a build, by the segments of its path under the
    ;; build's directory; a last empty segment names a directory's
    ;; index.html, which is served as it is.

    (define (bundle-file (directory String) (path (List String))) (→ Response) (! fs)
      (match (relative-path path)
        ((Some relative)
         (let ((file (string-append directory "/" relative)))
           (if (regular-file? file)
               (found relative (read-bytes file))
               (refusal 404 "no such file in the build"))))
        ((None) (refusal 404 "no such file in the build"))))

    (define (relative-path (path (List String))) (→ (Option String))
      (let ((names (match (reverse path)
                     ((Cons "" rest) (reverse (Cons "index.html" rest)))
                     (_ path))))
        (if (and (not (null? names)) (every? plain-name? names))
            (Some (string-join names "/"))
            (None))))

    ;; A name a directory can hold: a target's segments are decoded, so one
    ;; may hold a slash or NUL, and `.` and `..` are already resolved.

    (define (plain-name? (name String)) (→ Bool)
      (and (> (string-length name) 0)
           (not (string=? name "."))
           (not (string=? name ".."))
           (every? (lambda (char) (not (or (char=? char #\/) (char=? char #\null))))
                   (string->list name))))

    ;; A generation holds only regular files and directories, so a link is
    ;; never followed out of it.

    (define (regular-file? (path String)) (→ Bool) (! fs)
      (match (file-status path)
        ((Ok status)
         (match (● status kind)
           ((RegularFile) #t)
           (_ #f)))
        ((Err _) #f)))

    ;; ---- Responses ----

    ;; The store's objects are named for their contents, so a browser may
    ;; keep them for good. Nothing else is cached: `/` changes with each
    ;; build.

    (define (found (name String) (bytes Bytes)) (→ Response)
      (response 200
                (content-type name)
                (if (content-named? name) "public, max-age=31536000, immutable" "no-store")
                bytes))

    (define (content-named? (name String)) (→ Bool)
      (match (string-index name #\/)
        ((Some end) (member? (substring name 0 end) (list "store" "sha256")))
        ((None) #f)))

    (define (refusal (status I32) (message String)) (→ Response)
      (response status "text/plain; charset=utf-8" "no-store" (string->utf8 message)))

    (define (response (status I32) (type String) (caching String) (body Bytes)) (→ Response)
      (Response status
                (list (Header "Content-Type" type)
                      (Header "Cache-Control" caching)
                      (Header "X-Content-Type-Options" "nosniff"))
                body))

    (define (content-type (name String)) (→ String)
      (match (find (lambda (type) (ends-with? (string-downcase name) (● type first)))
                   content-types)
        ((Some type) (● type second))
        ((None) "application/octet-stream")))

    (define content-types (→ (List (Pair String String)))
      (list (Pair ".html" "text/html; charset=utf-8")
            (Pair ".mjs" "text/javascript")
            (Pair ".js" "text/javascript")
            (Pair ".css" "text/css")
            (Pair ".wasm" "application/wasm")
            (Pair ".json" "application/json")
            (Pair ".webmanifest" "application/manifest+json")
            (Pair ".svg" "image/svg+xml")
            (Pair ".png" "image/png")
            (Pair ".jpg" "image/jpeg")
            (Pair ".woff2" "font/woff2")
            (Pair ".ico" "image/x-icon")
            (Pair ".txt" "text/plain; charset=utf-8")))

    (define (ends-with? (text String) (suffix String)) (→ Bool)
      (let ((length (string-length text)) (size (string-length suffix)))
        (and (>= length size) (string=? (substring text (- length size) length) suffix))))))
