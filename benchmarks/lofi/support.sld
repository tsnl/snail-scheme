;; Native benchmark inputs and complete result predicates.
(define-library (lofi support)
  (export field fields-with json-array relative-path copy-file copy-tree
          native-configuration native-sources output-files-match?
          observation-repetitions source-files verify-source-files environment-with file-digests)
  (import (scheme base) (scheme char) (scheme cxr) (scheme file)
          (scheme inexact) (scheme write) (srfi 1) (srfi 69) (srfi 95)
          (only (chibi string) string-join string-split string-prefix? string-null? string-any)
          (except (chibi filesystem) file-exists?)
          (wasm-native process))
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

    ;; ---- Literal Rust configuration, separate from guest optimization ----

    (define (rust-string text)
      (let ((port (open-output-string)))
        (write-char #\" port)
        (string-for-each
         (lambda (character)
           (case character
             ((#\") (display "\\\"" port)) ((#\\) (display "\\\\" port))
             ((#\newline) (display "\\n" port)) ((#\return) (display "\\r" port))
             ((#\tab) (display "\\t" port))
             (else (if (< (char->integer character) 32)
                       (display (string-append "\\u{" (number->string (char->integer character) 16) "}") port)
                       (write-char character port)))))
         text)
        (write-char #\" port)
        (get-output-string port)))

    (define (rust-number value type)
      (unless (and (real? value) (finite? value))
        (error "native benchmark configuration requires finite numbers" value))
      (if (string=? type "f64") (number->string (inexact value))
          (begin
            (unless (and (exact-integer? value) (<= (- (expt 2 63)) value) (< value (expt 2 63)))
              (error "native benchmark integer is outside I64" value))
            (number->string value))))

    (define (rust-constant name type value)
      (string-append "pub const " name ": " type " = " (rust-number value type) ";\n"))

    (define (rust-array name type values)
      (string-append "pub const " name ": &[" type "] = &["
                     (string-join (map (lambda (value) (rust-number value type)) values) ", ") "];\n"))

    (define (rust-strings name values)
      (string-append "pub const " name ": &[&str] = &["
                     (string-join (map rust-string values) ", ") "];\n"))

    (define (numeric-arrays prefix values)
      (string-append
       (rust-array (string-append prefix "_INTEGERS") "i64"
                   (map (lambda (value) (if (exact-integer? value) value 0)) values))
       (rust-array (string-append prefix "_REALS") "f64" values)))

    (define (offsets arrays)
      (let loop ((rest arrays) (offset 0) (result '()))
        (if (null? rest) (reverse result)
            (loop (cdr rest) (+ offset (length (car rest))) (cons offset result)))))

    (define (observation-repetitions spec)
      (let ((basis (field spec 'observation_basis "canonical-count")))
        (cond ((string=? basis "whole-run") 1)
              ((string=? basis "canonical-count") (max 0 (field spec 'count)))
              (else (error "unknown observation basis" basis)))))

    (define (configured-count-check spec)
      (if (member "configured-count" (json-array (field spec 'additional_exports '#())))
          (string-append
           "unsafe extern \"C\" { #[link_name = \"wasm.configured-count\"] fn guest_configured_count() -> i64; }\n"
           "pub unsafe fn assert_configured_count() { assert_eq!(unsafe { guest_configured_count() }, CONFIGURED_COUNT); }\n")
          "pub unsafe fn assert_configured_count() {}\n"))

    (define (resource-expectations spec)
      (let ((runtime (field spec 'runtime "")) (count (observation-repetitions spec)))
        (cond
         ((string=? runtime "scalar-datum-reader")
          (cons 1 (* (vector-length (field spec 'pathnames '#())) count)))
         ((string=? runtime "scalar-io")
          (cons 0 (* (if (string=? (field spec 'name) "tail") 2 1) (field spec 'count))))
         (else (cons -1 -1)))))

    (define (native-expectations spec expected-size)
      (let* ((floating? (member (field spec 'name) '("fibfp" "sumfp" "fft")))
             (type (if floating? "f64" "i64")) (resources (resource-expectations spec))
             (expected (field spec 'expected))
             (barriers (field spec 'barriers_per_iteration (field spec 'worker_barriers 0))))
        (string-append
         (rust-constant "CONFIGURED_COUNT" "i64" (field spec 'count))
         (rust-constant "EXPECTED_SIZE" "i64" expected-size)
         (rust-constant "EXPECTED_SETUP" "i64" (field spec 'setup_barriers -1))
         (rust-constant "EXPECTED_BARRIERS" "i64" (* barriers (observation-repetitions spec)))
         (rust-constant "EXPECTED_SETUP_CLOSED" "i64" (car resources))
         (rust-constant "EXPECTED_WORKER_CLOSED" "i64" (cdr resources))
         (rust-constant "EXPECTED_TOLERANCE" "f64" (field spec 'tolerance 0))
         (string-append "pub type BenchResult = " type ";\n")
         (rust-constant "EXPECTED_RESULT" type (if (vector? expected) 1 expected))
         (configured-count-check spec))))

    (define (native-diagnostics spec)
      (let ((sizes (map json-array (json-array (field spec 'diagnostic_sizes '#())))))
        (string-append
         (rust-strings "DIAGNOSTIC_TEXT" (json-array (field spec 'diagnostic_text '#())))
         (rust-strings "DIAGNOSTIC_PREFIX" (map car sizes))
         (rust-strings "DIAGNOSTIC_SUFFIX" (map cadr sizes)))))

    (define (native-paths spec)
      (let* ((single (field spec 'pathname #f))
             (paths (json-array (field spec 'pathnames (if single (vector single) '#()))))
             (arrays (map (lambda (path) (map char->integer (string->list path))) paths)))
        (string-append
         (rust-array "PATH_CHARACTERS" "u32" (append-map values arrays))
         (rust-array "PATH_SIZES" "i64" (map length arrays))
         (rust-array "PATH_OFFSETS" "i64" (offsets arrays)))))

    (define (native-configuration spec observe?)
      (let* ((inputs (json-array (field spec 'inputs)))
             (vectors (map (lambda (value) (if (vector? value) (json-array value) '())) inputs))
             (expected (field spec 'expected))
             (expected (if (vector? expected) (json-array expected) (list expected))))
        (string-append
         "pub const OBSERVE_BARRIERS: bool = " (if observe? "true" "false") ";\n"
         (numeric-arrays "INPUT" (map (lambda (value) (if (vector? value) 0 value)) inputs))
         (numeric-arrays "VECTOR" (append-map values vectors))
         (numeric-arrays "EXPECTED" expected)
         (rust-array "VECTOR_SIZES" "i64" (map length vectors))
         (rust-array "VECTOR_OFFSETS" "i64" (offsets vectors))
         (native-expectations spec (length expected))
         (native-diagnostics spec) (native-paths spec))))

    (define (path-provider-source spec)
      (cond
       ((string=? (field spec 'name) "tail")
        (string-append
         "\n#[unsafe(export_name = \"path_length\")]\npub extern \"C\" fn path_length(which: i32) -> i64 { black_box(PATH_SIZES[which as usize]) }\n"
         "#[unsafe(export_name = \"path_character\")]\npub extern \"C\" fn path_character(which: i32, at: i64) -> u32 { black_box(PATH_CHARACTERS[(PATH_OFFSETS[which as usize] + at) as usize]) }\n"))
       ((string=? (field spec 'name) "ray")
        (string-append
         "\n#[unsafe(export_name = \"path_length\")]\npub extern \"C\" fn path_length() -> i64 { black_box(PATH_SIZES[0]) }\n"
         "#[unsafe(export_name = \"path_character\")]\npub extern \"C\" fn path_character(at: i64) -> u32 { black_box(PATH_CHARACTERS[at as usize]) }\n"))
       (else "")))

    (define (native-sources support source target timing?)
      (let* ((spec (read-json (path-join source "spec.json")))
             (integer? (string=? (field spec 'host (field spec 'runtime "")) "integer"))
             (integer? (or integer? (member (field spec 'name) '("pi" "chudnovsky"))))
             (kind (if integer? "integer" "scalar"))
             (entry (string-append kind (if timing? "-timing-entry.rs" "-entry.rs"))))
        (if integer? (integer-sources support target spec timing?)
            (scalar-sources support source target spec timing?))
        (copy-file (path-join support entry) (path-join target entry))
        (when (and (not timing?) (member (field spec 'name) '("slatex" "dynamic" "scheme" "compiler")))
          (copy-file (path-join source "native-entry.rs") (path-join target entry)))
        kind))

    (define (scalar-sources support source target spec timing?)
      (write-text (path-join target "case-config.rs") (native-configuration spec (not timing?)))
      (write-text (path-join target "scalar-provider.rs")
                  (string-append (read-text (path-join support "scalar-provider.rs"))
                                 (path-provider-source spec))))

    (define (integer-sources support target spec timing?)
      (copy-file (path-join support "integer-provider.rs") (path-join target "integer-provider.rs"))
      (write-text (path-join target "integer-config.rs")
                  (string-append "pub const OBSERVE_BARRIERS: bool = " (if timing? "false" "true") ";\n"))
      (let* ((expected (json-array (field spec 'expected)))
             (header (append (list (field spec 'count)) (json-array (field spec 'inputs)) (list (length expected)))))
        (write-text (path-join target "native-input.txt")
                    (string-append (string-join (map number->string header) " ") "\n"
                                   (string-join expected "\n") "\n"))))

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
    (import (wasm-native test-utils) (chibi temp-file))
    (begin
      (define (rejected? thunk) (guard (failure (else #t)) (thunk) #f))

      (define (test-scalar-configuration)
        (for-each (lambda (value)
                    (expect (rejected? (lambda () (numeric-arrays "INPUT" (list value)))) #t))
                  (list (expt 2 63) (- (- (expt 2 63)) 1) (string->number "+nan.0") '#(1 2) "answer")))

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
        (run-test test-scalar-configuration)
        (run-test test-numbered-files)
        (run-test test-digest-filenames)
        (run-test test-tail-lines)
        (run-test test-tail-many-lines))))))
