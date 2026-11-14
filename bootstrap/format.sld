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

(record Request
  ((width I64)
   (input Input)))

(define (request (arguments (List String))) (→ Request)
  (match arguments
    ((Cons "--width" (Cons columns rest))
     (match (string->i64 columns)
       ((Some width)
        (if (> width 0) (new Request (width width) (input (input-of rest))) (bad-width)))
       ((None) (bad-width))))
    (_ (new Request (width (format-width)) (input (input-of arguments))))))

(define (bad-width) (→ Request)
  (panic "format-scheme: --width takes a positive number of columns"))

(define (input-of (arguments (List String))) (→ Input)
  (match arguments
    ((Nil) (StandardInput))
    ((Cons "--check" (Cons path rest)) (CheckFiles (Cons path rest)))
    ((Cons "--write" (Cons path rest)) (WriteFiles (Cons path rest)))
    (_ (panic "usage: format-scheme [--width COLUMNS] [--write|--check FILE ...]"))))

;; ---- Input and output ----

;; Read scalars, not lines, so EOF does not invent a final newline.

(define (read-input) (→ String) (! input-port)
  (let loop ((characters (Nil)))
    (match (read-char)
      ((None) (list->string (reverse characters)))
      ((Some char) (loop (Cons char characters))))))

;; Every changed path, in order. Check mode leaves files alone; write mode
;; leaves already formatted files alone, including their timestamps.

(define (format-files (width I64) (write? Bool) (paths (List String))) (→ (List String)) (! fs)
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

(define (check-files (width I64) (paths (List String))) (→ Unit) (! fs)
  (match (format-files width #f paths)
    ((Nil) (unit))
    (changed
     (panic (string-join (map (lambda (path) (string-append path ": needs formatting")) changed)
                         "\n")))))

(define (perform (request Request)) (→ Unit) (! input-port output-port fs)
  (match (● request input)
    ((StandardInput) (write-string (format-source (read-input) (● request width))))
    ((CheckFiles paths) (check-files (● request width) paths))
    ((WriteFiles paths) (format-files (● request width) #t paths) (unit))))

(define (main) (→ Unit) (! fs input-port output-port)
  (match (command-line)
    ((Cons _ arguments) (perform (request arguments)))
    (_ (panic "format-scheme: missing command line")))
  (unit))
