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
   TextError
   ReadFailed
   NotRegularFile
   TooLong
   NotText
   ChangedWhileRead
   read-text-file
   write-text-file
   FileError
   NotFound
   AlreadyExists
   NotADirectory
   PermissionDenied
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
   command-line
   environment-variable
   working-directory)
  (import
   (snail core base))
  (begin

    ;; ---- Console effect ----

    (effect console
      ((console-write (-> Char Unit))
       (console-read (-> I32)))
      (default ((console-write support-console-write) (console-read support-console-read))))

    (extern support-console-write "snail.core.support" "snail:io/console-write" (-> Char Unit))
    (extern support-console-read "snail.core.support" "snail:io/console-read" (-> I32))

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

    (: display (All (T e) (requires (Show e T)) (-> T Unit ! console e)))
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
       (status-modified (-> I64))
       (path-read-text (-> I64 String I32))
       (path-write-text (-> String I32)))
      (default ((path-exists support-path-exists)
                (open-input support-open-input)
                (open-output support-open-output)
                (port-read support-port-read)
                (port-read-byte support-port-read-byte)
                (port-write support-port-write)
                (port-write-byte support-port-write-byte)
                (port-close support-port-close)
                (path-make-directory support-path-make-directory)
                (path-rename support-path-rename)
                (path-remove-file support-path-remove-file)
                (path-remove-directory support-path-remove-directory)
                (path-list support-path-list)
                (path-status support-path-status)
                (path-followed-status support-path-followed-status)
                (path-make-link support-path-make-link)
                (path-read-link support-path-read-link)
                (reply-character support-reply-character)
                (status-size support-status-size)
                (status-modified support-status-modified)
                (path-read-text support-path-read-text)
                (path-write-text support-path-write-text))))

    (extern support-path-exists "snail.core.support" "snail:io/file-exists" (-> String I32))
    (extern support-open-input "snail.core.support" "snail:io/open-input-file" (-> String I32))
    (extern support-open-output "snail.core.support" "snail:io/open-output-file" (-> String I32))
    (extern support-port-read "snail.core.support" "snail:io/read-character" (-> I32 I32))
    (extern support-port-read-byte "snail.core.support" "snail:io/read-byte" (-> I32 I32))
    (extern support-port-write "snail.core.support" "snail:io/write-string" (-> I32 String Unit))
    (extern support-port-write-byte "snail.core.support" "snail:io/write-byte" (-> I32 I32 Unit))
    (extern support-port-close "snail.core.support" "snail:io/close" (-> I32 Unit))
    (extern support-path-make-directory
            "snail.core.support"
            "snail:io/make-directory"
            (-> String I32))
    (extern support-path-rename "snail.core.support" "snail:io/rename" (-> String I32))
    (extern support-path-remove-file "snail.core.support" "snail:io/remove-file" (-> String I32))
    (extern support-path-remove-directory
            "snail.core.support"
            "snail:io/remove-directory"
            (-> String I32))
    (extern support-path-list "snail.core.support" "snail:io/list-directory" (-> String I32))
    (extern support-path-status "snail.core.support" "snail:io/file-status" (-> String I32))
    (extern support-path-followed-status
            "snail.core.support"
            "snail:io/followed-status"
            (-> String I32))
    (extern support-path-make-link
            "snail.core.support"
            "snail:io/make-symbolic-link"
            (-> String I32))
    (extern support-path-read-link
            "snail.core.support"
            "snail:io/read-symbolic-link"
            (-> String I32))
    (extern support-reply-character "snail.core.support" "snail:io/reply-character" (-> I32 Char))
    (extern support-status-size "snail.core.support" "snail:io/status-size" (-> I64))
    (extern support-status-modified "snail.core.support" "snail:io/status-modified" (-> I64))
    (extern support-path-read-text "snail.core.support" "snail:io/read-text" (-> I64 String I32))
    (extern support-path-write-text "snail.core.support" "snail:io/write-text" (-> String I32))

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

    ;; Why a path operation failed. A kind is here because a program acts
    ;; on it: a missing path is made or skipped, a name already taken is
    ;; replaced by another, a path through a file is gone, and a refusal is
    ;; answered as one. Every other failure is OtherError, as is every path
    ;; operation on a host with no filesystem, such as a page.
    (enum FileError
      (NotFound)
      (AlreadyExists)
      (NotADirectory)
      (PermissionDenied)
      (OtherError))

    (instance (Show (!) FileError)
      (define (show error)
        (match error
          ((NotFound) "no such file or directory")
          ((AlreadyExists) "it already exists")
          ((NotADirectory) "not a directory")
          ((PermissionDenied) "permission denied")
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
        ((-3) (Err (NotADirectory)))
        ((-4) (Err (PermissionDenied)))
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
        (made (directory-there path made))))

    ;; The last directory is made once its parents are, and may be there by
    ;; then: a trailing or doubled slash names a parent twice, as `a/b` and
    ;; `a/b/`, and another process may have made it meanwhile.
    (: make-with-parents (-> String (Result Unit FileError) ! fs))
    (define (make-with-parents path)
      (match (parent-path path)
        ((Some parent) (match (make-directories parent)
                         ((Ok _) (directory-there path (make-directory path)))
                         (failed failed)))
        ((None) (Err (NotFound)))))

    ;; What making the directory at `path` answered, with AlreadyExists
    ;; made a success when what is there is a directory.
    (: directory-there (-> String (Result Unit FileError) (Result Unit FileError) ! fs))
    (define (directory-there path made)
      (match made
        ((Err (AlreadyExists)) (if (directory? path) (Ok (unit)) made))
        (_ made)))

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

    ;; A symbolic link's target. A path that is not a link is OtherError.
    (: read-symbolic-link (-> String (Result String FileError) ! fs))
    (define (read-symbolic-link path)
      (match (path-result (path-read-link path))
        ((Ok count) (Ok (reply-text count)))
        ((Err error) (Err error))))

    ;; ---- Whole texts ----

    ;; Why a file's text was not read: the path could not be examined,
    ;; opened or read, or it is not a regular file, or the file holds more
    ;; bytes than the limit, or bytes that are not UTF-8, or it changed
    ;; while it was read.
    (enum TextError
      (ReadFailed
       ((error FileError)))
      (NotRegularFile)
      (TooLong)
      (NotText)
      (ChangedWhileRead))

    (instance (Show (!) TextError)
      (define (show error)
        (match error
          ((ReadFailed error) (show error))
          ((NotRegularFile) "not a regular file")
          ((TooLong) "the file is too long")
          ((NotText) "the file is not UTF-8 text")
          ((ChangedWhileRead) "the file changed while it was read"))))

    ;; The text of the regular file at `path`, if it holds at most `limit`
    ;; bytes of UTF-8. The path must name the file itself: a symbolic link
    ;; is not followed. The text is one version of the file, which kept its
    ;; length and modification time while it was read. Unlike read-file,
    ;; each failure is a value, so a service can answer it.
    ;; crates/snail-core-support/src/paths.rs numbers the refusals after
    ;; FileError's codes.
    (: read-text-file (-> String I64 (Result String TextError) ! fs))
    (define (read-text-file path limit)
      (let ((code (path-read-text limit path)))
        (case code
          ((-6) (Err (NotRegularFile)))
          ((-7) (Err (TooLong)))
          ((-8) (Err (NotText)))
          ((-9) (Err (ChangedWhileRead)))
          (else (match (path-result code)
                  ((Ok count) (Ok (reply-text count)))
                  ((Err error) (Err (ReadFailed error))))))))

    ;; Makes the file at `path`, or replaces its contents in place, with
    ;; `text`. Unlike write-file, a failure is a value. The path is staged
    ;; before the text, ended by a NUL, so a path holding one fails.
    (: write-text-file (-> String String (Result Unit FileError) ! fs))
    (define (write-text-file path text)
      (match (string-index path #\null)
        ((Some _) (Err (OtherError)))
        ((None) (path-done (path-write-text (path-pair path text))))))

    ;; ---- Clock ----

    ;; Nanoseconds since an origin the host chooses, which only ever grow:
    ;; the difference between two readings is the time between them.
    (effect clock
      ((monotonic-nanoseconds (-> I64)))
      (default ((monotonic-nanoseconds support-monotonic-nanoseconds))))

    (extern support-monotonic-nanoseconds "snail.core.support" "snail:clock/monotonic" (-> I64))

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

    ;; ---- Environment ----

    ;; A variable of the environment the program started with. It never
    ;; changes while the program runs, so reading it is total, as reading
    ;; the arguments is. The working directory is the one relative paths
    ;; resolve against; a host with no filesystem, such as a page, has none.
    (extern variable-length "snail.core.support" "snail:process/variable-length" (-> String I32))
    (extern variable-character
            "snail.core.support"
            "snail:process/variable-character"
            (-> I32 String Char))
    (extern directory-length "snail.core.support" "snail:process/directory-length" (-> I32))
    (extern directory-character
            "snail.core.support"
            "snail:process/directory-character"
            (-> I32 Char))

    (: environment-variable (-> String (Option String)))
    (define (environment-variable name)
      (let ((length (variable-length name)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (variable-character (i64->i32 position) name)))))))

    (: working-directory (-> (Option String)))
    (define (working-directory)
      (let ((length (directory-length)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (directory-character (i64->i32 position))))))))

    ))
