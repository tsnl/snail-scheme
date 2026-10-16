;; Concrete text input and output. Rust owns file payloads; each wrapper's
;; shared Refs preserve pending input and explicit close across aliases. No GC
;; finalizer owns these files. Standard streams are borrowed; cleanup closes files.
(define-library (lofi io)
  (export InputPort OutputPort LineResult end-of-file line line-text eof-object?
          CharacterResult character-end character-value character-text character-end?
          read-char peek-char current-input-port
          file-exists? delete-file open-input-file close-input-port
          call-with-input-file read-line open-output-file close-output-port
          call-with-output-file current-output-port output-port=?
          write-char write-string write-i64 newline)
  (import (lofi base))

  ;; ---- Scalar resource boundary ----

  (begin
    (def OutputPort (datatype ()
                              (output-port (handle (Ref I32) output-handle))))
    (def InputPort (datatype ()
                             (input-port (handle (Ref I32) input-handle)
                                         (packet (Ref I64) input-packet))))
    (def LineResult (datatype () (end-of-file) (line (text String line-text))))
    (def CharacterResult (datatype ()
                                   (character-end) (character-value (text Char character-text))))
    (define-extern path-begin "snail.library" "snail:io/path-begin" (-> Unit))
    (define-extern path-character "snail.library" "snail:io/path-character" (-> Char Unit))
    (define-extern path-exists "snail.library" "snail:io/file-exists" (-> I32))
    (define-extern path-delete "snail.library" "snail:io/delete-file" (-> Unit))
    (define-extern path-open-output "snail.library" "snail:io/open-output-file" (-> I32))
    (define-extern path-open-input "snail.library" "snail:io/open-input-file" (-> I32))
    (define-extern port-read "snail.library" "snail:io/read-character" (-> I32 I32))
    (define-extern port-peek "snail.library" "snail:io/peek-character" (-> I32 I32))
    (define-extern port-packet "snail.library" "snail:io/read-packet" (-> I32 I64))
    (define-extern port-write "snail.library" "snail:io/write-character" (-> I32 Char Unit))
    (define-extern port-close "snail.library" "snail:io/close" (-> I32 Unit))
    (define-extern standard-output-handle "snail.library" "snail:io/standard-output" (-> I32))
    (define-extern standard-input-handle "snail.library" "snail:io/standard-input" (-> I32))
    (define-extern port-check-output "snail.library" "snail:io/check-output" (-> I32 Unit))

    ;; This singleton borrows stdout. Its reserved scalar ID never names an
    ;; owned file, and neither explicit close nor trap cleanup closes the stream.
    ;; Current output is fixed here; dynamic rebinding is not implemented.
    (def standard-output
         (output-port (ref (standard-output-handle))))

    (def current-output-port (-> OutputPort)
         (lambda () standard-output))

    ;; All aliases share the native reader and its peek buffer. Explicit close
    ;; preserves the borrowed handle, just as it does for standard output.
    (def standard-input
         (input-port (ref (standard-input-handle)) (ref (ann 0 I64))))

    (def current-input-port (-> InputPort)
         (lambda () standard-input))

    (def output-port=? (-> OutputPort OutputPort Bool)
         (lambda (left right) (ref-eq? (output-handle left) (output-handle right))))

    ;; No user callback occurs between begin and the consuming file operation.
    ;; UTF-8 encoding happens in Rust; String traversal stays in Lofi.

    (def stage-path (-> String Unit)
         (lambda (pathname)
           (begin
             (path-begin)
             (begin (let count (string-length pathname))
                    (begin
                      (def loop
                           (lambda (index)
                             (if (= index count)
                                 (unit)
                                 (begin
                                   (path-character (string-ref pathname index))
                                   (loop (+ index (ann 1 I64)))
                                   (unit)))))
                      (loop (ann 0 I64)))))))

    (def file-exists? (-> String Bool)
         (lambda (pathname)
           (begin
             (stage-path pathname)
             (i32-eq (path-exists) (ann 1 I32)))))

    (def delete-file (-> String Unit)
         (lambda (pathname)
           (begin (stage-path pathname) (path-delete))))

    (def open-output-file (-> String OutputPort)
         (lambda (pathname)
           (begin
             (stage-path pathname)
             (output-port (ref (path-open-output))))))

    (def open-input-file (-> String InputPort)
         (lambda (pathname)
           (begin
             (stage-path pathname)
             (input-port (ref (path-open-input)) (ref (ann 0 I64))))))

    ;; ---- Explicit close and a normally returning callback ----

    (def close-output-port (-> OutputPort Unit)
         (lambda (port)
           (close-handle (output-handle port))))

    (def close-input-port (-> InputPort Unit)
         (lambda (port)
           (begin
             (ref-set! (input-packet port) (ann 0 I64))
             (close-handle (input-handle port)))))

    (def close-handle (-> (Ref I32) Unit)
         (lambda (cell)
           (begin (let handle (ref-get cell))
                  (if (if (i32-eq handle (ann -1 I32)) #t
                          (if (i32-eq handle (ann -2 I32)) #t (i32-eq handle (ann -3 I32))))
                      (unit)
                      (begin
                        (ref-set! cell (ann -1 I32))
                        (port-close handle)
                        (unit))))))

    (def call-with-output-file (All (T) (-> String (-> OutputPort T) T))
         (lambda (pathname procedure)
           (begin (let port (open-output-file pathname))
                  (begin (let result (procedure port))
                         (begin
                           (close-output-port port)
                           result)))))

    (def call-with-input-file (All (T) (-> String (-> InputPort T) T))
         (lambda (pathname procedure)
           (begin (let port (open-input-file pathname))
                  (begin (let result (procedure port))
                         (begin
                           (close-input-port port)
                           result)))))

    ;; ---- One owned-file cursor serves character, line and datum readers ----

    ;; Rust constructs nonzero packets: up to seven ASCII code+1 byte lanes,
    ;; -1 for EOF, or one validated Unicode scalar as -code-2. Seven lanes fit
    ;; below the sign bit, and code+1 distinguishes NUL from exhausted lanes.
    ;; Only private owned-file handles have pending guest input. Borrowed stdin
    ;; keeps the scalar Rust cursor so direct foreign reads share its lookahead.

    (def pending-input (-> InputPort I64)
         (lambda (port)
           (begin
             (let packet (ref-get (input-packet port)))
             (if (= packet (ann 0 I64))
                 (begin
                   (let filled (port-packet (ref-get (input-handle port))))
                   (ref-set! (input-packet port) filled)
                   filled)
                 packet))))

    (def packet-code (-> I64 I32)
         (lambda (packet)
           (if (< packet (ann 0 I64))
               (if (= packet (ann -1 I64)) (ann -1 I32)
                   (i64->i32 (- (ann -2 I64) packet)))
               (i64->i32 (- (i64-bitwise-and packet (ann 255 I64)) (ann 1 I64))))))

    ;; Check the shared handle before consulting pending input: close must make
    ;; cached characters and EOF inaccessible. Reading EOF clears it just like
    ;; scalar read; a later read can observe a file that has grown since EOF.

    (def read-input-code (-> InputPort I32)
         (lambda (port)
           (begin
             (let handle (ref-get (input-handle port)))
             (if (i32-lt handle (ann 0 I32))
                 (port-read handle)
                 (begin
                   (let packet (pending-input port))
                   (ref-set! (input-packet port)
                             (if (> packet (ann 0 I64))
                                 (i64-shift-right/logical packet (ann 8 I64)) (ann 0 I64)))
                   (packet-code packet))))))

    (def peek-input-code (-> InputPort I32)
         (lambda (port)
           (begin
             (let handle (ref-get (input-handle port)))
             (if (i32-lt handle (ann 0 I32))
                 (port-peek handle)
                 (packet-code (pending-input port))))))

    (def character-end? (-> CharacterResult Bool)
         (lambda (result)
           (match result ((character-end) #t) ((character-value text) #f))))

    (def character-result (-> I32 CharacterResult)
         (lambda (code)
           (if (i32-eq code (ann -1 I32))
               (character-end)
               (character-value (integer->char (i32->i64 code))))))

    (def read-char (-> InputPort CharacterResult)
         (lambda (port)
           (character-result (read-input-code port))))

    (def peek-char (-> InputPort CharacterResult)
         (lambda (port)
           (character-result (peek-input-code port))))

    ;; ---- Complete lines distinguish an empty line from end of file ----

    (def eof-object? (-> LineResult Bool)
         (lambda (result)
           (match result ((end-of-file) #t) ((line text) #f))))

    (def read-line (-> InputPort LineResult)
         (lambda (port)
           (begin
             (let code (read-input-code port))
             (if (i32-eq code (ann -1 I32))
                 (end-of-file)
                 (line (read-line-text port code (make-string (ann 0 I64)) (ann 0 I64)))))))
    ;; Rust validates UTF-8; the shared input cursor owns lookahead. CR, LF,
    ;; and CRLF terminate one line. A non-LF lookahead belongs to the next read.

    (def consume-line-feed (-> InputPort Unit)
         (lambda (port)
           (if (i32-eq (peek-input-code port) (ann 10 I32))
               (begin (read-input-code port) (unit)) (unit))))

    (def read-line-text (-> InputPort I32 String I64 String)
         (lambda (port code buffer count)
           (if (if (i32-eq code (ann -1 I32))
                   #t
                   (if (i32-eq code (ann 10 I32)) #t (i32-eq code (ann 13 I32))))
               (begin
                 (if (i32-eq code (ann 13 I32))
                     (begin (consume-line-feed port) (unit))
                     (unit))
                 (if (= count (string-length buffer)) buffer (substring buffer (ann 0 I64) count)))
               (begin
                 (let buffer (line-capacity buffer count))
                 (string-set! buffer count (integer->char (i32->i64 code)))
                 (read-line-text port (read-input-code port) buffer (+ count (ann 1 I64)))))))
    ;; Only the first count characters are initialized text. Doubling capacity
    ;; bounds total copying by a geometric series; no character needs a GC node.
    ;; The final substring trims spare capacity once, and exact fits reuse it.

    (def line-capacity (-> String I64 String)
         (lambda (buffer count)
           (if (< count (string-length buffer))
               buffer
               (if (= count (ann 4294967294 I64))
                   (unreachable)
                   (begin (let size (if (= count (ann 0 I64)) (ann 64 I64) (if (> count (ann 2147483647 I64)) (ann 4294967294 I64) (* count (ann 2 I64)))))
                          (begin (let grown (make-string size))
                                 (begin
                                   (string-copy! grown (ann 0 I64) buffer (ann 0 I64) count)
                                   grown)))))))

    ;; ---- Character iteration and decimal integer formatting ----

    (def write-char-to (-> Char OutputPort Unit)
         (lambda (character port)
           (port-write (ref-get (output-handle port)) character)))

    (def write-string-to (-> String OutputPort Unit)
         (lambda (text port)
           (begin
             ;; Even an empty write checks direction and lifetime without emitting text.
             (port-check-output (ref-get (output-handle port)))
             (begin (let count (string-length text))
                    (begin
                      (def loop
                           (lambda (index)
                             (if (= index count)
                                 (unit)
                                 (begin
                                   (write-char (string-ref text index) port)
                                   (loop (+ index (ann 1 I64)))
                                   (unit)))))
                      (loop (ann 0 I64)))))))

    (def newline-to (-> OutputPort Unit)
         (lambda (port) (write-char #\newline port)))
    (define-overload write-char (-> Char OutputPort Unit) write-char-to)
    (define-overload write-char (-> Char Unit)
      (lambda (character) (write-char-to character (current-output-port))))
    (define-overload write-string (-> String OutputPort Unit) write-string-to)
    (define-overload write-string (-> String Unit)
      (lambda (text) (write-string-to text (current-output-port))))
    (define-overload newline (-> OutputPort Unit) newline-to)
    (define-overload newline (-> Unit) (lambda () (newline-to (current-output-port))))

    (def write-i64 (-> I64 OutputPort Unit)
         (lambda (number port)
           (begin
             (if (< number (ann 0 I64))
                 (begin (write-char #\- port)
                        (unit))
                 (unit))
             (write-negative-digits (if (> number (ann 0 I64)) (- (ann 0 I64) number) number) port))))
    ;; Nonpositive digits avoid negating I64_MIN. Remainders are in [-9, 0],
    ;; recursion has at most 19 levels, and zero still emits one digit.

    (def write-negative-digits (-> I64 OutputPort Unit)
         (lambda (number port)
           (begin (let prefix (quotient number (ann 10 I64)))
                  (begin
                    (if (= prefix (ann 0 I64))
                        (unit)
                        (begin (write-negative-digits prefix port)
                               (unit)))
                    (write-char (integer->char (- (ann 48 I64) (remainder number (ann 10 I64)))) port)))))))
