;; Script builds publish complete generations: a page's public folder and
;; host, a web-app manifest, and a failed build that changes nothing.
;;
;;   ./snail-scheme run --target node tests/contracts/script-builds.scm ROOT
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (snail shell json)
 (snail shell json read)
 (contracts support))

(define source
  (→ String)
  (string-append "(import (snail core base) (snail core io) (greeting))\n"
                 "(define (main (out OutputPort)) (→ Unit) (display out (greeting)))\n"))

(record Project
  ((c Context)
   (root String)))

(define (in (p Project) (name String)) (→ String)
  (string-append (● p root) "/" name))

(define (public (p Project) (name String)) (→ String)
  (in p (string-append "page/public/" name)))

(define (build (p Project) (target String) (file String)) (→ Ran)
  (snail (● p c) (list "build" "--target" target file) (● p root)))

(define (page (p Project)) (→ Ran)
  (build p "browser" "page/main.scm"))

(define (page-output (p Project)) (→ String)
  (resolved (● p c) (in p "build/page/main")))

;; The chosen build mode reaches imported libraries.
(define (modes (p Project)) (→ Unit)
  (put! (● p c) (in p "mode.scm")
        (string-append "(import (snail core base) (snail core io) (snail shell build-mode))\n"
                       "(define (main (out OutputPort)) (→ Unit) (write-line out (show debug-build?)))"))
  (for-each (lambda (mode)
              (let ((ran (snail (● p c)
                                (append (Cons "run" (● mode first))
                                        (list "--target" "node" "mode.scm"))
                                (● p root))))
                (expect-text (first-line (● ran stdout)) (● mode second)
                             "the chosen build mode reaches imported libraries")))
            (list (new Pair (first (Nil)) (second "#t"))
                  (new Pair (first (list "--release")) (second "#f")))))

