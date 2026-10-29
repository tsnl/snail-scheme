;; Console text, files, directories and the clock. The host implements
;; `console`, `fs` and `clock` by default; a handler can replace any of
;; them, for example to capture output or to serve files from memory in a
;; test.
(define-library (snail core io)
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
   write-bytes
   file-exists?
   FileError
   NotFound
   AlreadyExists
   NotEmpty
   NotADirectory
   IsADirectory
   PermissionDenied
   InvalidPath
   NotSupported
   OtherError
   FileKind
   RegularFile
   Directory
   SymbolicLink
   OtherKind
   FileStatus
   FileStatus-kind
   FileStatus-size
   FileStatus-modified
   make-directory
   make-directories
   rename-file
   remove-file
   remove-directory
   remove-tree
   list-directory
   file-status
   followed-status
   make-symbolic-link
   read-symbolic-link
   clock
   monotonic-nanoseconds
   command-line)
  (import
   (snail core base))
  (begin

    ;; ---- Console effect ----

    (effect console
      ((console-write (-> Char Unit))
       (console-read (-> I32)))
      (host "snail.core.support"
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

    ;; Each operation receives its complete path. Ports are runtime handles;
    ;; a closed port must not be used again. The path operations after them
    ;; answer a nonnegative result or the negative code of a FileError
    ;; (path-result). What one finds besides, a directory's names, a link's
    ;; target or a status's numbers, waits for the reads that follow it
    ;; (reply-character, status-size and status-modified) until the next.
    ;; One that takes two paths takes them as one text, joined by a NUL,
    ;; which no path can hold (path-pair).
    (effect fs
      ((path-exists (-> String I32))
       (open-input (-> String I32))
       (open-output (-> String I32))
       (port-read (-> I32 I32))
       (port-read-byte (-> I32 I32))
       (port-write (-> I32 String Unit))
       (port-write-byte (-> I32 I32 Unit))
       (port-close (-> I32 Unit))
       (path-make-directory (-> String I32))
       (path-rename (-> String I32))
       (path-remove-file (-> String I32))
       (path-remove-directory (-> String I32))
       (path-list (-> String I32))
       (path-status (-> String I32))
       (path-followed-status (-> String I32))
       (path-make-link (-> String I32))
       (path-read-link (-> String I32))
       (reply-character (-> I32 Char))
       (status-size (-> I64))
       (status-modified (-> I64)))
      (host "snail.core.support"
            ((path-exists "snail:io/file-exists")
             (open-input "snail:io/open-input-file")
             (open-output "snail:io/open-output-file")
             (port-read "snail:io/read-character")
             (port-read-byte "snail:io/read-byte")
             (port-write "snail:io/write-string")
             (port-write-byte "snail:io/write-byte")
             (port-close "snail:io/close")
             (path-make-directory "snail:io/make-directory")
             (path-rename "snail:io/rename")
             (path-remove-file "snail:io/remove-file")
             (path-remove-directory "snail:io/remove-directory")
             (path-list "snail:io/list-directory")
             (path-status "snail:io/file-status")
             (path-followed-status "snail:io/followed-status")
             (path-make-link "snail:io/make-symbolic-link")
             (path-read-link "snail:io/read-symbolic-link")
             (reply-character "snail:io/reply-character")
             (status-size "snail:io/status-size")
             (status-modified "snail:io/status-modified"))))

    (: file-exists? (-> String Bool ! fs))
    (define (file-exists? path)
      (= (path-exists path) 1))

    ;; The whole file as text; the runtime fails the program if it cannot
    ;; be read.
    (: read-file (-> String String ! fs))
    (define (read-file path)
      (let ((port (open-input path)))
        (let ((chars (drain (lambda ()
                              (let ((code (port-read port)))
                                (if (= code -1) (None) (Some (i32->char code))))))))
          (port-close port)
          (vector->string chars))))

    ;; The whole file as bytes, for binary files such as images.
    (: read-bytes (-> String Bytes ! fs))
    (define (read-bytes path)
      (let ((port (open-input path)))
        (let ((bytes (drain (lambda ()
                              (let ((byte (port-read-byte port)))
                                (if (= byte -1) (None) (Some (i32->u8 byte))))))))
          (port-close port)
          bytes)))

    ;; Everything `next` gives until it gives None. Items gather a chunk at a
    ;; time, and the chunks are joined at the end, so a file of millions of
    ;; characters or bytes costs a few bytes for each rather than a list
    ;; cell.
    (define chunk-size 4096)

    (: drain (All (T e) (requires (Copy T)) (-> (-> (Option T) ! e) (Vector T) ! e)))
    (define (drain next)
      (let loop ((chunks (Nil)))
        (let ((chunk (next-chunk next)))
          (if (< (vector-length chunk) chunk-size)
              (vector-concatenate (reverse (Cons chunk chunks)))
              (loop (Cons chunk chunks))))))

    ;; Up to `chunk-size` items, fewer only at the end.
    (: next-chunk (All (T e) (requires (Copy T)) (-> (-> (Option T) ! e) (Vector T) ! e)))
    (define (next-chunk next)
      (let loop ((items (Nil)) (count 0))
        (if (= count chunk-size)
            (list->vector (reverse items))
            (match (next)
              ((Some item) (loop (Cons item items) (+ count 1)))
              ((None) (list->vector (reverse items)))))))

    (: write-file (-> String String Unit ! fs))
    (define (write-file path text)
      (let ((port (open-output path)))
        (port-write port text)
        (port-close port)))

    ;; Bytes to a binary file, replacing it.
    (: write-bytes (-> String Bytes Unit ! fs))
    (define (write-bytes path bytes)
      (let ((port (open-output path)))
        (let loop ((index 0))
          (when (< index (vector-length bytes))
            (port-write-byte port (u8->i32 (vector-ref bytes index)))
            (loop (+ index 1))))
        (port-close port)))

    ;; ---- Paths and directories ----

    ;; Why a path operation failed. A failure a program can act on is a
    ;; value: a missing path, a directory that is not empty. What the host
    ;; does not say more about is OtherError, as is every path operation on
    ;; a host with no filesystem, such as a page.
    (enum FileError
      (NotFound)
      (AlreadyExists)
      (NotEmpty)
      (NotADirectory)
      (IsADirectory)
      (PermissionDenied)
      (InvalidPath)
      (NotSupported)
      (OtherError))

    (instance (Show FileError)
      (define (show error)
        (match error
          ((NotFound) "no such file or directory")
          ((AlreadyExists) "it already exists")
          ((NotEmpty) "the directory is not empty")
          ((NotADirectory) "not a directory")
          ((IsADirectory) "it is a directory")
          ((PermissionDenied) "permission denied")
          ((InvalidPath) "invalid path")
          ((NotSupported) "not supported here")
          ((OtherError) "the operation failed"))))

    (enum FileKind
      (RegularFile)
      (Directory)
      (SymbolicLink)
      (OtherKind))

    ;; What is at a path: its kind, its size in bytes, and when its
    ;; contents last changed, in nanoseconds since the Unix epoch.
    (struct FileStatus
      ((kind FileKind)
       (size I64)
       (modified I64)))

    ;; A code as the runtime answers it. crates/snail-core-support/src/paths.rs gives
    ;; each FileError its number, in this order.
    (: path-result (-> I32 (Result I32 FileError)))
    (define (path-result code)
      (case code
        ((-1) (Err (NotFound)))
        ((-2) (Err (AlreadyExists)))
        ((-3) (Err (NotEmpty)))
        ((-4) (Err (NotADirectory)))
        ((-5) (Err (IsADirectory)))
        ((-6) (Err (PermissionDenied)))
        ((-7) (Err (InvalidPath)))
        ((-8) (Err (NotSupported)))
        (else (if (< code 0) (Err (OtherError)) (Ok code)))))

    (: path-done (-> I32 (Result Unit FileError)))
    (define (path-done code)
      (match (path-result code)
        ((Ok _) (Ok (unit)))
        ((Err error) (Err error))))

    (: path-pair (-> String String String))
    (define (path-pair first second)
      (string-append first (make-string 1 #\null) second))

    ;; Makes one directory, whose parent must exist.
    (: make-directory (-> String (Result Unit FileError) ! fs))
    (define (make-directory path)
      (path-done (path-make-directory path)))

    ;; Makes the directory and each missing parent. A directory already there
    ;; is success; anything else there is AlreadyExists.
    (: make-directories (-> String (Result Unit FileError) ! fs))
    (define (make-directories path)
      (match (make-directory path)
        ((Err (NotFound)) (make-with-parents path))
        ((Err (AlreadyExists)) (if (directory? path) (Ok (unit)) (Err (AlreadyExists))))
        (made made)))

    (: make-with-parents (-> String (Result Unit FileError) ! fs))
    (define (make-with-parents path)
      (match (parent-path path)
        ((Some parent) (match (make-directories parent)
                         ((Ok _) (make-directory path))
                         (failed failed)))
        ((None) (Err (NotFound)))))

    ;; The path up to its last separator, if that leaves a name.
    (: parent-path (-> String (Option String)))
    (define (parent-path path)
      (let loop ((index (- (string-length path) 1)))
        (cond ((<= index 0) (None))
              ((char=? (string-ref path index) #\/) (Some (substring path 0 index)))
              (else (loop (- index 1))))))

    (: directory? (-> String Bool ! fs))
    (define (directory? path)
      (match (file-status path)
        ((Ok status) (match (FileStatus-kind status)
                       ((Directory) #t)
                       (_ #f)))
        ((Err _) #f)))

    ;; Gives `from`'s file or directory the name `to`, replacing a file
    ;; there at once, so a reader of `to` sees the old file or the new one
    ;; and never neither: this is how a writer publishes a complete file.
    (: rename-file (-> String String (Result Unit FileError) ! fs))
    (define (rename-file from to)
      (path-done (path-rename (path-pair from to))))

    ;; Removes a file or a symbolic link, never a directory.
    (: remove-file (-> String (Result Unit FileError) ! fs))
    (define (remove-file path)
      (path-done (path-remove-file path)))

    ;; Removes an empty directory.
    (: remove-directory (-> String (Result Unit FileError) ! fs))
    (define (remove-directory path)
      (path-done (path-remove-directory path)))

    ;; Removes what is at `path` and, if it is a directory, everything in it
    ;; first. A symbolic link is removed, never followed.
    (: remove-tree (-> String (Result Unit FileError) ! fs))
    (define (remove-tree path)
      (match (file-status path)
        ((Ok status) (match (FileStatus-kind status)
                       ((Directory) (match (list-directory path)
                                      ((Ok names) (remove-entries path names))
                                      ((Err error) (Err error))))
                       (_ (remove-file path))))
        ((Err error) (Err error))))

    (: remove-entries (-> String (List String) (Result Unit FileError) ! fs))
    (define (remove-entries directory names)
      (match names
        ((Nil) (remove-directory directory))
        ((Cons name rest) (match (remove-tree (string-append directory "/" name))
                            ((Ok _) (remove-entries directory rest))
                            (failed failed)))))

    ;; The names in a directory, without "." and "..", in the order of
    ;; their scalars, whatever order the host keeps them in.
    (: list-directory (-> String (Result (List String) FileError) ! fs))
    (define (list-directory path)
      (match (path-result (path-list path))
        ((Ok 0) (Ok (Nil)))
        ((Ok count) (Ok (reply-names count)))
        ((Err error) (Err error))))

    ;; The reply's `count` scalars, split at each NUL. They are read from
    ;; the end, so each name's characters arrive in order.
    (: reply-names (-> I32 (List String) ! fs))
    (define (reply-names count)
      (let loop ((index (- count 1)) (name (Nil)) (names (Nil)))
        (if (< index 0)
            (Cons (list->string name) names)
            (let ((char (reply-character index)))
              (if (char=? char #\null)
                  (loop (- index 1) (Nil) (Cons (list->string name) names))
                  (loop (- index 1) (Cons char name) names))))))

    (: reply-text (-> I32 String ! fs))
    (define (reply-text count)
      (string-generate (i32->i64 count) (lambda (index) (reply-character (i64->i32 index)))))

    ;; The status of the path itself: a symbolic link is a SymbolicLink,
    ;; whatever it names.
    (: file-status (-> String (Result FileStatus FileError) ! fs))
    (define (file-status path)
      (status-result (path-status path)))

    ;; The status of what a read of `path` finds, following each symbolic
    ;; link to the file it names, so never a SymbolicLink. A link that names
    ;; nothing is NotFound here, though file-status finds the link.
    (: followed-status (-> String (Result FileStatus FileError) ! fs))
    (define (followed-status path)
      (status-result (path-followed-status path)))

    (: status-result (-> I32 (Result FileStatus FileError) ! fs))
    (define (status-result code)
      (match (path-result code)
        ((Ok kind) (Ok (FileStatus (file-kind kind) (status-size) (status-modified))))
        ((Err error) (Err error))))

    (: file-kind (-> I32 FileKind))
    (define (file-kind code)
      (case code
        ((0) (RegularFile))
        ((1) (Directory))
        ((2) (SymbolicLink))
        (else (OtherKind))))

    ;; Makes `path` a symbolic link to `target`, in `ln -s` order. The
    ;; target is kept as given: a relative one is read from the link's own
    ;; directory.
    (: make-symbolic-link (-> String String (Result Unit FileError) ! fs))
    (define (make-symbolic-link target path)
      (path-done (path-make-link (path-pair target path))))

    ;; A symbolic link's target. A path that is not a link is InvalidPath.
    (: read-symbolic-link (-> String (Result String FileError) ! fs))
    (define (read-symbolic-link path)
      (match (path-result (path-read-link path))
        ((Ok count) (Ok (reply-text count)))
        ((Err error) (Err error))))

    ;; ---- Clock ----

    ;; Nanoseconds since an origin the host chooses, which only ever grow:
    ;; the difference between two readings is the time between them.
    (effect clock
      ((monotonic-nanoseconds (-> I64)))
      (host "snail.core.support"
            ((monotonic-nanoseconds "snail:clock/monotonic"))))

    ;; ---- Command line ----

    ;; The program's arguments, starting with its own path. They never change
    ;; while it runs, so reading them is total.
    (extern argument-count "snail.core.support" "snail:process/argument-count" (-> I32))
    (extern argument-length "snail.core.support" "snail:process/argument-length" (-> I32 I32))
    (extern argument-character
            "snail.core.support"
            "snail:process/argument-character"
            (-> I32 I32 Char))

    (: command-line (-> (List String)))
    (define (command-line)
      (map (lambda (index)
             (let ((argument (i64->i32 index)))
               (string-generate (i32->i64 (argument-length argument))
                                (lambda (position)
                                  (argument-character argument (i64->i32 position))))))
           (iota (i32->i64 (argument-count)))))

    ))
