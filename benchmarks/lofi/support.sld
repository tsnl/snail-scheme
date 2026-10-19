;; Frozen benchmark inputs and complete result predicates.
(define-library (lofi support)
  (export field fields-with json-array relative-path copy-file copy-tree
          output-files-match?
          observation-repetitions source-files verify-source-files environment-with file-digests)
  (import
   (scheme base)
   (scheme char)
   (scheme cxr)
   (scheme file)
   (scheme inexact)
   (scheme write)
   (srfi 1)
   (srfi 69)
   (srfi 95)
   (only (chibi string) string-join string-split string-prefix? string-null? string-any)
   (except (chibi filesystem) file-exists?)
   (lofi host process))
  (begin

    ;; ---- Checked configuration and ordinary files ----

    (define (field value name . fallback)
      (let ((entry (assq name value)))
        (cond (entry (cdr entry)) ((pair? fallback) (car fallback))
              (else (error "missing benchmark field" name)))))

    (define (fields-with value . fields)
      (append fields (filter (lambda (entry) (not (assq (car entry) fields))) value)))

    (define (environment-with environment overrides)
      (append overrides (filter (lambda (entry) (not (assoc (car entry) overrides))) environment)))

    (define (json-array value)
      (unless (vector? value) (error "expected a JSON array" value))
      (vector->list value))

    (define (relative-path text)
      (unless (and (string? text) (positive? (string-length text))
                   (not (string-prefix? "/" text))
                   (not (member ".." (string-split text #\/))))
        (error "expected a nonempty relative path without parent traversal" text))
      text)

    (define (copy-file source target)
      (unless (file-regular? source) (error "expected ordinary input file" source))
      (create-directory* (path-directory target))
      ;; Chibi's portable bytevector I/O loops over individual bytes. Copying
      ;; a Rust installation needs the host's ordinary bulk file operation.
      (run-command! (list (tool-name "CP" "cp") "--" source target))
      (unless (chmod target (file-mode source)) (error "cannot retain input file mode" target)))

    (define (source-files directory)
      (sort (directory-files-recursive directory) string<?))

    (define (copy-tree source target)
      (create-directory* target)
      (for-each
       (lambda (path)
         (when (file-link? path) (error "cannot freeze a symbolic link" path))
         (copy-file path (path-join target (substring path (+ 1 (string-length source))))))
       (source-files source)))

    (define (verify-source-files directory files)
      (let ((paths (map (lambda (entry) (path-join directory (relative-path (symbol->string (car entry))))) files)))
        (for-each (lambda (path)
                    (unless (and (not (file-link? path)) (file-regular? path))
                      (error "frozen dependency is not an ordinary file" path))) paths)
        (for-each (lambda (expected actual)
                    (unless (string=? (cdr expected) (cdr actual))
                      (error "frozen dependency changed" (car actual))))
                  files (file-digests paths))))

    (define (file-digests paths)
      ;; Bound argv size while hashing a complete Rust installation. Null
      ;; separators preserve filenames containing spaces or newlines.
      (if (null? paths) '()
          (let ((count (min 256 (length paths))))
            (append (digest-batch (take paths count)) (file-digests (drop paths count))))))

    (define (digest-batch paths)
      (let* ((record (run-command/capture (append (list (tool-name "SHA256SUM" "sha256sum") "-z" "--") paths)
                                          '((supervisor . #f) (include-output-hex? . #f))))
             (rows (string-split (field record 'stdout) #\null)))
        (unless (and (= 0 (field record 'status)) (= (+ 1 (length paths)) (length rows)) (string=? "" (last rows)))
          (error "cannot hash frozen files" paths (field record 'stderr)))
        (map checked-digest paths (drop-right rows 1))))

    (define (checked-digest path row)
      (unless (and (>= (string-length row) 66) (string=? (substring row 64 66) "  ")
                   (string=? (substring row 66) path)
                   (every (lambda (character) (or (char<=? #\0 character #\9) (char<=? #\a character #\f)))
                          (string->list (substring row 0 64))))
        (error "malformed file digest" path row))
      (cons path (substring row 0 64)))

    (define (observation-repetitions spec)
      (let ((basis (field spec 'observation_basis "canonical-count")))
        (cond ((string=? basis "whole-run") 1)
              ((string=? basis "canonical-count") (max 0 (field spec 'count)))
              (else (error "unknown observation basis" basis)))))

    ;; ---- Full byte predicates, including the entire numbered output set ----

    (define (numbered-output-path pattern iteration)
      (relative-path
       (if (string? pattern) pattern
           (string-append (field pattern 'prefix)
                          (number->string (+ (field pattern 'index_offset) (* iteration (field pattern 'index_step))))
                          (field pattern 'suffix)))))

    (define (numbered-outputs-match? source working target route)
      (let* ((manifest (read-json (path-join source "output-manifest.json")))
             (expected (append-map
                        (lambda (iteration)
                          (map (lambda (row) (cons (numbered-output-path (field row 'path) iteration) row))
                               (json-array (field manifest 'files))))
                        (iota (field manifest 'iterations))))
             (prefix (+ 1 (string-length working)))
             (digests (file-digests (source-files (path-join working "outputs"))))
             (actual (map (lambda (entry) (cons (substring (car entry) prefix) (cdr entry))) digests))
             (expected-table (alist->hash-table expected string=?))
             (actual-table (alist->hash-table actual string=?))
             (bad (filter (lambda (entry) (not (numbered-file-matches? working entry actual-table))) expected))
             (extra (filter (lambda (name) (not (hash-table-exists? expected-table name))) (map car actual)))
             (passed (and (= (hash-table-size expected-table) (field manifest 'total_files) (length expected))
                          (null? extra) (null? bad) (= (length actual) (length expected)))))
        (write-json (path-join target (string-append route "-outputs.json"))
                    `((passed . ,passed) (expected_files . ,(hash-table-size expected-table)) (actual_files . ,(length actual))
                      (mismatched . ,(list->vector (map car bad))) (extra . ,(list->vector extra))))
        passed))

    (define (numbered-file-matches? working entry actual)
      (let ((path (path-join working (car entry))) (row (cdr entry)))
        (and (not (file-link? path)) (hash-table-exists? actual (car entry))
             (= (file-size path) (field row 'bytes))
             (equal? (hash-table-ref actual (car entry)) (field row 'sha256)))))

    (define (tail-bytes input)
      (let ((text (utf8->string input)))
        (when (string-any (lambda (character) (char=? character #\return)) text)
          (error "Tail oracle requires LF-only input"))
        (let* ((lines (string-split text #\newline))
               (lines (if (and (pair? lines) (string-null? (last lines))) (drop-right lines 1) lines)))
          ;; Keep call arity bounded even when the input contains many lines.
          (string->utf8 (string-join (map (lambda (line) (string-append line "\n")) (reverse lines)) "")))))

    (define (output-files-match? source working target route)
      (let* ((spec (read-json (path-join source "spec.json"))) (name (field spec 'name)))
        (cond
         ((string=? name "slatex") (numbered-outputs-match? source working target route))
         ((not (member name '("cat" "tail" "ray"))) #t)
         (else
          (let* ((paths (field spec 'pathnames '#()))
                 (path (if (string=? name "ray") (field spec 'pathname) (vector-ref paths 1)))
                 (output (path-join working (relative-path path)))
                 (expected (expected-output-hash name spec working target))
                 (actual (and (file-regular? output) (file-sha256 output))))
            (write-json (path-join target (string-append route "-outputs.json"))
                        `((path . ,path) (actual . ,(or actual 'null)) (expected . ,expected)))
            (equal? actual expected))))))

    (define (expected-output-hash name spec working target)
      (if (string=? name "ray") (field spec 'image_sha256)
          (let ((input (path-join working (relative-path (vector-ref (field spec 'pathnames) 0)))))
            (if (string=? name "cat") (file-sha256 input)
                (let ((oracle (path-join target "tail-oracle.output")))
                  (write-bytes oracle (tail-bytes (read-bytes input)))
                  (file-sha256 oracle)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-lofi-support)
    (import
     (lofi host test-utils)
     (chibi temp-file))
    (begin
      (define (rejected? thunk) (guard (failure (else #t)) (thunk) #f))

      (define (test-numbered-files)
        (call-with-temp-dir "lofi-numbered-outputs"
                            (lambda (root preserve)
                              (create-directory* (path-join root "outputs"))
                              (write-text (path-join root "outputs/z3.tex") "canonical output\n")
                              (let ((row `((path . ((prefix . "outputs/z") (index_offset . 3) (index_step . 57) (suffix . ".tex")))
                                           (bytes . 17) (sha256 . ,(file-sha256 (path-join root "outputs/z3.tex"))))))
                                (write-json (path-join root "output-manifest.json") `((iterations . 2) (total_files . 2) (files . ,(vector row))))
                                (copy-file (path-join root "outputs/z3.tex") (path-join root "outputs/z60.tex"))
                                (expect (numbered-outputs-match? root root root "complete") #t)
                                (write-text (path-join root "outputs/z60.tex") "incorrect output\n")
                                (expect (numbered-outputs-match? root root root "changed") #f)
                                (delete-file (path-join root "outputs/z60.tex"))
                                (expect (numbered-outputs-match? root root root "missing") #f)
                                (copy-file (path-join root "outputs/z3.tex") (path-join root "outputs/z60.tex"))
                                (copy-file (path-join root "outputs/z3.tex") (path-join root "outputs/z117.tex"))
                                (expect (numbered-outputs-match? root root root "extra") #f)
                                (write-json (path-join root "output-manifest.json")
                                            `((iterations . 2) (total_files . 2) (files . ,(vector (fields-with row (cons 'path "outputs/z3.tex"))))))
                                (expect (numbered-outputs-match? root root root "collision") #f)))))

      (define (test-digest-filenames)
        (call-with-temp-dir "lofi-digests"
                            (lambda (root preserve)
                              (let ((paths (map (lambda (name) (path-join root name)) '("a b" "a\nb"))))
                                (for-each (lambda (path) (write-text path "same bytes")) paths)
                                (let ((digests (file-digests paths)))
                                  (expect (map car digests) paths)
                                  (expect (map cdr digests) (map file-sha256 paths)))))))

      (define (test-tail-lines)
        (for-each
         (lambda (example)
           (expect (tail-bytes (string->utf8 (car example))) (string->utf8 (cadr example))))
         '(("" "") ("a" "a\n") ("a\n" "a\n") ("\n" "\n") ("\n\n" "\n\n")
           ("a\nb" "b\na\n") ("a\nb\n" "b\na\n") ("\na\n" "a\n\n")
           ("a\n\nb\n" "b\n\na\n") ("λ🙂\né\n" "é\nλ🙂\n")))
        (for-each (lambda (input) (expect (rejected? (lambda () (tail-bytes (string->utf8 input)))) #t))
                  '("\ra\n" "a\rb\n" "a\r" "a\r\n")))

      (define (numbered-lines start end step)
        (let ((output (open-output-string)))
          (let loop ((index start))
            (unless (= index end)
              (display "line " output) (display index output) (newline output)
              (loop (+ index step))))
          (string->utf8 (get-output-string output))))

      (define (test-tail-many-lines)
        ;; More lines than the canonical bib fixture, without expanding a
        ;; fragment list into that many arguments in the compiler host.
        (expect (tail-bytes (numbered-lines 0 40000 1)) (numbered-lines 39999 -1 -1)))

      (define (test-lofi-support)
        (run-test test-numbered-files)
        (run-test test-digest-filenames)
        (run-test test-tail-lines)
        (run-test test-tail-many-lines))))))
