;; Build-script composition: Lofi emits Wasm, then the standalone package
;; lowers that Wasm and explicitly links Cargo providers. No compiler target.
(import (scheme base) (scheme cxr) (scheme file) (scheme write)
        (chibi filesystem) (chibi pathname) (chibi string) (chibi regexp) (srfi 1)
        (wasm-native) (wasm-native process) (wasm-native wasm-optimize)
        (wasm-native chromium-trace) (lofi source-driver))

;; ---- Source selection and protected outputs ----

(define (native-options arguments)
  (let loop ((arguments arguments) (options '()) (inputs '()))
    (if (null? arguments)
        (begin (unless (= 2 (length inputs)) (error "usage: build-native [OPTIONS] SOURCE OUTPUT"))
               (append options (list (cons 'source (absolute-path (cadr inputs)))
                                     (cons 'output (absolute-path (car inputs))))))
        (let ((flag (car arguments)))
          (cond ((member flag '("--wasm" "--llvm" "--object"))
                 (loop (cdr arguments) (cons (cons 'mode (string->symbol (substring flag 2 (string-length flag)))) options) inputs))
                ((string=? flag "--rust-provider")
                 (unless (>= (length arguments) 3) (error "--rust-provider requires MODULE FILE"))
                 (loop (cdddr arguments) (cons (cons 'provider (list (cadr arguments) (absolute-path (caddr arguments)))) options) inputs))
                ((member flag '("--entry-rust" "--export" "-I" "--library" "--generation-provider"))
                 (unless (pair? (cdr arguments)) (error "missing option value" flag))
                 (loop (cddr arguments)
                       (cons (cons (cond ((string=? flag "--entry-rust") 'entry)
                                         ((string=? flag "--export") 'export)
                                         ((string=? flag "--generation-provider") 'generation-provider) (else 'library))
                                   (if (string=? flag "--export") (cadr arguments) (absolute-path (cadr arguments)))) options) inputs))
                ((string-prefix? "-" flag) (error "unknown native build option" flag))
                (else (loop (cdr arguments) options (cons flag inputs))))))))
(define (all-options options name)
  (reverse (map cdr (filter (lambda (entry) (eq? name (car entry))) options))))
(define (protected-output? root output inputs libraries)
  (or (any (lambda (input) (paths-alias? output input)) inputs)
      (any (lambda (directory) (string-prefix? (string-append directory "/") output))
           (append (map (lambda (name) (path-join root name)) '("src" "scripts" "lib" "wasm-native")) libraries))))

;; ---- Command entry policy ----

(define (command-entry llvm directory)
  (let ((signature (regexp-search (rx "define " ($ (or "void" "i32" "i64")) " @\"wasm.main\"()") (read-text llvm))))
    (unless signature (error "native command requires a zero-argument main returning Unit, I32 or I64"))
    (let ((result (regexp-match-submatch signature 1)) (path (path-join directory "entry.rs")))
      (write-text path
                  (string-append "unsafe extern \"C\" { fn native_module_init(); #[link_name = \"wasm.main\"] fn guest_main()"
                                 (if (string=? result "void") "" (string-append " -> " result)) "; }\n"
                                 "fn main() {\n    snail_runtime::native::initialize_host();\n    unsafe { native_module_init(); }\n"
                                 (if (string=? result "void") "    unsafe { guest_main(); }\n    let status = 0;\n"
                                     "    let value = unsafe { guest_main() } as i64;\n    let status = if (0..=255).contains(&value) { value as i32 } else { 1 };\n")
                                 "    std::process::exit(snail_runtime::native::native_finish(status));\n}\n"))
      path)))

;; ---- Ordinary Wasm and native library calls ----

(define (import-record declaration)
  (make-native-import (caar declaration) (cadar declaration) (cadr declaration)
                      (caddr declaration) (if (null? (cadddr declaration)) 'void (car (cadddr declaration)))))
(define (source-wasm root options directory)
  (let ((text (path-join directory "source.wat")) (binary (path-join directory "source.wasm")))
    (parameterize ((library-directories (all-options options 'library))
                   (generation-provider-module (option-ref options 'generation-provider #f))
                   (command-program? (not (option-ref options 'entry #f))))
      (apply source-file->wat-file root (option-ref options 'source #f) text
             (map string->symbol (all-options options 'export))))
    (assemble-wasm text binary)
    binary))
(define (compile-native root options directory bindings)
  (let* ((source (option-ref options 'source #f)) (mode (option-ref options 'mode 'lofi))
         (llvm (path-join directory "module.ll")) (object (path-join directory "module.o")))
    (with-chromium-trace-to
     (path-join directory "compile.trace.json")
     (lambda ()
       (cond ((eq? mode 'object) (write-bytes object (read-bytes source)))
             ((eq? mode 'llvm) (write-text llvm (read-text source)) (llvm-object llvm object))
             (else (wasm-binary->llvm (if (eq? mode 'wasm) source (source-wasm root options directory))
                                      (map import-record bindings) directory llvm)
                   (llvm-object llvm object)))))
    (link-native-object (path-join root "wasm-native") object
                        (or (option-ref options 'entry #f) (command-entry llvm directory))
                        (all-options options 'provider) directory)))

;; ---- Stable inputs and retained build evidence ----

(define (build-native-main root arguments)
  (let* ((options (native-options arguments)) (output (option-ref options 'output #f))
         (providers (all-options options 'provider)) (libraries (all-options options 'library))
         (inputs (append (filter string? (list (option-ref options 'source #f) (option-ref options 'entry #f)
                                               (option-ref options 'generation-provider #f)))
                         (append-map rust-source-inputs (append (map cadr providers)
                                                                (if (option-ref options 'entry #f)
                                                                    (list (option-ref options 'entry #f)) '())))
                         (directory-files-recursive (path-join root "src"))
                         (directory-files-recursive (path-join root "scripts"))
                         (append-map directory-files-recursive (cons (path-join root "lib") libraries))
                         (append-map (lambda (part) (directory-files-recursive (path-join root "wasm-native" part)))
                                     '("src" "scheme" "scripts"))
                         (list (path-join root "wasm-native/Cargo.toml") (path-join root "wasm-native/Cargo.lock")))))
    (when (protected-output? root output inputs libraries) (error "native output must not replace an input" output))
    (let ((directory (make-build-directory (path-directory output) (string-append (path-strip-directory output) ".native-")))
          (before (source-hashes inputs)))
      (parameterize ((current-command-records '()) (current-command-log (path-join directory "commands.json")))
        (dynamic-wind
            (lambda () #f)
            (lambda ()
              (let ((bindings (append (runtime-bindings (path-join root "wasm-native"))
                                      (append-map (lambda (provider) (apply rust-bindings provider)) providers))))
                (check-provider-bindings '() bindings)
                (let ((program (compile-native root options directory bindings)))
                  (check-stable-inputs before)
                  (rename-file program output))))
            (lambda () (native-evidence root directory inputs before output))))))
  0)

(command-line-main (lambda (arguments) (build-native-main (car arguments) (cdr arguments))) "lofi")
