;; Unicode 16 mappings are compared with the installed Rust casing baseline.
(define-library (lofi-tools generate-unicode)
  (export generate-unicode-main)
  (import (scheme base) (scheme cxr) (scheme char) (scheme file) (scheme write)
          (scheme process-context) (srfi 1) (srfi 69)
          (only (srfi 132) list-sort)
          (only (chibi string) string-split string-trim string-prefix? string-contains string-join substring-cursor)
          (wasm-native process) (lofi-tools host-tools))
  (begin

    ;; ---- Structured Unicode mappings ----

    (define-record-type <mappings>
      (make-mappings upper lower simple full digits) mappings?
      (upper mappings-upper) (lower mappings-lower) (simple mappings-simple)
      (full mappings-full) (digits mappings-digits set-mappings-digits!))
    (define (lines text)
      (filter (lambda (line) (not (string=? line ""))) (string-split text #\newline)))
    (define (hex-number text)
      (let ((number (string->number (string-trim text char-whitespace?) 16)))
        (unless (and (exact-integer? number) (<= 0 number #x10ffff)) (error "invalid Unicode code point" text)) number))
    (define (simple-field fields index code)
      (let ((text (list-ref fields index))) (if (string=? text "") code (hex-number text))))
    (define (read-data-row mappings line)
      (let ((fields (string-split line #\;)))
        (unless (= 15 (length fields)) (error "expected a UnicodeData row" line))
        (let ((code (hex-number (car fields))))
          (hash-table-set! (mappings-upper mappings) code (simple-field fields 12 code))
          (hash-table-set! (mappings-lower mappings) code (simple-field fields 13 code))
          (when (string=? (list-ref fields 6) "0")
            (set-mappings-digits! mappings (cons code (mappings-digits mappings)))))))
    (define (folded-scalars values)
      (unless (and (<= 1 (length values) 3)
                   (every (lambda (code) (and (<= 0 code #x10ffff) (not (<= #xd800 code #xdfff)))) values))
        (error "full folding requires one through three valid output scalars" values)) values)
    (define (read-fold-row mappings line)
      (unless (string-prefix? "#" line)
        (let ((fields (string-split line #\;)))
          (unless (>= (length fields) 3) (error "expected a CaseFolding row" line))
          (let ((code (hex-number (car fields))) (status (string-trim (cadr fields) char-whitespace?))
                (target (folded-scalars (map hex-number (string-split (string-trim (caddr fields) char-whitespace?))))))
            (when (member status '("C" "S")) (hash-table-set! (mappings-simple mappings) code (car target)))
            (when (member status '("C" "F")) (hash-table-set! (mappings-full mappings) code target))))))
    (define (read-mappings data folding)
      (let ((mappings (make-mappings (make-hash-table) (make-hash-table) (make-hash-table) (make-hash-table) '()))
            (folding (read-text folding)))
        (unless (string-prefix? "# CaseFolding-16.0.0.txt" folding) (error "expected Unicode 16.0 CaseFolding.txt"))
        (for-each (lambda (line) (read-data-row mappings line)) (lines (read-text data)))
        (for-each (lambda (line) (read-fold-row mappings line)) (lines folding))
        (set-mappings-digits! mappings (reverse (mappings-digits mappings))) mappings))

    ;; ---- Cargo-built Rust baseline ----

    (define (read-native-row table line)
      (let ((fields (string-split line #\;)))
        (unless (= 3 (length fields)) (error "invalid Rust casing row" line))
        (hash-table-set! table (hex-number (car fields))
                         (list (map hex-number (string-split (cadr fields) #\,))
                               (folded-scalars (map hex-number (string-split (caddr fields) #\,)))))))
    (define (native-casing root)
      (let* ((program (build-host-tool root "snail-unicode-baseline"))
             (rows (lines (run-command! (list program)))) (table (make-hash-table))
             (version (map string->number (string-split (car rows) #\.))))
        (unless (and (= 3 (length version)) (every exact-integer? version)) (error "invalid Rust Unicode version" version))
        (for-each (lambda (line) (read-native-row table line)) (cdr rows)) (values version table)))
    (define (native-mapping table code direction)
      (list-ref (hash-table-ref/default table code (list (list code) (list code))) direction))
    (define (native-scalar table code direction)
      (let ((codes (native-mapping table code direction))) (if (= 1 (length codes)) (car codes) code)))
    (define (all-codes mappings native)
      (let ((codes (make-hash-table)))
        (for-each (lambda (table) (hash-table-walk table (lambda (code mapping) (hash-table-set! codes code #t))))
                  (list native (mappings-upper mappings) (mappings-simple mappings) (mappings-full mappings)))
        (list-sort < (hash-table-keys codes))))

    ;; ---- Rust lookup tables ----

    (define (line out . parts) (for-each (lambda (part) (display part out)) parts) (newline out))
    (define (text-lines out texts) (for-each (lambda (text) (line out text)) texts))
    (define (escaped code) (string-append "\\u{" (number->string code 16) "}"))
    (define (emit-header out version)
      (text-lines out '("//! Unicode 16.0 casing exceptions and decimal digits."
                        "//! Generated by scripts/generate-unicode against Rust's native casing."
                        "//! Unicode data © 2024 Unicode, Inc.; https://www.unicode.org/license.txt" ""
                        "// Regenerate the exceptions when Rust changes its Unicode baseline."))
      (line out "const _: () = assert!("
            (string-join (map (lambda (index part) (string-append "char::UNICODE_VERSION." (number->string index)
                                                                  " == " (number->string part))) '(0 1 2) version) " && ") ");")
      (newline out))
    (define (emit-scalar out codes native expected name title direction)
      (line out "// ---- " title " ----") (newline out)
      (line out "pub(crate) fn " name "(character: char) -> char {") (line out "    match character {")
      (for-each (lambda (code)
                  (let ((target (hash-table-ref/default expected code code)))
                    (unless (= target (native-scalar native code direction))
                      (line out "        '" (escaped code) "' => '" (escaped target) "',")))) codes)
      (line out "        _ => { let mut mapped = character." (if (zero? direction) "to_uppercase" "to_lowercase") "();")
      (text-lines out '("            let first = mapped.next().unwrap();"
                        "            if mapped.next().is_none() { first } else { character } }" "    }" "}" "")))
    (define (emit-full-fold out codes native expected)
      (text-lines out '("// ---- Full case folding ----" ""
                        "// The pinned full mappings and native fallback contain one through three"
                        "// scalars. The generator checks this bound; NUL remains an ordinary scalar."
                        "pub(crate) struct Folded {" "    pub(crate) scalars: [char; 3]," "    pub(crate) len: usize," "}" ""
                        "fn collect_folded(mapped: impl Iterator<Item = char>) -> Folded {"
                        "    let mut result = Folded { scalars: ['\\0'; 3], len: 0 };" "    for scalar in mapped {"
                        "        result.scalars[result.len] = scalar;" "        result.len += 1;" "    }"
                        "    assert!(result.len > 0);" "    result" "}" ""
                        "pub(crate) fn full_fold(character: char) -> Folded {" "    let exception = match character {"))
      (for-each (lambda (code)
                  (let ((target (hash-table-ref/default expected code (list code))))
                    (unless (equal? target (native-mapping native code 1))
                      (line out "        '" (escaped code) "' => \"" (apply string-append (map escaped target)) "\",")))) codes)
      (text-lines out '("        _ => return collect_folded(character.to_lowercase())," "    };"
                        "    collect_folded(exception.chars())" "}" "")))
    (define (emit-digits out digits)
      (text-lines out '("// ---- Decimal digits ----" "" "pub(crate) fn digit_value(character: char) -> Option<u8> {"
                        "    const STARTS: &[u32] = &["))
      (let loop ((digits digits))
        (unless (null? digits)
          (let ((count (min 8 (length digits))))
            (line out "        " (string-join (map (lambda (code) (string-append "0x" (number->string code 16)))
                                                   (take digits count)) ", ") ",")
            (loop (drop digits count)))))
      (text-lines out '("    ];" "    let point = character as u32;"
                        "    let index = STARTS.partition_point(|start| *start <= point);" "    if index == 0 { return None; }"
                        "    let digit = point - STARTS[index - 1];" "    (digit < 10).then_some(digit as u8)" "}")))
    (define (generate root data folding)
      (let ((mappings (read-mappings data folding)) (out (open-output-string)))
        (call-with-values (lambda () (native-casing root))
          (lambda (version native)
            (let ((codes (all-codes mappings native)))
              (emit-header out version)
              (emit-scalar out codes native (mappings-upper mappings) "uppercase" "Uppercase" 0)
              (emit-scalar out codes native (mappings-lower mappings) "lowercase" "Lowercase" 1)
              (emit-scalar out codes native (mappings-simple mappings) "fold_character" "Fold character" 1)
              (emit-full-fold out codes native (mappings-full mappings)) (emit-digits out (mappings-digits mappings)))))
        (get-output-string out)))

    ;; ---- Regeneration preserves the module's tests ----

    (define (preserved-tests path)
      (let* ((existing (if (file-exists? path) (read-text path) "")) (marker "// ---- Tests ----")
             (cursor (string-contains existing marker)) (tests (and cursor (substring-cursor existing cursor))))
        (if (and tests (not (string=? tests marker))) (string-append "\n" tests) "")))
    (define (generate-unicode-main root arguments)
      (cond ((or (member "--help" arguments) (member "-h" arguments))
             (display "usage: generate-unicode UNICODE_DATA CASE_FOLDING OUTPUT\n") 0)
            ((not (= 3 (length arguments)))
             (display "usage: generate-unicode UNICODE_DATA CASE_FOLDING OUTPUT\n" (current-error-port)) 2)
            (else
             (guard (failure (else (display "generate-unicode: " (current-error-port)) (write failure (current-error-port))
                                   (newline (current-error-port)) 1))
               (let* ((output (caddr arguments)) (tests (preserved-tests output))
                      (generated (generate root (car arguments) (cadr arguments))))
                 (write-text output (string-append generated tests)) 0)))))))
