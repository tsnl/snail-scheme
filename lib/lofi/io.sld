;; Console text and files. The host implements `console` and `fs` by
;; default; a handler can replace either, for example to capture output or
;; to serve files from memory in a test.
(define-library (lofi io)
  (export
   console
   console-write
   console-read
   write-char
   write-string
   newline
   write-line
   display
   read-line
   fs
   read-file
   write-file
   file-exists?
   command-line)
  (import
   (lofi base))
  (begin

    ;; ---- Console effect ----

    (effect console
      ((console-write (-> Char Unit))
       (console-read (-> I32)))
      (host "snail.library"
            ((console-write "snail:io/console-write")
             (console-read "snail:io/console-read"))))

    ;; ---- Text input ----

    ;; The next line of standard input without its newline, or None at the
    ;; end of input.
    (: read-line (-> (Option String) ! console))
    (define (read-line)
      (let loop ((chars (Nil)))
        (let ((code (console-read)))
          (cond ((and (= code -1) (null? chars)) (None))
                ((or (= code -1) (= code 10)) (Some (list->string (reverse chars))))
                (else (loop (Cons (i32->char code) chars)))))))

    ;; ---- Text output ----

    (: write-char (-> Char Unit ! console))
    (define (write-char char)
      (console-write char))

    (: write-string (-> String Unit ! console))
    (define (write-string text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (console-write (string-ref text index))
          (loop (+ index 1)))))

    (: newline (-> Unit ! console))
    (define (newline)
      (console-write #\newline))

    (: write-line (-> String Unit ! console))
    (define (write-line text)
      (write-string text)
      (newline))

    (: display (All (T) (requires (Show T)) (-> T Unit ! console)))
    (define (display value)
      (write-string (show value)))

    ;; ---- Files ----

    ;; A path is sent one scalar at a time before the operation that uses
    ;; it. Ports are runtime handles; a closed port must not be used again.
    (effect fs
      ((path-begin (-> Unit))
       (path-character (-> Char Unit))
       (path-exists (-> I32))
       (open-input (-> I32))
       (open-output (-> I32))
       (port-read (-> I32 I32))
       (port-write (-> I32 Char Unit))
       (port-close (-> I32 Unit)))
      (host "snail.library"
            ((path-begin "snail:io/path-begin")
             (path-character "snail:io/path-character")
             (path-exists "snail:io/file-exists")
             (open-input "snail:io/open-input-file")
             (open-output "snail:io/open-output-file")
             (port-read "snail:io/read-character")
             (port-write "snail:io/write-character")
             (port-close "snail:io/close"))))

    (: send-path (-> String Unit ! fs))
    (define (send-path path)
      (path-begin)
      (let loop ((index 0))
        (when (< index (string-length path))
          (path-character (string-ref path index))
          (loop (+ index 1)))))

    (: file-exists? (-> String Bool ! fs))
    (define (file-exists? path)
      (send-path path)
      (= (path-exists) 1))

    ;; The whole file as text; the runtime fails the program if it cannot
    ;; be read.
    (: read-file (-> String String ! fs))
    (define (read-file path)
      (send-path path)
      (let ((port (open-input)))
        (let loop ((chars (Nil)))
          (let ((code (port-read port)))
            (if (= code -1)
                (begin (port-close port) (list->string (reverse chars)))
                (loop (Cons (i32->char code) chars)))))))

    (: write-file (-> String String Unit ! fs))
    (define (write-file path text)
      (send-path path)
      (let ((port (open-output)))
        (let loop ((index 0))
          (when (< index (string-length text))
            (port-write port (string-ref text index))
            (loop (+ index 1))))
        (port-close port)))

    ;; ---- Command line ----

    ;; The program's arguments, starting with its own path. They never change
    ;; while it runs, so reading them is total.
    (extern argument-count "snail.library" "snail:process/argument-count" (-> I32))
    (extern argument-length "snail.library" "snail:process/argument-length" (-> I32 I32))
    (extern argument-character "snail.library" "snail:process/argument-character" (-> I32 I32 Char))

    (: command-line (-> (List String)))
    (define (command-line)
      (map (lambda (index)
             (let ((argument (i64->i32 index)))
               (string-generate (i32->i64 (argument-length argument))
                                (lambda (position) (argument-character argument (i64->i32 position))))))
           (iota (i32->i64 (argument-count)))))

    ))
