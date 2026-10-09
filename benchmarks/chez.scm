;; Compile the canonical benchmarks with Chez's safe, native-code compiler.
;; Only the import form is replaced; benchmark algorithms remain unchanged.
(import (chezscheme))

;; These forms are prepended to each generated R6RS program. Keep the adapters
;; here with their limitations, rather than maintaining second benchmark copies.
(define adapter-forms
  '((import (rename (chezscheme)
                    (define-record-type chez-define-record-type)
                    (error chez-error)))

    ;; The benchmarks use immutable records with every field in constructor order.
    (define-syntax define-record-type
      (lambda (form)
        (syntax-case form ()
          ((_ name (constructor argument ...) predicate (field accessor) ...)
           (equal? (syntax->datum #'(argument ...)) (syntax->datum #'(field ...)))
           #'(chez-define-record-type (name constructor predicate)
                                      (fields (immutable field accessor) ...)))
          (_ (syntax-error form "unsupported benchmark record definition")))))

    (define (error message . irritants)
      (apply chez-error #f message irritants))

    (define (exact-integer? value)
      (and (integer? value) (exact? value)))

    (define (time-nanoseconds time)
      (+ (* (time-second time) 1000000000) (time-nanosecond time)))

    (define (current-jiffy)
      (time-nanoseconds (current-time 'time-monotonic)))

    (define (jiffies-per-second) 1000000000)

    (define (read-string count . ports)
      (get-string-n (if (null? ports) (current-input-port) (car ports)) count))

    ;; Chez 10.4.1 has no built-in substring search. This checked character loop is
    ;; compiled to native code; Snail's runtime instead uses Rust's str::find.
    (define (substring-at? text needle start)
      (let loop ((index 0))
        (or (= index (string-length needle))
            (and (char=? (string-ref text (+ start index)) (string-ref needle index))
                 (loop (+ index 1))))))

    (define (string-contains text needle . starts)
      (let ((limit (- (string-length text) (string-length needle))))
        (let loop ((start (if (null? starts) 0 (car starts))))
          (cond ((> start limit) #f)
                ((substring-at? text needle start) start)
                (else (loop (+ start 1)))))))

    ;; Request a full collection, matching the scope of Snail's explicit GC.
    ;; Chez's moving, generational policy and allocation accounting still differ.
    (define (collect-garbage)
      (collect (collect-maximum-generation)))

    ;; Only fields used by gc.scm are supplied. Index 4 counts reclaimed BYTES,
    ;; whereas Snail counts objects; the benchmark merely checks positive progress.
    ;; Unavailable maxima/object counts are #f, never invented measurements.
    (define (gc-statistics)
      (let ((stats (statistics)))
        (vector (sstats-gc-count stats) (time-nanoseconds (sstats-gc-real stats))
                #f #f (sstats-gc-bytes stats) #f #f)))))

;; Read Scheme forms with Chez's reader instead of stripping imports as text.
;; Restrict the replaced import to the libraries these benchmarks actually use.

(define allowed-libraries
  '((scheme base) (scheme write) (scheme time) (scheme process-context)
    (scheme file) (snail-scheme runtime)))

(define (check-import form)
  (unless (and (pair? form) (eq? (car form) 'import)
               (for-all (lambda (name) (member name allowed-libraries)) (cdr form)))
    (error 'chez-benchmark "unsupported benchmark imports" form)))

(define (write-form form output)
  (write form output)
  (newline output))

(define (copy-program input output)
  (check-import (read input))
  (for-each (lambda (form) (write-form form output)) adapter-forms)
  (let loop ((form (read input)))
    (unless (eof-object? form)
      (write-form form output)
      (loop (read input)))))

(define (write-program source destination)
  (when (file-exists? destination) (delete-file destination))
  (call-with-input-file source
    (lambda (input)
      (call-with-output-file destination
        (lambda (output) (copy-program input output))))))

(define (compile-benchmark source destination)
  (let ((program (string-append destination ".sps")))
    (write-program source program)
    (parameterize ((optimize-level 2) (compile-file-message #f))
      (compile-program program destination))))

(define (main arguments)
  (unless (= (length arguments) 3)
    (error 'chez-benchmark "usage: chez.scm SOURCE OUTPUT"))
  (compile-benchmark (cadr arguments) (caddr arguments)))

(main (command-line))
