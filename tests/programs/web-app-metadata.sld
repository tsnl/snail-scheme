(import
 (snail core base)
 (snail core io)
 (snail shell project web-app))

(define (check (out OutputPort) (name String) (actual String) (expected String)) (→ Unit) (! mut)
  (unless (string=? actual expected) (panic (string-append name ": " actual)))
  (write-line out name))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (check out "implicit head"
         (with-web-app "<!doctype html><title>App</title>" "app.manifest.datum")
         "<!doctype html><head><link id=\"snail-web-app\" rel=\"manifest\" href=\"./manifest.webmanifest\"><meta name=\"snail-modules\" content=\"./app.manifest.datum\"><title>App</title>")
  (check out "existing head and attributes"
         (with-web-app
          "<!DOCTYPE html><html lang=\"en\"><HEAD data-x=\">\"><title>App</title></HEAD></html>"
          "app.manifest.datum")
         "<!DOCTYPE html><html lang=\"en\"><HEAD data-x=\">\"><link id=\"snail-web-app\" rel=\"manifest\" href=\"./manifest.webmanifest\"><meta name=\"snail-modules\" content=\"./app.manifest.datum\"><title>App</title></HEAD></html>")
  (check out "quoted doctype and comments"
         (insert-metadata
          "<!-- before --><!DOCTYPE html SYSTEM \"a>b\">\n<!-- after --><head></head>"
          (list (WebManifest "./manifest.webmanifest")))
         "<!-- before --><!DOCTYPE html SYSTEM \"a>b\">\n<!-- after --><head><link id=\"snail-web-app\" rel=\"manifest\" href=\"./manifest.webmanifest\"></head>")
  (check out "metadata is escaped attribute data"
         (insert-metadata "<head data-kept=\"yes\"><base href=\"original\"></head>"
                          (list (ModuleMap "\"😀 </script> & other\"")))
         "<head data-kept=\"yes\"><meta name=\"snail-modules\" content=\"&quot;😀 &lt;/script> &amp; other&quot;\"><base href=\"original\"></head>")
  (let ((bom (make-string 1 (i32->char 65279))))
    (check out "BOM retained"
           (insert-metadata (string-append bom "\n<!doctype html><body>body</body>")
                            (list (ModuleMap "/")))
           (string-append bom
                          "\n<!doctype html><head><meta name=\"snail-modules\" content=\"/\"><body>body</body>")))
  (check out "carriage returns survive HTML parsing"
         (insert-metadata "<head></head>" (list (ModuleMap (make-string 1 #\return))))
         "<head><meta name=\"snail-modules\" content=\"&#13;\"></head>")
  (check out "implicit head contents stay in the head"
         (insert-metadata
          "<!doctype html><noscript><meta name=\"x\" content=\"a\"></noscript><title>Test</title>"
          (list (ModuleMap "/")))
         "<!doctype html><head><meta name=\"snail-modules\" content=\"/\"><noscript><meta name=\"x\" content=\"a\"></noscript><title>Test</title>")
  (unit))
