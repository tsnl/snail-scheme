;; Typed serialization and its two wire encodings execute with real services.
(define-library (snail-tests serialization)
  (export run-serialization-suite)
  (import
   (scheme base)
   (scheme cxr)
   (scheme write)
   (srfi 1)
   (srfi 95)
   (only (chibi string) string-suffix?)
   (only (chibi pathname) path-strip-extension)
   (snail-tests harness))
  (begin

    ;; ---- One fixture carries its source, scalar result and rejection probes ----

    (define (source-path case)
      (path "tests/serialization" (string-append (field case 'name) ".sld")))
    (define (guest-path case)
      (path-join (artifacts) (string-append (field case 'name) ".wasm")))
    (define (probes case)
      (cons (cons "main" (field case 'result "42"))
            (map (lambda (name) (cons name "trap")) (rows (field case 'reject '#())))))
    (define (compile-fixture case)
      (let ((exports (rows (field case 'reject '#()))))
        (build-guest (source-path case) (guest-path case) exports
                     (list "--library" (path "tests/serialization")))))
    (define (check-compile-rejection case)
      (checked (field case 'name)
               (list (path "scripts/build-lofi") "--library" (path "tests/serialization")
                     (source-path case) (guest-path case))
               `((status . error) (error . ,(field case 'compile_error))))
      (display (string-append "PASS " (field case 'name) " compile rejection\n")))
    (define (link-fixture case form)
      (let ((raw? (string=? form "raw")) (wasm (guest-path case)))
        (checked (string-append (field case 'name) "-" form "-link")
                 (append (list (path "scripts/link-lofi-runtime") "--runtime"
                               (path "build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm"))
                         (if raw? '("--diagnostic-prune-only") '())
                         (list (if raw? (string-append wasm ".raw.wasm") wasm)
                               (build-path (string-append (field case 'name) "-" form ".wasm")))))))
    (define (check-wasm case form)
      (let ((artifact (build-path (string-append (field case 'name) "-" form ".wasm"))))
        (for-each (lambda (probe)
                    (let ((record (checked (string-append (field case 'name) "-" form "-" (car probe))
                                           (node (path "tests/serialization/run.mjs") artifact (car probe) (cdr probe)))))
                      (check-diagnostic case probe record)))
                  (probes case))
        (display (string-append "PASS " (field case 'name) " " form "\n"))))
    (define (check-diagnostic case probe record)
      (when (and (string=? (cdr probe) "trap") (field case 'diagnostic))
        (assert-that (contains? (field record 'stderr) (field case 'diagnostic))
                     "missing serialization failure diagnostic" (car probe))))

    ;; ---- Native calls exercise the same zero-argument exports ----

    (define (rust-declaration name index type)
      (string-append "#[link_name = \"wasm." name "\"] fn probe_" (number->string index)
                     "() -> " (if (string=? type "I64") "i64" "i32") ";\n"))
    (define (native-entry case)
      (let* ((checks (probes case)) (entry (build-path (string-append (field case 'name) "-entry.rs")))
             (indexes (iota (length checks))))
        (write-text entry
                    (string-append "#[path = \"" (path "tests/native-support.rs") "\"] mod support;\nunsafe extern \"C\" {\n"
                                   (apply string-append (map (lambda (probe index) (rust-declaration (car probe) index (field case 'type))) checks indexes))
                                   "}\nfn main() { let args = support::initialize(); let probe: usize = args[1].parse().unwrap();\n"
                                   "if probe != 0 { assert_eq!(unsafe { probe_0() }, " (field case 'result "42") "); }\nlet value = unsafe { match probe {\n"
                                   (apply string-append (map (lambda (index) (string-append (number->string index) " => probe_" (number->string index) "() as i64,\n")) indexes))
                                   "_ => panic!(\"unknown probe\") } }; assert_eq!(value, " (field case 'result "42") "); support::finish(0); }\n"))
        entry))
    (define (check-native case)
      (let ((native (build-path (string-append (field case 'name) ".native"))))
        (build-native (string-append (guest-path case) ".raw.wasm") native (native-entry case) '())
        (native-guest-identical! native (guest-path case))
        (indexed-for-each
         (lambda (index probe)
           (let ((record (checked (string-append (field case 'name) "-native-" (car probe)) (list native (number->string index))
                                  `((status . ,(if (string=? (cdr probe) "trap") 1 0))
                                    (environment . (("SNAIL_NATIVE_GC_INTERVAL" . ,(field case 'gc_interval "1"))))))))
             (check-diagnostic case probe record))) (probes case))
        (display (string-append "PASS " (field case 'name) " native\n"))))

    ;; ---- Selection keeps development checks within the complete case inventory ----

    (define (check-inventory cases)
      (let ((names (map (lambda (case) (field case 'name)) cases))
            (files (filter (lambda (name) (string-suffix? ".sld" name))
                           (directory-files (path "tests/serialization")))))
        (assert-equal (length names) (length (delete-duplicates names)) "duplicate serialization fixtures")
        (assert-equal (sort names string<?) (sort (map path-strip-extension files) string<?)
                      "serialization fixture inventory differs")))
    (define (run-serialization-suite)
      (let* ((cases (rows (read-json (path "tests/serialization/cases.json"))))
             (selected (argument-positionals)) (only (argument-value "--only" #f)))
        (check-inventory cases)
        (assert-that (member only '(#f "wasm" "native")) "unknown serialization target")
        (for-each (lambda (name) (assert-that (any (lambda (case) (string=? name (field case 'name))) cases) "unknown serialization case" name)) selected)
        (unless (null? selected) (set! cases (filter (lambda (case) (member (field case 'name) selected)) cases)))
        (unless (equal? only "native") (runtime-build))
        (for-each (lambda (case)
                    (if (field case 'compile_error)
                        (unless (equal? only "native") (check-compile-rejection case))
                        (begin
                          (unless (equal? only "native")
                            (compile-fixture case)
                            (for-each (lambda (form) (link-fixture case form) (check-wasm case form)) '("raw" "optimized")))
                          (unless (equal? only "wasm") (check-native case))))) cases)
        (complete! "derived serialization and common wire representation"
                   `((passed . #t) (fixtures . ,(length cases)) (target . ,(or only "all"))))))))
