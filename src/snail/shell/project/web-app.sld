;; The default identity is the resolved start_url. A dev server exposes
;; the manifest at the stable application mount, outside build generations.
;; An explicit id would resolve against the origin, not this directory.
;; A project's own public/manifest.webmanifest replaces this default whole.
(define-library (snail shell project web-app)
  (export web-app-manifest with-web-app stable-web-app
          PageMetadata
          PageBase
          PageMeta
          WebManifest
          ModuleMap
          ReloadData
          ModuleScript
          insert-metadata)
  (import
   (snail core base)
   (snail shell json)
   (only (snail shell text) string-downcase))
  (begin

    ;; ---- Manifest ----

    (define (web-app-manifest (name String)) (→ Json)
      (JsonObject
       (append (map (lambda (field) (Pair (::first field) (JsonString (::second field))))
                    (list (Pair "name" name) (Pair "short_name" name)
                          (Pair "start_url" "./") (Pair "scope" "./") (Pair "display" "standalone")
                          (Pair "background_color" "#24282f") (Pair "theme_color" "#24282f")))
               (list (Pair "icons" (JsonArray (map icon (list 192 512))))))))

    (define (icon (size I64)) (→ Json)
      (JsonObject
       (list (Pair "src" (JsonString (string-append "./snail-icon-" (show size) ".png")))
             (Pair "sizes" (JsonString (string-append (show size) "x" (show size))))
             (Pair "type" (JsonString "image/png")))))

    ;; ---- Page metadata ----

    ;; The only markup the packager adds. Callers describe elements; this
    ;; renderer owns quoting and HTML encoding. Reload data uses an attribute,
    ;; so a path containing </script> cannot terminate a raw-text element.
    (enum PageMetadata
      (PageBase ((url String)))
      (PageMeta ((name String)
                 (content String)))
      (WebManifest ((url String)))
      (ModuleMap ((url String)))
      (ReloadData ((text String)))
      (ModuleScript ((url String))))

    (define (attribute-text (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (case char ((#\&) "&amp;") ((#\") "&quot;") ((#\<) "&lt;") ((#\return) "&#13;")
                    (else (make-string 1 char))))
            (string->list text))))

    (define (element-start (name String) (attributes (List (Pair String String)))) (→ String)
      (string-append "<" name
                     (string-concatenate
                      (map (lambda (attribute)
                             (string-append " " (::first attribute) "=\""
                                            (attribute-text (::second attribute)) "\""))
                           attributes))
                     ">"))

    (define (metadata-text (item PageMetadata)) (→ String)
      (match item
        ((PageBase url) (element-start "base" (list (Pair "href" url))))
        ((PageMeta name content)
         (element-start "meta" (list (Pair "name" name) (Pair "content" content))))
        ((WebManifest url) (element-start "link" (list (Pair "id" "snail-web-app")
                                                       (Pair "rel" "manifest") (Pair "href" url))))
        ((ModuleMap url)
         (element-start "meta" (list (Pair "name" "snail-modules") (Pair "content" url))))
        ((ReloadData text)
         (element-start "meta" (list (Pair "id" "snail-manifest") (Pair "content" text))))
        ((ModuleScript url) (string-append (element-start "script" (list (Pair "type" "module")
                                                                         (Pair "src" url)))
                                           "</script>"))))

    (define default-link (→ String) (metadata-text (WebManifest "./manifest.webmanifest")))

    ;; Keep user HTML byte-for-byte around one parsed insertion boundary.
    ;; Existing head attributes stay on their element. Missing heads are
    ;; opened explicitly, and close where the original HTML closes them.
    ;; A doctype/preamble stays before the generated head.

    (define (insert-metadata (text String) (items (List PageMetadata))) (→ String)
      (let* ((head (head-boundary text)) (at (::first head))
             (added (string-concatenate (map metadata-text items))))
        (string-append (substring text 0 at)
                       (if (::second head) added (string-append "<head>" added))
                       (substring text at (string-length text)))))

    (define (with-web-app (text String) (development Bool)) (→ String)
      (insert-metadata text (Cons (WebManifest "./manifest.webmanifest")
                                  (if development (list (ModuleMap "./modules.json")) (Nil)))))

    ;; Only the builder-owned first link is replaced. A pinned executable
    ;; base must never pin the app's installation identity to one generation.

    (define (stable-web-app (text String) (mount String)) (→ String)
      (let ((start (::first (head-boundary text))))
        (if (text-at? text start default-link)
            (string-append (substring text 0 start)
                           (metadata-text
                            (WebManifest (string-append mount "manifest.webmanifest")))
                           (substring text
                                      (+ start (string-length default-link))
                                      (string-length text)))
            text)))

    ;; ---- Document prefix ----

    ;; The offset is after an existing <head>, or where one should be
    ;; inserted. The Bool proves which representation the offset describes.

    (define (head-boundary (text String)) (→ (Pair I64 Bool))
      (let* ((before (preamble-end text (doctype-end text)))
             (html (tag-after text before "html"))
             (at (preamble-end text (match html ((Some end) end) ((None) before)))))
        (match (tag-after text at "head")
          ((Some end) (Pair end #t))
          ((None) (Pair at #f)))))

    (define (tag-after (text String) (at I64) (name String)) (→ (Option I64))
      (let ((end (+ (+ at 1) (string-length name))))
        (if (and (< end (string-length text))
                 (string=? (string-downcase (substring text at end)) (string-append "<" name))
                 (or (char-whitespace? (string-ref text end)) (char=? (string-ref text end) #\>)))
            (Some (declaration-end text end (None)))
            (None))))

    ;; A page may begin with a BOM, whitespace and comments before its
    ;; doctype. Keep that prefix before injected metadata, preserving standards
    ;; mode. A quoted public/system identifier may itself contain `>`.

    (define (doctype-end (text String)) (→ I64)
      (let ((start (preamble-end text 0)))
        (if (and (<= (+ start 9) (string-length text))
                 (string=? (string-downcase (substring text start (+ start 9))) "<!doctype"))
            (declaration-end text (+ start 9) (None))
            start)))

    (define (text-at? (text String) (at I64) (wanted String)) (→ Bool)
      (and (<= (+ at (string-length wanted)) (string-length text))
           (string=? (substring text at (+ at (string-length wanted))) wanted)))

    (define (preamble-end (text String) (at I64)) (→ I64)
      (cond ((>= at (string-length text)) at)
            ((or (char-whitespace? (string-ref text at))
                 (char=? (string-ref text at) (i32->char 65279)))
             (preamble-end text (+ at 1)))
            ((text-at? text at "<!--")
             (match (comment-end text (+ at 4))
               ((Some end) (preamble-end text end))
               ((None) at)))
            (else at)))

    (define (comment-end (text String) (at I64)) (→ (Option I64))
      (cond ((> (+ at 3) (string-length text)) (None))
            ((text-at? text at "-->") (Some (+ at 3)))
            (else (comment-end text (+ at 1)))))

    (define (declaration-end (text String) (at I64) (quote (Option Char))) (→ I64)
      (if (>= at (string-length text)) at
          (let ((char (string-ref text at)))
            (match quote
              ((Some delimiter)
               (declaration-end text (+ at 1) (if (char=? char delimiter) (None) quote)))
              ((None)
               (cond ((char=? char #\>) (+ at 1))
                     ((or (char=? char #\") (char=? char #\'))
                      (declaration-end text (+ at 1) (Some char)))
                     (else (declaration-end text (+ at 1) (None)))))))))))
