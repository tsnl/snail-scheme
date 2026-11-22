;; The source compiler uses text files and byte arrays through this boundary.
;; A capability is a token here: Chez's own files and standard output stand
;; behind the one `Fs` and the one output port.
(library (snail core io)
  (export unsafe-host
          host-fs
          standard-output
          read-file
          read-bytes
          write-file
          file-exists?
          followed-status
          FileStatus
          FileKind
          RegularFile
          Directory FileError NotFound command-line write-string write-line newline)
  (import
   (rename (chezscheme) (file-exists? chez:file-exists?) (newline chez:newline))
   (only (snail core base) array-generate enum record new Ok Err))
  ;; What is at a path, the link followed, as (snail core io) answers it:
  ;; the compiler reads a linked file's size and modification time.
  (enum FileKind (RegularFile) (Directory))
  (enum FileError (NotFound))
  (record FileStatus
    ((kind FileKind)
     (size I64)
     (modified I64)))
  (define (unsafe-host) 'host)
  (define (host-fs host) 'host-fs)
  (define (standard-output host) 'standard-output)
  (define (followed-status fs path)
    (if (chez:file-exists? path)
        (let ([time (file-modification-time path)])
          (Ok (new FileStatus
                (kind (if (file-directory? path) (Directory) (RegularFile)))
                (size (if (file-directory? path)
                          0
                          (call-with-port (open-file-input-port path) port-length)))
                (modified (+ (* (time-second time) 1000000000) (time-nanosecond time))))))
        (Err (NotFound))))
  (define (read-file fs path) (call-with-input-file path get-string-all))
  (define (read-bytes fs path)
    (let ((bytes (call-with-port (open-file-input-port path) get-bytevector-all)))
      (array-generate (if (eof-object? bytes) 0 (bytevector-length bytes))
                      (lambda (index) (bytevector-u8-ref bytes index)))))
  (define (write-file fs path text)
    (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                           (native-transcoder))
      (lambda (port) (put-string port text))))
  (define (write-string out text) (put-string (current-output-port) text))
  (define (file-exists? fs path) (chez:file-exists? path))
  (define (newline out) (chez:newline (current-output-port)))
  (define (write-line out text) (write-string out text) (newline out)))
