;; The client page, built when this library is: its producer builds
;; client/main.scm for the browser, and the library links every file of
;; that build.
(generate-library (embedded client)
                  (import
                   (snail core base)
                   (snail shell project build)
                   (embedded linking))
                  (files-library (list "embedded" "client")
                                 "client-files"
                                 (build-script (producer-tools)
                                               (script-at "client/main.scm")
                                               (Browser)
                                               (Debug))))
