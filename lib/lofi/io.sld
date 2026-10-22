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
   read-bytes
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
       (port-read-byte (-> I32 I32))
       (port-write (-> I32 String Unit))
       (port-close (-> I32 Unit)))
      (host "snail.library"
            ((path-begin "snail:io/path-begin")
             (path-character "snail:io/path-character")
             (path-exists "snail:io/file-exists")
             (open-input "snail:io/open-input-file")
             (open-output "snail:io/open-output-file")
             (port-read "snail:io/read-character")
             (port-read-byte "snail:io/read-byte")
             (port-write "snail:io/write-string")
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
        (let ((chars (drain (lambda () (let ((code (port-read port))) (if (= code -1) (None) (Some (i32->char code))))))))
          (port-close port)
          (vector->string chars))))

    ;; The whole file as bytes, for binary files such as images.
    (: read-bytes (-> String Bytes ! fs))
    (define (read-bytes path)
      (send-path path)
      (let ((port (open-input)))
        (let ((bytes (drain (lambda () (let ((byte (port-read-byte port))) (if (= byte -1) (None) (Some (i32->u8 byte))))))))
          (port-close port)
          bytes)))

    ;; Everything `next` gives until it gives None. Items gather a chunk at a
    ;; time, and the chunks are joined at the end, so a file of millions of
    ;; characters, such as a generated library, costs a few bytes for each
    ;; rather than a list cell.
    (define chunk-size 4096)

    (: drain (All (T e) (-> (-> (Option T) ! e) (Vector T) ! e)))
    (define (drain next)
      (let loop ((chunks (Nil)))
        (let ((chunk (next-chunk next)))
          (if (< (vector-length chunk) chunk-size)
              (joined (vector-from (reverse (Cons chunk chunks))))
              (loop (Cons chunk chunks))))))

    ;; Up to `chunk-size` items, fewer only at the end.
    (: next-chunk (All (T e) (-> (-> (Option T) ! e) (Vector T) ! e)))
    (define (next-chunk next)
      (let loop ((items (Nil)) (count 0))
        (if (= count chunk-size)
            (vector-from (reverse items))
            (match (next)
              ((Some item) (loop (Cons item items) (+ count 1)))
              ((None) (vector-from (reverse items)))))))

    ;; Every chunk but the last is full, so item i lies in chunk i / size.
    (: joined (All (T) (-> (Vector (Vector T)) (Vector T))))
    (define (joined chunks)
      (let* ((last-chunk (vector-ref chunks (- (vector-length chunks) 1)))
             (count (+ (* chunk-size (- (vector-length chunks) 1)) (vector-length last-chunk))))
        (vector-generate count (lambda (index) (vector-ref (vector-ref chunks (quotient index chunk-size)) (remainder index chunk-size))))))

    (: vector-from (All (T) (-> (List T) (Vector T))))
    (define (vector-from items)
      (if (null? items) (vector-generate 0 (lambda (index) (panic "empty"))) (list->vector items)))

    (: write-file (-> String String Unit ! fs))
    (define (write-file path text)
      (send-path path)
      (let ((port (open-output)))
        (port-write port text)
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
