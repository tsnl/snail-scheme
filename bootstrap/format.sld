;; scripts/format-scheme runs this program, built and cached by stage 0.
;; The IDE uses the same pure formatter. This boundary only selects input,
;; writes changed files, and reports checks through the usual CLI diagnostic.
(import
 (snail core base)
 (snail core io)
 (snail shell format))

;; ---- Requests ----

(enum Input
  (StandardInput)
  (CheckFiles ((paths (List String))))
  (WriteFiles ((paths (List String)))))

(struct Request
  ((width I64)
   (input Input)))

(: request (impl (Fn (List String) -> Request)))
(define (request arguments)
  (match arguments
    ((Cons "--width" (Cons columns rest))
     (match (string->i64 columns)
       ((Some width)
        (if (> width 0) (Request width (input-of rest)) (bad-width)))
       ((None) (bad-width))))
    (_ (Request format-width (input-of arguments)))))

(: bad-width (impl (Fn -> Request)))
(define (bad-width)
  (panic "format-scheme: --width takes a positive number of columns"))

(: input-of (impl (Fn (List String) -> Input)))
(define (input-of arguments)
  (match arguments
    ((Nil) (StandardInput))
    ((Cons "--check" (Cons path rest)) (CheckFiles (Cons path rest)))
    ((Cons "--write" (Cons path rest)) (WriteFiles (Cons path rest)))
    (_ (panic "usage: format-scheme [--width COLUMNS] [--write|--check FILE ...]"))))

;; ---- Input and output ----

;; Read scalars, not lines, so EOF does not invent a final newline.
(: read-input (impl (Fn -> String ! console)))
(define (read-input)
  (let loop ((characters (Nil)))
    (let ((code (console-read)))
      (if (= code -1)
          (list->string (reverse characters))
          (loop (Cons (i32->char code) characters))))))

;; Every changed path, in order. Check mode leaves files alone; write mode
;; leaves already formatted files alone, including their timestamps.
(: format-files (impl (Fn I64 Bool (List String) -> (List String) ! fs)))
(define (format-files width write? paths)
  (let loop ((paths paths) (changed (Nil)))
    (match paths
      ((Nil) (reverse changed))
      ((Cons path rest)
       (let* ((before (read-file path)) (after (format-source before width)))
         (if (string=? before after)
             (loop rest changed)
             (begin
               (when write? (write-file path after))
               (loop rest (Cons path changed)))))))))

;; Collect all changed files before reporting, rather than stopping at the
;; first one. Panic prints to stderr and exits with status 1, as other tools do.
(: check-files (impl (Fn I64 (List String) -> Unit ! fs)))
(define (check-files width paths)
  (match (format-files width #f paths)
    ((Nil) (unit))
    (changed
     (panic (string-join (map (lambda (path) (string-append path ": needs formatting")) changed)
                         "\n")))))

(: perform (impl (Fn Request -> Unit ! console fs)))
(define (perform request)
  (match (::input request)
    ((StandardInput) (write-string (format-source (read-input) (::width request))))
    ((CheckFiles paths) (check-files (::width request) paths))
    ((WriteFiles paths) (format-files (::width request) #t paths) (unit))))

(match (command-line)
  ((Cons _ arguments) (perform (request arguments)))
  (_ (panic "format-scheme: missing command line")))
