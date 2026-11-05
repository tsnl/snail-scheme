;; The default identity is the resolved start_url. A dev server exposes
;; the manifest at the stable application mount, outside build generations.
;; An explicit id would resolve against the origin, not this directory.
;; A project's own public/manifest.webmanifest replaces this default whole.
(define-library (snail shell project web-app)
  (export web-app-manifest with-web-app stable-web-app doctype-end)
  (import
   (snail core base)
   (snail shell json)
   (only (snail shell text) string-downcase))
  (begin

    ;; ---- Manifest ----

    (: web-app-manifest (-> String Json))
    (define (web-app-manifest name)
      (JsonObject
       (append (map (lambda (field) (Pair (Pair-first field) (JsonString (Pair-second field))))
                    (list (Pair "name" name) (Pair "short_name" name)
                          (Pair "start_url" "./") (Pair "scope" "./") (Pair "display" "standalone")
                          (Pair "background_color" "#24282f") (Pair "theme_color" "#24282f")))
               (list (Pair "icons" (JsonArray (map icon (list 192 512))))))))

    (: icon (-> I64 Json))
    (define (icon size)
      (JsonObject
       (list (Pair "src" (JsonString (string-append "./snail-icon-" (show size) ".png")))
             (Pair "sizes" (JsonString (string-append (show size) "x" (show size))))
             (Pair "type" (JsonString "image/png")))))

    ;; ---- The page's link ----

    (: default-link String)
    (define default-link (manifest-link "./manifest.webmanifest"))

    (: manifest-link (-> String String))
    (define (manifest-link url)
      (string-append "<link id=\"snail-web-app\" rel=\"manifest\" href=\""
                     (attribute-text url)
                     "\">"))

    (: attribute-text (-> String String))
    (define (attribute-text text)
      (string-concatenate
       (map (lambda (char)
              (case char ((#\&) "&amp;") ((#\") "&quot;") ((#\<) "&lt;")
                    (else (make-string 1 char))))
            (string->list text))))

    ;; The builder adds exactly this marker. Development replaces only
    ;; that owned link, so <base> can pin scripts without pinning app identity.
    (: with-web-app (-> String String))
    (define (with-web-app text)
      (let ((start (doctype-end text)))
        (string-append (substring text 0 start)
                       default-link
                       (substring text start (string-length text)))))

    (: stable-web-app (-> String String String))
    (define (stable-web-app text mount)
      (let ((start (doctype-end text)))
        (if (text-at? text start default-link)
            (string-append (substring text 0 start)
                           (manifest-link (string-append mount "manifest.webmanifest"))
                           (substring text
                                      (+ start (string-length default-link))
                                      (string-length text)))
            text)))

    ;; A page may begin with a BOM, whitespace and comments before its
    ;; doctype. Keep that prefix before injected metadata, preserving standards
    ;; mode. A quoted public/system identifier may itself contain `>`.
    (: doctype-end (-> String I64))
    (define (doctype-end text)
      (let ((start (preamble-end text 0)))
        (if (and (<= (+ start 9) (string-length text))
                 (string=? (string-downcase (substring text start (+ start 9))) "<!doctype"))
            (declaration-end text (+ start 9) (None))
            start)))

    (: text-at? (-> String I64 String Bool))
    (define (text-at? text at wanted)
      (and (<= (+ at (string-length wanted)) (string-length text))
           (string=? (substring text at (+ at (string-length wanted))) wanted)))

    (: preamble-end (-> String I64 I64))
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

    (: comment-end (-> String I64 (Option I64)))
    (define (comment-end text at)
      (cond ((> (+ at 3) (string-length text)) (None))
            ((text-at? text at "-->") (Some (+ at 3)))
            (else (comment-end text (+ at 1)))))

    (: declaration-end (-> String I64 (Option Char) I64))
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
