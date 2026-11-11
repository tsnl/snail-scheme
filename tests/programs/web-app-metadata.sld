(import
 (snail core base)
 (snail core io)
 (snail shell project web-app))

(: check (impl (Fn String String String -> Unit ! console)))
(define (check name actual expected)
  (unless (string=? actual expected) (panic (string-append name ": " actual)))
  (write-line name))

(check "implicit head"
       (with-web-app "<!doctype html><title>App</title>" #f)
       "<!doctype html><head><link id=\"snail-web-app\" rel=\"manifest\" href=\"./manifest.webmanifest\"><title>App</title>")

(check "existing head and attributes"
       (with-web-app
        "<!DOCTYPE html><html lang=\"en\"><HEAD data-x=\">\"><title>App</title></HEAD></html>"
        #t)
       "<!DOCTYPE html><html lang=\"en\"><HEAD data-x=\">\"><link id=\"snail-web-app\" rel=\"manifest\" href=\"./manifest.webmanifest\"><meta name=\"snail-modules\" content=\"./modules.json\"><title>App</title></HEAD></html>")

(check "quoted doctype, comments and stable identity"
       (stable-web-app
        (with-web-app "<!-- before --><!DOCTYPE html SYSTEM \"a>b\">\n<!-- after --><head></head>"
                      #f)
        "/one/")
       "<!-- before --><!DOCTYPE html SYSTEM \"a>b\">\n<!-- after --><head><link id=\"snail-web-app\" rel=\"manifest\" href=\"/one/manifest.webmanifest\"></head>")

(check "metadata is escaped attribute data"
       (insert-metadata "<head data-kept=\"yes\"><base href=\"original\"></head>"
                        (list (PageBase "/one/.snail/builds/2/")
                              (ReloadData "(file \"😀 </script> & other\")")
                              (ModuleScript "/one/.snail/reload.mjs")))
       "<head data-kept=\"yes\"><base href=\"/one/.snail/builds/2/\"><meta id=\"snail-manifest\" content=\"(file &quot;😀 &lt;/script> &amp; other&quot;)\"><script type=\"module\" src=\"/one/.snail/reload.mjs\"></script><base href=\"original\"></head>")

(let ((bom (make-string 1 (i32->char 65279))))
  (check "BOM retained"
         (insert-metadata (string-append bom "\n<!doctype html><body>body</body>")
                          (list (PageBase "/")))
         (string-append bom "\n<!doctype html><head><base href=\"/\"><body>body</body>")))

(check "carriage returns survive HTML parsing"
       (insert-metadata "<head></head>" (list (ReloadData (make-string 1 #\return))))
       "<head><meta id=\"snail-manifest\" content=\"&#13;\"></head>")

(check "implicit head contents stay in the head"
       (insert-metadata
        "<!doctype html><noscript><meta name=\"x\" content=\"a\"></noscript><title>Test</title>"
        (list (PageBase "/")))
       "<!doctype html><head><base href=\"/\"><noscript><meta name=\"x\" content=\"a\"></noscript><title>Test</title>")
