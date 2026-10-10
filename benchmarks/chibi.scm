;; Run the canonical CPU, memory, and I/O benchmarks with Chibi Scheme.
;; Benchmark bodies are unchanged. Chibi supplies the R7RS operations;
;; the I/O adapter converts its native search cursors to character indices.
;; Chibi 0.12's (scheme time) clock rounds wall-clock time to milliseconds.
;; GC is omitted: its public counters cannot satisfy our reclamation check.
(import (scheme base) (scheme file) (scheme read) (scheme write)
        (scheme process-context))

;; ---- Import adaptation ----

(define allowed-libraries
  '((scheme base) (scheme write) (scheme time) (scheme process-context)
    (scheme file) (snail-scheme runtime)))

(define (adapt-import form)
  (unless (and (pair? form) (eq? (car form) 'import)
               (every-allowed? (cdr form)))
    (error "unsupported benchmark imports" form))
  (cons 'import
        (map (lambda (name)
               (if (equal? name '(snail-scheme runtime))
                   '(rename (only (chibi string) string-contains
                                  string-index->cursor string-cursor->index)
                            (string-contains chibi-string-contains))
                   name))
             (cdr form))))

(define (every-allowed? libraries)
  (or (null? libraries)
      (and (member (car libraries) allowed-libraries)
           (every-allowed? (cdr libraries)))))

(define search-adapter
  '(define (string-contains text needle . starts)
     (let* ((start (if (null? starts) 0 (car starts)))
            (cursor (string-index->cursor text start))
            (found (chibi-string-contains text needle cursor)))
       (and found (string-cursor->index text found)))))

;; ---- Program copying ----

(define (write-form form output)
  (write form output)
  (newline output))

(define (copy-program input output)
  (let ((imports (read input)))
    (write-form (adapt-import imports) output)
    (when (member '(snail-scheme runtime) (cdr imports))
      (write-form search-adapter output)))
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

(define (main arguments)
  (unless (= (length arguments) 3)
    (error "usage: chibi.scm SOURCE OUTPUT"))
  (write-program (cadr arguments) (car (cddr arguments))))

(main (command-line))
