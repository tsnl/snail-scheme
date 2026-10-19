;; A build chooses source once per key. Generator dependencies and the imports
;; of the returned library have separate maps, but share a preparation chain.
;; Start with source-file->core and source-file->wasm for the ordinary file path.
;; They prepare a library map for compiler.sld, then emit Wasm for the build driver.
(define-library (lofi compiler source-driver)
  (export make-generation-context generation-context?
          prepare-library collect-libraries collect-source-file
          library-directories generation-provider-module command-program?
          source-file->core source-file->wasm source-file->wat-file)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (scheme write)
   (only (lofi host json) json->string)
   (only (chibi temp-file) call-with-temp-dir)
   (lofi compiler reader)
   (lofi compiler syntax-parser)
   (lofi compiler syntax)
   (lofi compiler source)
   (lofi host chromium-trace)
   (lofi host build-host)
   (lofi compiler frontend)
   (lofi compiler library)
   (lofi compiler library-transfer)
   (lofi compiler bootstrap)
   (lofi compiler specialize)
   (lofi compiler emit-wasm)
   (only (lofi compiler primitives) primitive-names)
   (only (lofi compiler types) strict-error resolve)
   (only (lofi compiler checked) program-body program-type)
   (only (lofi compiler ir) node-loc)
   (only (lofi host wasm) write-wasm))
  (begin

    ;; ---- Located file descriptions ----

    (define-record-type <generation>
      (make-generation producer) generation?
      (producer generation-producer))
    (define (form-head form)
      (and (list-syntax? form) (pair? (list-syntax-elements form))
           (syntax-identifier? (car (list-syntax-elements form)))
           (atom-syntax-value (car (list-syntax-elements form)))))
    (define (proper-elements form)
      (unless (and (list-syntax? form) (null? (list-syntax-improper-tail form)))
        (error "expected a proper Lofi form" (syntax-loc form)))
      (list-syntax-elements form))
    (define (library-key? key)
      (and (list? key) (pair? key)
           (let names ((tail key))
             (or (null? tail) (and (symbol? (car tail)) (names (cdr tail)))))))
    (define (source-key form)
      (let ((key (map syntax->datum (proper-elements form))))
        (unless (library-key? key) (error "expected a nonempty Lofi library name" (syntax-loc form))) key))
    (define (located-datum datum loc)
      (cond ((syntax? datum) datum)
            ((list? datum) (make-list-syntax (map (lambda (item) (located-datum item loc)) datum) '() loc))
            (else (make-atom-syntax datum loc))))
    ;; The reserved identifier is inaccessible to source code. Building syntax
    ;; lets a producer retain pending Scheme/macro expansion like any library.
    (define (recipe-producer key imports body loc)
      (let ((private (make-identifier-syntax '|#%lofi:producer| loc 'generated #f)))
        (parse-library
         (located-datum `(define-library ,key ,imports (export (rename ,private produce))
                                         (begin (def ,private (lambda () ,body)))) loc))))
    (define (parse-generation form)
      (let ((parts (proper-elements form)))
        (unless (and (= (length parts) 4) (eq? (form-head (caddr parts)) 'import))
          (error "generate-library requires a name, one import clause and one expression" (syntax-loc form)))
        (make-generation
         (recipe-producer (source-key (cadr parts)) (caddr parts) (cadddr parts) (syntax-loc form)))))
    (define (description-library description)
      (if (generation? description) (generation-producer description) description))
    (define (read-description path script?)
      (let ((forms (reader->syntax-list (file->reader path))))
        (cond ((and (= (length forms) 1) (eq? (form-head (car forms)) 'generate-library))
               (parse-generation (car forms)))
              ((and (= (length forms) 1) (eq? (form-head (car forms)) 'define-library))
               (parse-library (car forms)))
              (script? (syntax-list->lofi-library forms))
              (else (error "expected one Lofi library declaration or generation recipe" path)))))

    ;; ---- Explicit tools, providers and source context ----

    (define-record-type <generation-context>
      (new-generation-context runner providers) generation-context?
      (runner generation-runner)
      (providers generation-providers))
    (define (make-generation-context runner providers)
      (unless (and (string? runner) (or (not providers) (string? providers)))
        (error "generation context requires a runner path and an optional provider module path"))
      (new-generation-context runner providers))
    (define (write-artifact artifact path)
      (call-with-port (open-binary-output-file path)
        (lambda (port) (write-bytevector (artifact-bytes artifact) port))))
    (define (read-text path)
      (call-with-input-file path
        (lambda (port)
          (let read ((pieces '()) (piece (read-string 4096 port)))
            (if (eof-object? piece) (apply string-append (reverse pieces))
                (read (cons piece pieces) (read-string 4096 port)))))))
    (define (generator-command choice context binary packet)
      (list (tool-name "NODE" "node") (generation-runner context) binary packet (choice-path choice)
            (json->string (list->vector (map symbol->string (choice-key choice))))
            (or (generation-providers context) "")))
    (define (execute-generator artifact choice context directory)
      (let ((binary (string-append directory "/producer.wasm")) (packet (string-append directory "/library.json")))
        (write-artifact artifact binary)
        (let ((status (process-status (generator-command choice context binary packet) "." #f "lofi-generator")))
          (unless (zero? status)
            (error "Lofi library generation failed" (choice-loc choice) (choice-key choice)
                   (if (file-exists? (string-append packet ".error")) (read-text (string-append packet ".error")) status))))
        (receive-library-transfer (make-library-transfer-context) (call-with-input-file packet read-library-transfer))))

    ;; ---- One selected library value per build key ----

    (define-record-type <source-choice>
      (make-source-choice key path description value) source-choice?
      (key choice-key)
      (path choice-path)
      (description choice-description)
      (value choice-value set-choice-value!))
    (define (choice-loc choice)
      (lofi-library-loc (description-library (choice-description choice))))
    (define-record-type <preparation>
      (new-preparation directories choices context) preparation?
      (directories preparation-directories)
      (choices preparation-choices set-preparation-choices!)
      (context preparation-context))
    (define (supplied-choices libraries)
      (unless (list? libraries) (error "expected a library map"))
      (if (null? libraries) '()
          (let ((entry (car libraries)))
            (unless (and (pair? entry) (library-key? (car entry)) (lofi-library? (cdr entry)))
              (error "invalid library map entry" entry))
            (when (assoc (car entry) (cdr libraries)) (error "duplicate library key" (car entry)))
            (cons (cons (car entry) (make-source-choice (car entry) #f (cdr entry) (cdr entry)))
                  (supplied-choices (cdr libraries))))))
    (define (make-preparation directories libraries context)
      (unless (and (list? directories) (or (not context) (generation-context? context)))
        (error "expected search directories and an optional generation context"))
      (for-each (lambda (directory) (unless (string? directory) (error "expected a search directory" directory))) directories)
      (new-preparation directories (supplied-choices libraries) context))
    (define (library-path directory key)
      (let join ((parts key) (path directory))
        (if (null? parts) (string-append path ".sld")
            (join (cdr parts) (string-append path "/" (symbol->string (car parts)))))))
    (define (find-source key directories loc pending)
      (if (null? directories)
          (error "Lofi library not found" loc key (reverse (map choice-key pending)) (reverse (map choice-path pending)))
          (let ((path (library-path (car directories) key)))
            (if (file-exists? path) path (find-source key (cdr directories) loc pending)))))
    (define (record-choice key path description state)
      (let ((choice (make-source-choice key path description (and (lofi-library? description) description))))
        (set-preparation-choices! state (cons (cons key choice) (preparation-choices state))) choice))
    (define (choose-source key state loc pending)
      (let ((known (assoc key (preparation-choices state))))
        (if known (cdr known)
            (let* ((path (find-source key (preparation-directories state) loc pending))
                   (description (read-description path #f)) (library (description-library description)))
              (unless (equal? key (lofi-library-name library))
                (error "library name does not match import" (lofi-library-loc library) key path))
              (record-choice key path description state)))))
    (define (fresh-library-key base libraries)
      (let choose ((key base))
        (if (assoc key libraries) (choose (append key '(private))) key)))

    ;; ---- Independent maps share the active preparation chain ----

    (define (check-preparation-cycle choice pending loc)
      (when (member (choice-key choice) (map choice-key pending))
        (let* ((chain (reverse (cons choice pending)))
               (generated? (let visit ((steps chain))
                             (and (pair? steps) (or (generation? (choice-description (car steps))) (visit (cdr steps)))))))
          (error (if generated? "cyclic library preparation" "cyclic library import") loc
                 (map choice-key chain) (map choice-path chain)))))
    (define (collect-imports library state libraries pending)
      (let collect ((imports (lofi-library-imports library)) (libraries libraries))
        (if (null? imports) libraries
            (let ((import
                   (car imports)))
              (collect (cdr imports) (collect-key (lofi-import-provider import) state libraries pending
                                                  (lofi-import-loc import)))))))
    (define (collect-key key state libraries pending loc)
      (let ((choice (choose-source key state loc pending)))
        (check-preparation-cycle choice pending loc)
        (if (assoc key libraries) libraries
            (let* ((chain (cons choice pending)) (library (produce-choice choice state chain)))
              (collect-imports library state (cons (cons key library) libraries) chain)))))
    ;; The private adapter's ordinary call checks LofiLibrary nominally before
    ;; its token becomes the scalar execution ABI. It cannot capture body names.
    (define (generator-adapter key producer-key loc)
      (parse-library
       (located-datum
        `(define-library ,key
           (import
            (only ,producer-key produce)
            (only (lofi compiler builder) LofiLibrary library-token))
           (export run) (begin (def run (-> I64) (lambda () (library-token (ann (produce) LofiLibrary)))))) loc)))
    (define (generator-artifact choice state pending)
      (let* ((producer (generation-producer (choice-description choice)))
             (dependencies (collect-imports producer state '() pending))
             (libraries (collect-key '(lofi compiler builder) state dependencies pending (choice-loc choice)))
             (with-producer (cons (cons (choice-key choice) producer) libraries))
             (adapter-key (fresh-library-key '(lofi generation-adapter) with-producer))
             (adapter (generator-adapter adapter-key (choice-key choice) (choice-loc choice))))
        (compile (cons (cons adapter-key adapter) with-producer) (make-entry adapter-key 'run))))
    (define (produce-choice choice state pending)
      (or (choice-value choice)
          (let ((context (preparation-context state)))
            (unless context (error "generation requires an explicit execution context" (choice-loc choice)))
            (let* ((artifact (generator-artifact choice state pending))
                   (library (call-with-temp-dir "lofi-generation"
                                                (lambda (directory preserve) (execute-generator artifact choice context directory)))))
              (set-choice-value! choice library) library))))

    ;; ---- Public preparation and source compilation ----

    (define (prepare-library key directories libraries context)
      (unless (library-key? key) (error "expected a nonempty Lofi library key" key))
      (let* ((state (make-preparation directories libraries context)) (choice (choose-source key state #f '())))
        (produce-choice choice state (list choice))))
    (define (collect-libraries entry directories libraries context)
      (unless (entry? entry) (error "collect-libraries requires an entry"))
      (collect-key (entry-library entry) (make-preparation directories libraries context) '() '() #f))
    ;; An anonymous script has no lookup key while its imports are collected.
    ;; Choose its private map key afterward, so it cannot shadow a real import.
    (define (collect-anonymous-source library path state)
      (let* ((root (make-source-choice #f path library library))
             (libraries (collect-imports library state '() (list root)))
             (key (fresh-library-key '(lofi command) libraries)))
        (values key (cons (cons key library) libraries))))
    (define (collect-source-file path directories libraries context)
      (let* ((state (make-preparation directories libraries context))
             (description ((chromium-trace "lofi.parse" read-description) path #t))
             (library (description-library description))
             (key (lofi-library-name library)))
        (if (not key) (collect-anonymous-source library path state)
            (begin
              (when (assoc key (preparation-choices state))
                (error "source root conflicts with supplied library" (lofi-library-loc library) key))
              (record-choice key path description state)
              (values key (collect-key key state '() '() (lofi-library-loc library)))))))
    (define library-directories (make-parameter '()))
    (define generation-provider-module (make-parameter #f))
    (define command-program? (make-parameter #f))
    (define (raise-source-diagnostic failure)
      (let ((details (and (error-object? failure) (error-object-irritants failure))))
        (if (and (pair? details) (loc? (car details)))
            (apply strict-error (car details) (error-object-message failure) (cdr details)) (raise failure))))
    (define (source-file->core root path)
      (guard (failure (else (raise-source-diagnostic failure)))
        (let-values (((key libraries)
                      (collect-source-file path (append (library-directories) (list (string-append root "/src")))
                                           (list (cons '(lofi primitive) (make-primitive-library primitive-names)))
                                           (make-generation-context (string-append root "/scripts/run-lofi-generator.mjs")
                                                                    (generation-provider-module)))))
          ((chromium-trace "lofi.check" library-map->core) libraries key))))
    (define (check-command-result core)
      (let ((body (program-body core)))
        (when (and (command-program?) (not (memq (resolve (program-type core)) '(Unit I32 I64 Never))))
          (strict-error (node-loc body) "command result must be Unit, I32, I64 or Never" (program-type core)))))
    (define (source-file->wasm root path . exports)
      (let ((core (source-file->core root path)))
        (check-command-result core)
        (let ((concrete (apply (chromium-trace "lofi.specialize" prepare-generation) core exports)))
          ((chromium-trace "lofi.emit-wasm" strict-core->wasm) concrete))))
    (define (source-file->wat-file root path output . exports)
      (let ((module (apply source-file->wasm root path exports)))
        (call-with-output-file output (lambda (port) (write-wasm module port))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-source-driver)
    (import
     (lofi host test-utils))
    (begin
      (define (test-generation text)
        (parse-generation (car (reader->syntax-list (string->reader "recipe.sld" text)))))
      (define (test-recipe-grammar)
        (let ((producer (generation-producer (test-generation "(generate-library (test a) (import) 42)"))))
          (expect (lofi-library-name producer) '(test a))
          (expect (length (lofi-library-declarations producer)) 1)
          (expect (length (lofi-library-bindings producer)) 1))
        (for-each
         (lambda (text)
           (expect (guard (failure (else #t)) (test-generation text) #f) #t))
         '("(generate-library () (import) 42)" "(generate-library (test a) (export) 42)"
           "(generate-library (test a) (import) 1 2)" "(generate-library (test a) (import))"
           "(generate-library (test a) (import) (def x 42))" "(generate-library (test a) (import) 42 . tail)")))
      (define (test-source-read-diagnostic)
        (let ((path "tests/lofi/unclosed-library.sld.txt"))
          (for-each
           (lambda (read-source)
             (expect (guard (failure ((error-object? failure) (error-object-message failure)))
                       (read-source) #f)
                     (string-append path ":4:1: cannot parse Lofi source: expected closing delimiter ')'")))
           (list (lambda () (collect-source-file path '() '() (make-generation-context "unused" #f)))
                 (lambda () (source-file->core "." path))))))
      (define (test-source-driver)
        (run-test test-recipe-grammar)
        (run-test test-source-read-diagnostic))))
   (else)))
