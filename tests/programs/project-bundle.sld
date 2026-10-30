(import
 (snail core base)
 (snail core io)
 (snail shell http)
 (snail shell http exchange)
 (snail shell utf8)
 (snail shell project bundle))

;; A browser application's bundle on two builds, mounted at /site/: the
;; page based in the latest, a latest build's file, each build's own files under
;; /.snail/builds/EPOCH/, a build no longer retained, names that are not a
;; build's file, a link out of a build, and nothing built yet. Each line is
;; a request and the response's status, type and body.
(define root "build/tests/project-bundle")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: put (-> String String Unit ! fs))
(define (put name text)
  (write-file (at name) text))

(remove-tree root)
(make-directories (at "g3/modules"))
(make-directories (at "g4/modules"))
(make-directories (at "g4/nested"))
(put "g3/index.html" "<!DOCTYPE html>\n<script src=\"./host.mjs\"></script>\n")
(put "g3/modules.json" "{\"modules\": \"three\"}")
(put "g4/index.html" "<!doctype html>\n<title>four</title>\n")
(put "g4/modules.json" "{\"modules\": \"four\"}")
(put "g4/modules/a.wasm" "four's module")
(put "g4/nested/index.html" "nested")
(put "g4/style.css" "body {}")
(put "outside.txt" "outside")
(make-symbolic-link "../outside.txt" (at "g4/linked.txt"))

(: builds (List BuildDirectory))
(define builds
  (list (BuildDirectory 4 (at "g4")) (BuildDirectory 3 (at "g3"))))

(: show-response (-> String Response Unit ! console))
(define (show-response label response)
  (write-line (string-append label
                             " -> "
                             (show (Response-status response))
                             " "
                             (match (find (lambda (header)
                                            (string=? (Header-name header) "Content-Type"))
                                          (Response-headers response))
                               ((Some header) (Header-value header))
                               ((None) "no type"))
                             ": "
                             (match (utf8->string (Response-body response))
                               ((Ok text) text)
                               ((Err _) "not text")))))

(: request (-> String (List String) Unit ! fs console))
(define (request label path)
  (show-response label (bundle-response "/site/" builds path)))

(request "/" (Nil))
(request "/index.html" (list "index.html"))
(request "/modules.json" (list "modules.json"))
(request "/modules/a.wasm" (list "modules" "a.wasm"))
(request "/STYLE.CSS" (list "STYLE.CSS"))
(request "/style.css" (list "style.css"))
(request "/nested/" (list "nested" ""))
(request "/.snail/builds/3/modules.json" (list ".snail" "builds" "3" "modules.json"))
(request "/.snail/builds/3/" (list ".snail" "builds" "3" ""))
(request "/.snail/builds/4/modules/a.wasm" (list ".snail" "builds" "4" "modules" "a.wasm"))
(request "/.snail/builds/2/modules.json" (list ".snail" "builds" "2" "modules.json"))
(request "/a%2Fb" (list "a/b"))
(request "/modules" (list "modules"))
(request "/linked.txt" (list "linked.txt"))
(show-response "/ before a build" (bundle-response "/site/" (Nil) (Nil)))
(remove-tree root)
