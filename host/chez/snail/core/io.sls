;; The source compiler uses text files and byte arrays through this boundary.
(library (snail core io)
  (export read-file
          read-bytes
          write-file
          file-exists?
          followed-status
          FileStatus
          FileKind
          RegularFile
          Directory FileError NotFound command-line write-string write-line newline)
  (import
   (chezscheme)
   (only (snail core base) array-generate enum record new Ok Err))
  ;; What is at a path, the link followed, as (snail core io) answers it:
  ;; the compiler reads a linked file's size and modification time.
  (enum FileKind (RegularFile) (Directory))
  (enum FileError (NotFound))
  (record FileStatus
    ((kind FileKind)
     (size I64)
     (modified I64)))
  (define (followed-status path)
    (if (file-exists? path)
        (let ([time (file-modification-time path)])
          (Ok (new FileStatus
                (kind (if (file-directory? path) (Directory) (RegularFile)))
                (size (if (file-directory? path)
                          0
                          (call-with-port (open-file-input-port path) port-length)))
                (modified (+ (* (time-second time) 1000000000) (time-nanosecond time))))))
        (Err (NotFound))))
  (define (read-file path) (call-with-input-file path get-string-all))
  (define (read-bytes path)
    (let ((bytes (call-with-port (open-file-input-port path) get-bytevector-all)))
      (array-generate (if (eof-object? bytes) 0 (bytevector-length bytes))
                      (lambda (index) (bytevector-u8-ref bytes index)))))
  (define (write-file path text)
    (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                           (native-transcoder))
      (lambda (port) (put-string port text))))
  (define (write-string text) (put-string (current-output-port) text))
  (define (write-line text) (write-string text) (newline)))
