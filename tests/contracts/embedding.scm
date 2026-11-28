;; One build embedding another: a server script's generated library builds
;; a client page (tests/embedding) and links every file of it. Producers run
;; in every build, so a changed client file reaches the next server. A
;; script whose producer builds that script is refused, by name. A producer
;; that needs its own library, at once or once another producer has run, is
;; an import cycle, and a producer in one never runs.
;;
;;   ./snail-scheme run --target node tests/contracts/embedding.scm ROOT
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (contracts support))

(define (served (c Context) (workspace String)) (→ (List String))
  (filter (lambda (line) (not (string=? line "")))
          (lines (● (succeeded (snail c (list "run" "--target" "node" "server.scm") workspace)
                               "the server")
                    stdout))))

(define (sorted? (items (List String))) (→ Bool)
  (match items
    ((Cons a (Cons b rest)) (and (not (string<? b a)) (sorted? (Cons b rest))))
    (_ #t)))

(define (ends-with? (text String) (suffix String)) (→ Bool)
  (and (>= (string-length text) (string-length suffix))
       (string=?
        (substring text (- (string-length text) (string-length suffix)) (string-length text))
        suffix)))

;; A line naming a stored object: store/sha256/ (13 characters), a
;; two-digit shard and a slash, the 64-digit digest, then its size, status
;; and caching.
(define (stored-object? (line String)) (→ Bool)
  (let ((suffix " 3 200 public, max-age=31536000, immutable"))
    (and (starts-with? line "store/sha256/")
         (ends-with? line suffix)
         (= (string-length line) (+ 80 (string-length suffix))))))

(define (embedding (c Context)) (→ Unit)
  (let ((workspace (scratch c "embedding")))
    (succeeded
     (command c "cp" (list "-R" (string-append (● c root) "/tests/embedding/.") workspace) "/" "")
     "cp")
    (put! c (string-append workspace "/snail-scheme-workspace.datum")
          (string-append "(workspace (extends \"" (● c root) "\"))\n"))
    (make-directories (● c fs) (string-append workspace "/client/public/nested"))
    (write-bytes (● c fs) (string-append workspace "/client/public/nested/data.bin") #u8(65 0 255))
    (make-directories (● c fs) (string-append workspace "/client/main.resources"))
    (write-bytes (● c fs) (string-append workspace "/client/main.resources/tile.bin") #u8(4 5 6))
    (let* ((first (served c workspace))
           (listed (reverse (list-drop (reverse first) 1)))
           (paths (map (lambda (line)
                         (match (string-index line #\space)
                           ((Some at) (substring line 0 at))
                           ((None) line)))
                       listed)))
      (expect (sorted? paths) "files are listed in path order")
      (for-each (lambda (path)
                  (expect (member? path paths) (string-append "the client's " path " is linked")))
                (list "index.html" "host.mjs" "main.wasm" "nested/data.bin"))
      (expect (member? "nested/data.bin 3" first) "a linked file names its size")
      (expect (any? (lambda (line)
                      (and (starts-with? line "resources.json ") (ends-with? line " 200 no-cache")))
                    first)
              "the catalog is served uncached")
      (expect (any? stored-object? first) "a stored object is served for good")
      (expect-text (final first) "65,0,255" "the server reads the client's file")
      (expect
       (contains? (text-of c (string-append workspace "/build/client/main/index.html")) "client")
       "the producer publishes the client build in the workspace"))
    (write-bytes (● c fs) (string-append workspace "/client/public/nested/data.bin") #u8(90 0 255))
    (expect-text (final (served c workspace)) "90,0,255" "the next build embeds the changed file")
    (let ((ran (snail c (list "build" "--target" "node" "own.scm") workspace)))
      (failed-with ran "a script's build embeds itself" "a script that embeds itself")
      (expect (contains? (● ran stderr) "own.scm → ") "and is named twice"))
    (removed! c workspace)))

;; Each producer leaves a marker when it runs. A knot's producer imports,
;; through a helper, the library it generates; a late cycle shows only once
;; the first producer's output imports a second generated library, whose
;; producer imports the first.
(define (recipe (workspace String) (parts (List String)) (imports String) (output String))
  (→ String)
  (let ((name (string-join parts " "))
        (marker (string-join parts "-"))
        (quoted (string-join parts "\" \"")))
    (string-append "(generate-library (" name ")\n"
                   "  (import (snail core base) (snail core io) (snail shell syntax) " imports ")\n"
                   "  (lambda ((fs Fs))\n"
                   "    (write-file fs \"" workspace "/" marker ".ran\" \"ran\")\n"
                   "    (library-syntax (list \""
                   quoted
                   "\") (list \"value\") (list (list \"snail\" \"core\" \"base\") "
                   output ")\n"
                   "      (list (form \"define\" (list (form \"value\" (Nil))\n"
                   "            (form \"→\" (list (SymbolSyntax \"String\")))\n"
                   "            (StringSyntax \"" (string-join parts "/") "\")))))))")))

(define (producer-cycles (c Context)) (→ Unit)
  (let* ((workspace (scratch c "producer-cycles"))
         (write (lambda ((name String) (text String))
                  (→ Unit)
                  (put! c (string-append workspace "/" name) text)))
         (ran? (lambda ((name String))
                 (→ Bool)
                 (file-exists? (● c fs) (string-append workspace "/" name ".ran"))))
         (build (lambda ((name String))
                  (→ Ran)
                  (snail c (list "build" "--target" "node" name) workspace))))
    (write "knot.scm" "(import (snail core base) (sample knot)) (define (main) (→ Unit) (unit))")
    (write "src/sample/knot.sld"
           (recipe workspace (list "sample" "knot") "(sample knot-helper)" ""))
    (write "src/sample/knot-helper.sld"
           "(define-library (sample knot-helper) (export) (import (sample knot)) (begin))")
    (write "late.scm" "(import (snail core base) (g one)) (define (main) (→ Unit) (unit))")
    (write "src/g/one.sld" (recipe workspace (list "g" "one") "" "(list \"g\" \"two\")"))
    (write "src/g/two.sld" (recipe workspace (list "g" "two") "(g one)" ""))
    (failed-with (build "knot.scm") "library import cycle through sample.knot" "a knot")
    (expect (not (ran? "sample-knot")) "a producer in a cycle never runs")
    (failed-with (build "late.scm") "library import cycle through g.one" "a late cycle")
    (expect (and (ran? "g-one") (not (ran? "g-two")))
            "only the producer the cycle shows after runs")
    (removed! c workspace)))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let ((c (context arguments fs processes environment)))
    (producer-cycles c)
    (embedding c)
    (write-line out
                "embedding: a build embeds another through a producer; cycles of producers and of builds fail")))

(define (final (items (List String))) (→ String)
  (match (last items)
    ((Some item) item)
    ((None) "")))
