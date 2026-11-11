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

    (: web-app-manifest (impl (Fn String -> Json)))
    (define (web-app-manifest name)
      (JsonObject
       (append (map (lambda (field) (Pair (::first field) (JsonString (::second field))))
                    (list (Pair "name" name) (Pair "short_name" name)
                          (Pair "start_url" "./") (Pair "scope" "./") (Pair "display" "standalone")
                          (Pair "background_color" "#24282f") (Pair "theme_color" "#24282f")))
               (list (Pair "icons" (JsonArray (map icon (list 192 512))))))))

    (: icon (impl (Fn I64 -> Json)))
    (define (icon size)
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

    (: attribute-text (impl (Fn String -> String)))
    (define (attribute-text text)
      (string-concatenate
       (map (lambda (char)
              (case char ((#\&) "&amp;") ((#\") "&quot;") ((#\<) "&lt;") ((#\return) "&#13;")
                    (else (make-string 1 char))))
            (string->list text))))

    (: element-start (impl (Fn String (List (Pair String String)) -> String)))
    (define (element-start name attributes)
      (string-append "<" name
                     (string-concatenate
                      (map (lambda (attribute)
                             (string-append " " (::first attribute) "=\""
                                            (attribute-text (::second attribute)) "\""))
                           attributes))
                     ">"))

    (: metadata-text (impl (Fn PageMetadata -> String)))
    (define (metadata-text item)
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

    (: default-link String)
    (define default-link (metadata-text (WebManifest "./manifest.webmanifest")))

    ;; Keep user HTML byte-for-byte around one parsed insertion boundary.
    ;; Existing head attributes stay on their element. Missing heads are
    ;; opened explicitly, and close where the original HTML closes them.
    ;; A doctype/preamble stays before the generated head.
    (: insert-metadata (impl (Fn String (List PageMetadata) -> String)))
    (define (insert-metadata text items)
      (let* ((head (head-boundary text)) (at (::first head))
             (added (string-concatenate (map metadata-text items))))
        (string-append (substring text 0 at)
                       (if (::second head) added (string-append "<head>" added))
                       (substring text at (string-length text)))))

    (: with-web-app (impl (Fn String Bool -> String)))
    (define (with-web-app text development)
      (insert-metadata text (Cons (WebManifest "./manifest.webmanifest")
                                  (if development (list (ModuleMap "./modules.json")) (Nil)))))

    ;; Only the builder-owned first link is replaced. A pinned executable
    ;; base must never pin the app's installation identity to one generation.
    (: stable-web-app (impl (Fn String String -> String)))
    (define (stable-web-app text mount)
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
    (: head-boundary (impl (Fn String -> (Pair I64 Bool))))
    (define (head-boundary text)
      (let* ((before (preamble-end text (doctype-end text)))
             (html (tag-after text before "html"))
             (at (preamble-end text (match html ((Some end) end) ((None) before)))))
        (match (tag-after text at "head")
          ((Some end) (Pair end #t))
          ((None) (Pair at #f)))))

    (: tag-after (impl (Fn String I64 String -> (Option I64))))
    (define (tag-after text at name)
      (let ((end (+ (+ at 1) (string-length name))))
        (if (and (< end (string-length text))
                 (string=? (string-downcase (substring text at end)) (string-append "<" name))
                 (or (char-whitespace? (string-ref text end)) (char=? (string-ref text end) #\>)))
            (Some (declaration-end text end (None)))
            (None))))

    ;; A page may begin with a BOM, whitespace and comments before its
    ;; doctype. Keep that prefix before injected metadata, preserving standards
    ;; mode. A quoted public/system identifier may itself contain `>`.
    (: doctype-end (impl (Fn String -> I64)))
    (define (doctype-end text)
      (let ((start (preamble-end text 0)))
        (if (and (<= (+ start 9) (string-length text))
                 (string=? (string-downcase (substring text start (+ start 9))) "<!doctype"))
            (declaration-end text (+ start 9) (None))
            start)))

    (: text-at? (impl (Fn String I64 String -> Bool)))
    (define (text-at? text at wanted)
      (and (<= (+ at (string-length wanted)) (string-length text))
           (string=? (substring text at (+ at (string-length wanted))) wanted)))

    (: preamble-end (impl (Fn String I64 -> I64)))
    (define (preamble-end text at)
      (cond ((>= at (string-length text)) at)
            ((or (char-whitespace? (string-ref text at))
                 (char=? (string-ref text at) (i32->char 65279)))
             (preamble-end text (+ at 1)))
            ((text-at? text at "<!--")
             (match (comment-end text (+ at 4))
               ((Some end) (preamble-end text end))
               ((None) at)))
            (else at)))

    (: comment-end (impl (Fn String I64 -> (Option I64))))
    (define (comment-end text at)
      (cond ((> (+ at 3) (string-length text)) (None))
            ((text-at? text at "-->") (Some (+ at 3)))
            (else (comment-end text (+ at 1)))))

    (: declaration-end (impl (Fn String I64 (Option Char) -> I64)))
    (define (declaration-end text at quote)
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