(define (lay-out! (p Project)) (→ Unit)
  (let ((c (● p c)))
    (put! c (in p "src/greeting.sld")
          (string-append "(define-library (greeting) (export greeting) (import (snail core base)) "
                         "(begin (define (greeting) (→ String) \"hello project\")))"))
    (for-each (lambda (file) (put! c (in p file) source))
              (list "cli.scm" "page/main.scm" "occupied.scm"))
    (put! c (public p "index.html") "<!doctype html><title>Project</title>")
    (make-directories (● c fs) (public p "nested"))
    (write-bytes (● c fs) (public p "nested/data.bin") #u8(0 255 127))
    (put! c (public p "obsolete.txt") "first generation")))

(define (scripts (p Project)) (→ Unit)
  (let ((c (● p c)))
    (expect-text (first-line (● (succeeded (build p "node" "cli.scm") "cli build") stdout))
                 (in p "build/cli")
                 "building does not run the program")
    (expect-text (● (node c (list (string-append (● c root) "/host/native/run-snail.mjs")
                                  (in p "build/cli/cli.wasm"))
                          (● p root))
                    stdout)
                 "hello project" "the workspace src/ reaches the compiler")))

(define (first-page (p Project)) (→ String)
  (let ((c (● p c)))
    (succeeded (page p) "page build")
    (let ((first (page-output p)))
      (expect-text (text-of c (string-append first "/index.html"))
                   (string-append
                    "<!doctype html><head><link id=\"snail-web-app\" rel=\"manifest\" "
                    "href=\"./manifest.webmanifest\"><meta name=\"snail-modules\" "
                    "content=\"./main.wasm\"><title>Project</title>")
                   "a page is told its manifest and its module")
      (let ((manifest
             (match (string->json (text-of c (string-append first "/manifest.webmanifest")))
               ((Some json) json)
               ((None) (panic "the manifest is not JSON")))))
        (expect (not (some? (member-of manifest "id"))) "the default manifest has no id")
        (expect (string-member? manifest "start_url" "./") "it starts at the page")
        (expect (string-member? manifest "scope" "./") "and covers it")
        (expect (string-member? manifest "display" "standalone") "and stands alone"))
      (for-each (lambda (size)
                  (let ((png (read-bytes (● c fs)
                                         (string-append first "/snail-icon-" (show size) ".png"))))
                    (expect (and (= (big-endian png 16) size) (= (big-endian png 20) size))
                            (string-append "the icon is " (show size) " pixels square"))))
                (list 192 512))
      (expect
       (equal-bytes? (read-bytes (● c fs) (string-append first "/nested/data.bin")) #u8(0 255 127))
       "the public folder is copied byte for byte")
      (expect-text (text-of c (string-append first "/host.mjs"))
                   (text-of c (string-append (● c root) "/host/browser/host.mjs"))
                   "the page holds the browser host")
      first)))

(define (second-page (p Project) (first String)) (→ String)
  (let* ((c (● p c))
         (custom
          "{\"id\":\"/custom-project-app\",\"name\":\"My application\",\"start_url\":\"./\",\"display\":\"fullscreen\"}"))
    (put! c (public p "manifest.webmanifest") custom)
    (removed! c (public p "obsolete.txt"))
    (succeeded (page p) "second page build")
    (let ((second (page-output p)))
      (expect (not (string=? second first)) "a build publishes a new generation")
      (expect-text (text-of c (string-append second "/manifest.webmanifest")) custom
                   "custom manifest replaces the default whole")
      (expect (not (file-exists? (● c fs) (string-append second "/obsolete.txt")))
              "a file gone from public/ is gone from the new generation")
      (expect-text (text-of c (string-append first "/obsolete.txt")) "first generation"
                   "old readers keep their complete generation")
      second)))

;; Each refused build leaves the published generation as it was.
(define (refusals (p Project) (second String)) (→ Unit)
  (let* ((c (● p c))
         (unchanged (lambda ((what String))
                      (→ Unit)
                      (expect-text (page-output p) second what))))
    (put! c (in p "page/main.scm") "(import (snail core base)) (missing-function)")
    (expect (not (= (● (page p) status) 0)) "a broken page does not build")
    (unchanged "failed compiler attempt leaves output unchanged")
    (put! c (in p "page/main.scm") source)
    (make-directories (● c fs) (public p "host.mjs"))
    (failed-with (page p) "conflicts with a build artifact" "a public file named for the host")
    (unchanged "failed packaging leaves output unchanged")
    (removed! c (public p "host.mjs"))
    ;; store/ holds the files a program links, so the name is the build's.
    (make-directories (● c fs) (public p "store"))
    (failed-with (page p) "conflicts with a build artifact" "a public store/")
    (unchanged "a reserved name is refused in every build")
    (removed! c (public p "store"))
    (link! c (● p root) (public p "recursive-link"))
    (failed-with (page p) "cannot be symbolic links" "a link in public/")
    (unchanged "and leaves the output unchanged")
    (removed! c (public p "recursive-link"))
    (unless (string=? (first-line (● (command c "id" (list "-u") "/" "") stdout)) "0")
      (succeeded (command c "chmod" (list "0" (public p "nested")) "/" "") "chmod")
      (let ((ran (page p)))
        (succeeded (command c "chmod" (list "755" (public p "nested")) "/" "") "chmod")
        (failed-with ran "cannot read directory" "an unreadable public directory")
        (unchanged "an unreadable public directory is not silently omitted")))))

(define (occupied (p Project)) (→ Unit)
  (let ((c (● p c)))
    (put! c (in p "build/occupied/keep.txt") "unmanaged")
    (failed-with (build p "node" "occupied.scm") "unmanaged build output" "an occupied output")
    (expect-text (text-of c (in p "build/occupied/keep.txt"))
                 "unmanaged"
                 "an unmanaged output is kept")))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let* ((c (context arguments fs processes environment))
         (p (new Project (c c) (root (scratch c "workspace")))))
    (make-directories fs (in p "src"))
    (modes p)
    (lay-out! p)
    (scripts p)
    (let ((second (second-page p (first-page p))))
      (refusals p second))
    (occupied p)
    (removed! c (● p root))
    (write-line out "script builds passed")))

;; ---- Helpers ----

(define (member-of (json Json) (name String)) (→ (Option Json))
  (match json
    ((JsonObject members)
     (match (find (lambda (member) (string=? (● member first) name)) members)
       ((Some found) (Some (● found second)))
       ((None) (None))))
    (_ (None))))

(define (string-member? (json Json) (name String) (wanted String)) (→ Bool)
  (match (member-of json name)
    ((Some (JsonString value)) (string=? value wanted))
    (_ #f)))

(define (some? (value (Option Json))) (→ Bool)
  (match value
    ((Some _) #t)
    ((None) #f)))

;; The unsigned 32-bit big-endian number at `at`, as a PNG's header holds
;; its width and height.
(define (big-endian (bytes Bytes) (at I64)) (→ I64)
  (fold-left
   (lambda (number offset) (+ (* number 256) (i32->i64 (u8->i32 (array-ref bytes (+ at offset))))))
   0
   (iota 4)))

(define (equal-bytes? (a Bytes) (b Bytes)) (→ Bool)
  (and (= (array-length a) (array-length b))
       (every? (lambda (index) (= (u8->i32 (array-ref a index)) (u8->i32 (array-ref b index))))
               (iota (array-length a)))))
