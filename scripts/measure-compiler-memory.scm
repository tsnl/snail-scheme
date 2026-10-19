;; Diagnostic only: each snapshot forces Chibi collection. These are retained
;; objects at pass boundaries, not clean timings or the process-group peak.
(import
 (scheme base)
 (scheme file)
 (scheme read)
 (scheme process-context)
 (scheme time)
 (only (chibi heap-stats) heap-stats)
 (only (chibi filesystem) create-directory*)
 (only (chibi string) string-prefix?)
 (only (lofi host process) write-json)
 (lofi host chromium-trace)
 (lofi host wasm)
 (lofi compiler source-driver)
 (lofi compiler specialize)
 (lofi compiler emit-wasm))

;; ---- Retained objects and resident pages ----

(define arguments (cdr (command-line)))
(unless (= (length arguments) 3)
  (error "usage: measure-compiler-memory.scm ROOT SOURCE OUTPUT-DIRECTORY"))
(define directory (car (cddr arguments)))
(define snapshots '())
(create-directory* directory)

(define (resident-kib)
  (call-with-input-file "/proc/self/status"
    (lambda (port)
      (let find ((line (read-line port)))
        (cond ((eof-object? line) #f)
              ((string-prefix? "VmRSS:" line) (read (open-input-string (substring line 6 (string-length line)))))
              (else (find (read-line port))))))))
(define (snapshot phase)
  (let* ((objects (heap-stats))
         (counts (map (lambda (entry) `((type . ,(symbol->string (car entry))) (count . ,(cdr entry)))) objects))
         (record `((phase . ,phase) (jiffy . ,(current-jiffy))
                   (resident_kib . ,(resident-kib)) (objects . ,(list->vector counts)))))
    (set! snapshots (cons record snapshots))
    (write-json (string-append directory "/memory.json")
                `((kind . "forced-gc-diagnostic") (source . ,(cadr arguments))
                  (jiffies_per_second . ,(jiffies-per-second))
                  (snapshots . ,(list->vector (reverse snapshots)))))))

;; ---- Ordinary compiler passes, with collections between them ----

(with-chromium-trace-to
 (string-append directory "/compile.trace.json")
 (lambda ()
   (snapshot "loaded")
   (let* ((core (source-file->core (car arguments) (cadr arguments)))
          (checked (snapshot "checked"))
          (concrete (prepare-generation core))
          (specialized (snapshot "specialized"))
          (module (strict-core->wasm concrete))
          (emitted (snapshot "emitted")))
     (call-with-output-file (string-append directory "/source.wat")
       (lambda (port) (write-wasm module port)))
     (snapshot "written"))))
