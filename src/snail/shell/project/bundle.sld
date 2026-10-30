;; A browser application's development bundle, as a server mounts it at a
;; path: the page, the files of the latest build, and the files of each
;; build still retained under .snail/builds/EPOCH/. The page at the mount
;; is the latest build's, given a base in that build's directory, so all it
;; names relatively, its scripts and styles, its modules.json and the
;; modules that names, comes from the build it was served from, even once a
;; newer one is published; loading the page again gives the newest. A build
;; that is no longer retained answers 404. Everything the development
;; server adds lives under .snail/, which a public tree does not use.
;;
;; (snail shell project service) mounts each browser target at /NAME/ on
;; an origin apart from the editor's; an application with a server of its
;; own can mount its bundle at /.
(define-library (snail shell project bundle)
  (export
   BuildDirectory
   BuildDirectory-epoch
   BuildDirectory-directory
   bundle-response)
  (import
   (snail core base)
   (snail core io)
   (snail shell http)
   (snail shell http exchange)
   (only (snail shell text) string-downcase)
   (snail shell utf8))
  (begin

    ;; ---- Builds ----

    ;; A build of the application, by its epoch, and the directory of its
    ;; generation.
    (struct BuildDirectory
      ((epoch I64)
       (directory String)))

    ;; ---- Answering ----

    ;; The response to a GET or HEAD of `path`, the segments of a target
    ;; after the mount, an absolute path ending in a slash, given the builds
    ;; retained, newest first.
    (: bundle-response (-> String (List BuildDirectory) (List String) Response ! fs))
    (define (bundle-response mount builds path)
      (match builds
        ((Nil) (refusal 503 "the application has not been built yet"))
        ((Cons latest _)
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

    ;; The latest build's page, based in its build's directory. A page that
    ;; is not UTF-8 is served as it is.
    (: page (-> String BuildDirectory Response ! fs))
    (define (page mount build)
      (let ((path (string-append (BuildDirectory-directory build) "/index.html")))
        (if (regular-file? path)
            (let ((bytes (read-bytes path)))
              (found "index.html"
                     (match (utf8->string bytes)
                       ((Ok text) (string->utf8 (based text mount (BuildDirectory-epoch build))))
                       ((Err _) bytes))))
            (refusal 404 "the application has no index.html"))))

    ;; The page with a base element first, or after the doctype that starts
    ;; it, so the page stays in standards mode.
    (: based (-> String String I64 String))
    (define (based text mount epoch)
      (let ((base (string-append "<base href=\"" mount ".snail/builds/" (show epoch) "/\">"))
            (start (doctype-end text)))
        (string-append (substring text 0 start) base (substring text start (string-length text)))))

    (: doctype-end (-> String I64))
    (define (doctype-end text)
      (if (and (>= (string-length text) 9)
               (string=? (string-downcase (substring text 0 9)) "<!doctype"))
          (match (string-index text #\>)
            ((Some index) (+ index 1))
            ((None) 0))
          0))

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

    (: found (-> String Bytes Response))
    (define (found name bytes)
      (response 200 (content-type name) bytes))

    (: refusal (-> I32 String Response))
    (define (refusal status message)
      (response status "text/plain; charset=utf-8" (string->utf8 message)))

    ;; Nothing is cached: `/` changes with each build, and a build's files
    ;; are few enough to fetch again.
    (: response (-> I32 String Bytes Response))
    (define (response status type body)
      (Response status
                (list (Header "Content-Type" type)
                      (Header "Cache-Control" "no-store")
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
