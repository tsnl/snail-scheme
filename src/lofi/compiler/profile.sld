;; Chibi-only diagnostics: instrument private library copies, never product sources.
(define-library (lofi compiler profile)
  (export instrument-compiler profile-operation profile-phase source-label)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (scheme process-context)
   (scheme read)
   (scheme time)
   (scheme write)
   (lofi compiler source)
   (lofi host chromium-trace)
   (only (lofi host process) path-join write-json))
  (begin

    ;; ---- Bounded source-unit spans and optional helper totals ----

    (define current-phase (make-parameter "source preparation"))
    (define totals '())
    (define active-timer #f)
    (define helpers? (equal? (get-environment-variable "SNAIL_PROFILE_HELPERS") "1"))
    (define (source-label operation location)
      (if (not location) operation
          (string-append operation " " (loc-filename location) ":"
                         (number->string (loc-line location)) ":"
                         (number->string (loc-column location)))))
    (define (operation-total operation)
      (let* ((key (string-append (current-phase) ":" operation)) (entry (assoc key totals)))
        (if entry (cdr entry)
            (let ((total (vector 0 0 0)))
              (set! totals (cons (cons key total) totals)) total))))
    ;; Self time excludes measured children only. Timers include raised trials;
    ;; dynamic-wind restores nesting before an enclosing guard handles failure.
    (define (finish-timer total parent children start)
      (let ((elapsed (max 0 (- (current-jiffy) start))))
        (set! active-timer parent)
        (when parent (vector-set! parent 0 (+ (vector-ref parent 0) elapsed)))
        (vector-set! total 1 (+ (vector-ref total 1) elapsed))
        (vector-set! total 2 (+ (vector-ref total 2) (max 0 (- elapsed (vector-ref children 0)))))))
    (define (timed-call operation procedure arguments)
      (let ((total (operation-total operation)) (parent active-timer)
            (children (vector 0)) (start (current-jiffy)))
        (vector-set! total 0 (+ (vector-ref total 0) 1))
        (dynamic-wind
            (lambda () (set! active-timer children))
            (lambda () (apply procedure arguments))
            (lambda () (finish-timer total parent children start)))))
    (define (profile-operation operation procedure label)
      (if (and (not label) (not helpers?)) procedure
          (lambda arguments
            (timed-call operation
                        (if label (chromium-trace (apply label arguments) procedure) procedure)
                        arguments))))
    (define (total-description entry)
      (let ((total (cdr entry)) (frequency (jiffies-per-second)))
        `((operation . ,(car entry)) (calls . ,(vector-ref total 0))
          (inclusive_seconds . ,(/ (inexact (vector-ref total 1)) frequency))
          (self_seconds . ,(/ (inexact (vector-ref total 2)) frequency)))))
    (define (save-totals)
      (write-json (path-join (get-environment-variable "SNAIL_PROFILE_DIRECTORY") "operations.json")
                  (list->vector (map total-description totals))))
    (define (profile-phase name procedure)
      (let ((traced (chromium-trace name procedure)))
        (lambda arguments
          (parameterize ((current-phase name))
            (let ((parent active-timer))
              (call-with-values (lambda () (apply traced arguments))
                (lambda results
                  (unless (eq? active-timer parent) (error "profiling timer did not unwind" name))
                  (save-totals) (apply values results))))))))

    ;; ---- Explicit instrumentation sites ----

    ;; Spans identify source units. Helpers use aggregate timers in hotspots
    ;; mode; putting every lookup in the trace would obscure the useful spans.
    (define recipes
      '(("lofi/compiler/emit-wasm.sld"
         (emit-function (node-loc (function-source function)))
         (emit-entry (node-loc (prepared-body program)))
         (prepare-activation #t)
         (new-local #f) (layout! #f) (emit-call-rule #f) (emit-data-operation #f))
        ("lofi/compiler/infer.sld"
         (check-initializer! (node-loc (source-initializer binding)))
         (generalize-group! (node-loc (source-initializer (car group))))
         (check-skolem-escape #f) (finish-declaration-check! #t)
         (settle-summary-obligations! #t) (plan-bindings #t)
         (check-obligations #f))
        ("lofi/compiler/specialize.sld"
         (activation-value-index #f) (typed-concrete-type #f) (specialize-as #f)
         (resolve-reference #f) (request-function #f) (request-value #f) (concrete #f))
        ("lofi/compiler/overloads.sld"
         (improve-overloads! #f) (select-overload-view #f) (compatible? #f))
        ("lofi/compiler/types.sld" (generalize #f))))
    (define (operation-label operation parameters location)
      (and location
           `(lambda ,parameters
              ,(if (eq? location #t) (symbol->string operation)
                   `(source-label ,(symbol->string operation) ,location)))))
    (define (instrument-definition form recipe)
      (let* ((operation (caadr form)) (parameters (cdadr form))
             (location (cadr recipe)))
        `(define ,operation
           (profile-operation ,(symbol->string operation)
                              (lambda ,parameters ,@(cddr form))
                              ,(operation-label operation parameters location)))))
    (define (instrument-form form sites counts)
      (cond ((not (pair? form)) form)
            ((memq (car form) '(define-library begin))
             (map (lambda (form) (instrument-form form sites counts)) form))
            ((eq? (car form) 'import) (append form '((lofi compiler profile))))
            ((and (eq? (car form) 'define) (pair? (cadr form)) (assq (caadr form) sites))
             (let ((entry (assq (caadr form) counts)))
               (set-cdr! entry (+ 1 (cdr entry)))
               (instrument-definition form (assq (caadr form) sites))))
            (else form)))
    (define (read-library filename)
      (call-with-input-file filename
        (lambda (port)
          (let ((library (read port)))
            (unless (and (pair? library) (eq? (car library) 'define-library) (eof-object? (read port)))
              (error "profiling requires exactly one library" filename)) library))))
    (define (instrument-library root overlay recipe)
      (let* ((file (car recipe)) (sites (cdr recipe))
             (counts (map (lambda (site) (cons (car site) 0)) sites))
             (library (instrument-form (read-library (path-join root "src" file)) sites counts)))
        (for-each (lambda (entry)
                    (unless (= (cdr entry) 1) (error "profiling site changed" file entry))) counts)
        (call-with-output-file (path-join overlay file)
          (lambda (port) (write library port) (newline port)))
        `((path . ,file) (operations . ,(list->vector (map (lambda (site) (symbol->string (car site))) sites))))))
    (define (instrument-compiler root overlay)
      (write-json (path-join overlay "sites.json")
                  (list->vector (map (lambda (recipe) (instrument-library root overlay recipe)) recipes)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-compiler-profile)
    (import
     (lofi host test-utils)
     (chibi temp-file)
     (only (chibi filesystem) create-directory)
     (only (lofi host process) write-text read-text))
    (begin
      (define (test-profile-values)
        (let* ((called 0)
               (operation (profile-operation "values" (lambda () (set! called (+ called 1)) (values 1 2)) #f))
               (empty (profile-operation "empty" (lambda () (values)) #f)))
          (expect (call-with-values operation list) '(1 2))
          (expect (call-with-values empty list) '())
          (expect called 1)
          (expect (vector-ref (operation-total "values") 0) 1)))
      (define (test-profile-unwinding)
        (let* ((failure (list 'trial-failure))
               (inner (profile-operation "inner" (lambda () (raise failure)) #f))
               (outer (profile-operation "outer" (lambda () (inner)) #f)))
          (expect (eq? failure (guard (caught (else caught)) (outer))) #t)
          (expect active-timer #f)
          (expect (vector-ref (operation-total "inner") 0) 1)
          (expect (vector-ref (operation-total "outer") 0) 1)
          (expect ((profile-operation "after" (lambda () 42) #f)) 42)
          (expect active-timer #f)))
      (define (test-profile-disabled)
        (let ((procedure (lambda () 42)))
          (set! helpers? #f)
          (expect (eq? procedure (profile-operation "disabled" procedure #f)) #t)
          (set! helpers? #t)))
      (define (test-profile-sites)
        (call-with-temp-dir
         "compiler-profile"
         (lambda (directory preserve)
           (create-directory (path-join directory "src"))
           (create-directory (path-join directory "overlay"))
           (for-each (lambda (count) (test-site-count directory count)) '(0 1 2)))))
      (define (test-site-count directory count)
        (let* ((definition '(define (worker value) value))
               (source `(define-library (unit) (import
                                                (scheme base)) (begin ,@(make-list count definition))))
               (file (path-join directory "src/unit.sld")) (text (open-output-string)))
          (write source text) (write-text file (get-output-string text))
          (expect (guard (failure (else 'rejected))
                    (instrument-library directory (path-join directory "overlay") '("unit.sld" (worker #t)))
                    'accepted) (if (= count 1) 'accepted 'rejected))
          (expect (read-text file) (get-output-string text))))
      (define (test-compiler-profile)
        (let ((old totals) (enabled? helpers?))
          (dynamic-wind
              (lambda () (set! totals '()) (set! helpers? #t))
              (lambda ()
                (run-test test-profile-values)
                (run-test test-profile-unwinding)
                (run-test test-profile-disabled)
                (run-test test-profile-sites))
              (lambda () (set! totals old) (set! helpers? enabled?)))))))
   (else)))
