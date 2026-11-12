;; Current input and output ports, files, directories and the clock. Input
;; and output are independent effects: handlers choose their streams, and
;; their defaults use standard input and output. The host also supplies
;; defaults for `fs` and `clock`.
(define-library (snail core io)
  (export
   input-port
   output-port
   read-char
   write-char
   write-string
   newline
   write-line
   display
   write
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
   WriteMode CreateNew ReplaceExisting CreateOrReplace
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

    ;; ---- Current port effects ----

    (effect input-port
      ((read-char (dyn (Fn → (Option Char)))))
      (default ((read-char read-standard-char))))

    (effect output-port
      ((write-string (dyn (Fn String → Unit))))
      (default ((write-string write-standard-string))))

    ;; The runtime reserves -3 for borrowed stdin and -2 for borrowed stdout.
    ;; Reading stdin flushes pending stdout first. Only the foreign boundary
    ;; uses -1 for EOF; handlers and callers exchange Option Char.
    (define (read-standard-char) (→ (Option Char))
      (let ((code (support-port-read -3)))
        (if (= code -1) (None) (Some (i32->char code)))))

    (define (write-standard-string (text String)) (→ Unit)
      (support-port-write -2 text))

    ;; ---- Text input ----

    ;; The next line of the current input without its newline, or None at the
    ;; end of input.

    (define (read-line) (→ (Option String)) (! input-port)
      (let loop ((chars (Nil)))
        (match (read-char)
          ((None) (if (null? chars) (None) (Some (list->string (reverse chars)))))
          ((Some char)
           (if (= char #\newline)
               (Some (list->string (reverse chars)))
               (loop (Cons char chars)))))))

    ;; ---- Text output ----

    (define (write-char (char Char)) (→ Unit) (! output-port)
      (write-string (make-string 1 char)))

    (define (newline) (→ Unit) (! output-port)
      (write-string "\n"))

    (define (write-line (text String)) (→ Unit) (! output-port)
      (write-string (string-append text "\n")))

    (define (display (value T)) (→ Unit) (! output-port e) (∀ T e) (⊨ (Show e T))
      (write-string (show value)))

    (define (write (value T)) (→ Unit) (! output-port) (∀ T) (⊨ (Repr T))
      (write-string (repr value)))

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
      ((path-exists (dyn (Fn String → I32)))
       (open-input (dyn (Fn String → I32)))
       (open-output (dyn (Fn String → I32)))
       (port-read (dyn (Fn I32 → I32)))
       (port-read-byte (dyn (Fn I32 → I32)))
       (port-write (dyn (Fn I32 String → Unit)))
       (port-write-byte (dyn (Fn I32 I32 → Unit)))
       (port-close (dyn (Fn I32 → Unit)))
       (path-make-directory (dyn (Fn String → I32)))
       (path-rename (dyn (Fn String → I32)))
       (path-remove-file (dyn (Fn String → I32)))
       (path-remove-directory (dyn (Fn String → I32)))
       (path-list (dyn (Fn String → I32)))
       (path-status (dyn (Fn String → I32)))
       (path-followed-status (dyn (Fn String → I32)))
       (path-make-link (dyn (Fn String → I32)))
       (path-read-link (dyn (Fn String → I32)))
       (reply-character (dyn (Fn I32 → Char)))
       (status-size (dyn (Fn → I64)))
       (status-modified (dyn (Fn → I64)))
       (path-read-text (dyn (Fn I64 String → I32)))
       (path-write-text (dyn (Fn I32 String → I32))))
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

    (extern support-path-exists
            "snail.core.support"
            "snail:io/file-exists"
            (impl (Fn String → I32)))
    (extern support-open-input
            "snail.core.support"
            "snail:io/open-input-file"
            (impl (Fn String → I32)))
    (extern support-open-output
            "snail.core.support"
            "snail:io/open-output-file"
            (impl (Fn String → I32)))
    (extern support-port-read "snail.core.support" "snail:io/read-character" (impl (Fn I32 → I32)))
    (extern support-port-read-byte "snail.core.support" "snail:io/read-byte" (impl (Fn I32 → I32)))
    (extern support-port-write
            "snail.core.support"
            "snail:io/write-string"
            (impl (Fn I32 String → Unit)))
    (extern support-port-write-byte
            "snail.core.support"
            "snail:io/write-byte"
            (impl (Fn I32 I32 → Unit)))
    (extern support-port-close "snail.core.support" "snail:io/close" (impl (Fn I32 → Unit)))
    (extern support-path-make-directory
            "snail.core.support"
            "snail:io/make-directory"
            (impl (Fn String → I32)))
    (extern support-path-rename "snail.core.support" "snail:io/rename" (impl (Fn String → I32)))
    (extern support-path-remove-file
            "snail.core.support"
            "snail:io/remove-file"
            (impl (Fn String → I32)))
    (extern support-path-remove-directory
            "snail.core.support"
            "snail:io/remove-directory"
            (impl (Fn String → I32)))
    (extern support-path-list
            "snail.core.support"
            "snail:io/list-directory"
            (impl (Fn String → I32)))
    (extern support-path-status
            "snail.core.support"
            "snail:io/file-status"
            (impl (Fn String → I32)))
    (extern support-path-followed-status
            "snail.core.support"
            "snail:io/followed-status"
            (impl (Fn String → I32)))
    (extern support-path-make-link
            "snail.core.support"
            "snail:io/make-symbolic-link"
            (impl (Fn String → I32)))
    (extern support-path-read-link
            "snail.core.support"
            "snail:io/read-symbolic-link"
            (impl (Fn String → I32)))
    (extern support-reply-character
            "snail.core.support"
            "snail:io/reply-character"
            (impl (Fn I32 → Char)))
    (extern support-status-size "snail.core.support" "snail:io/status-size" (impl (Fn → I64)))
    (extern support-status-modified
            "snail.core.support"
            "snail:io/status-modified"
            (impl (Fn → I64)))
    (extern support-path-read-text
            "snail.core.support"
            "snail:io/read-text"
            (impl (Fn I64 String → I32)))
    (extern support-path-write-text
            "snail.core.support"
            "snail:io/write-text"
            (impl (Fn I32 String → I32)))

    (define (file-exists? (path String)) (→ Bool) (! fs)
      (= (path-exists path) 1))

    ;; The whole file as text; the runtime fails the program if it cannot
    ;; be read.

    (define (read-file (path String)) (→ String) (! fs)
      (let ((port (open-input path)))
        (let ((chars (drain (lambda ()
                              (let ((code (port-read port)))
                                (if (= code -1) (None) (Some (i32->char code))))))))
          (port-close port)
          (vector->string chars))))

    ;; The whole file as bytes, for binary files such as images.

    (define (read-bytes (path String)) (→ Bytes) (! fs)
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

    (define (drain (next (dyn (Fn → (Option T) ! e)))) (→ (Vector T)) (! e) (∀ T e) (⊨ (Copy T))
      (let loop ((chunks (Nil)))
        (let ((chunk (next-chunk next)))
          (if (< (vector-length chunk) chunk-size)
              (vector-concatenate (reverse (Cons chunk chunks)))
              (loop (Cons chunk chunks))))))

    ;; Up to `chunk-size` items, fewer only at the end.

    (define (next-chunk (next (dyn (Fn → (Option T) ! e))))
      (→ (Vector T))
      (! e)
      (∀ T e)
      (⊨ (Copy T))
      (let loop ((items (Nil)) (count 0))
        (if (= count chunk-size)
            (list->vector (reverse items))
            (match (next)
              ((Some item) (loop (Cons item items) (+ count 1)))
              ((None) (list->vector (reverse items)))))))

    (define (write-file (path String) (text String)) (→ Unit) (! fs)
      (let ((port (open-output path)))
        (port-write port text)
        (port-close port)))

    ;; Bytes to a binary file, replacing it.

    (define (write-bytes (path String) (bytes Bytes)) (→ Unit) (! fs)
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
      (define show
        (lambda (error) (match error
                          ((NotFound) "no such file or directory")
                          ((AlreadyExists) "it already exists")
                          ((NotADirectory) "not a directory")
                          ((PermissionDenied) "permission denied")
                          ((OtherError) "the operation failed")))))

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

    (define (path-result (code I32)) (→ (Result I32 FileError))
      (case code
        ((-1) (Err (NotFound)))
        ((-2) (Err (AlreadyExists)))
        ((-3) (Err (NotADirectory)))
        ((-4) (Err (PermissionDenied)))
        (else (if (< code 0) (Err (OtherError)) (Ok code)))))

    (define (path-done (code I32)) (→ (Result Unit FileError))
      (match (path-result code)
        ((Ok _) (Ok (unit)))
        ((Err error) (Err error))))

    (define (path-pair (first String) (second String)) (→ String)
      (string-append first (make-string 1 #\null) second))

    ;; Makes one directory, whose parent must exist.

    (define (make-directory (path String)) (→ (Result Unit FileError)) (! fs)
      (path-done (path-make-directory path)))

    ;; Makes the directory and each missing parent. A directory already there
    ;; is success; anything else there is AlreadyExists.

    (define (make-directories (path String)) (→ (Result Unit FileError)) (! fs)
      (match (make-directory path)
        ((Err (NotFound)) (make-with-parents path))
        (made (directory-there path made))))

    ;; The last directory is made once its parents are, and may be there by
    ;; then: a trailing or doubled slash names a parent twice, as `a/b` and
    ;; `a/b/`, and another process may have made it meanwhile.

    (define (make-with-parents (path String)) (→ (Result Unit FileError)) (! fs)
      (match (parent-path path)
        ((Some parent) (match (make-directories parent)
                         ((Ok _) (directory-there path (make-directory path)))
                         (failed failed)))
        ((None) (Err (NotFound)))))

    ;; What making the directory at `path` answered, with AlreadyExists
    ;; made a success when what is there is a directory.

    (define (directory-there (path String) (made (Result Unit FileError)))
      (→ (Result Unit FileError))
      (! fs)
      (match made
        ((Err (AlreadyExists)) (if (directory? path) (Ok (unit)) made))
        (_ made)))

    ;; The path up to its last separator, if that leaves a name.

    (define (parent-path (path String)) (→ (Option String))
      (let loop ((index (- (string-length path) 1)))
        (cond ((<= index 0) (None))
              ((char=? (string-ref path index) #\/) (Some (substring path 0 index)))
              (else (loop (- index 1))))))

    (define (directory? (path String)) (→ Bool) (! fs)
      (match (file-status path)
        ((Ok status) (match (● status kind)
                       ((Directory) #t)
                       (_ #f)))
        ((Err _) #f)))

    ;; Gives `from`'s file or directory the name `to`, replacing a file
    ;; there at once, so a reader of `to` sees the old file or the new one
    ;; and never neither: this is how a writer publishes a complete file.

    (define (rename-file (from String) (to String)) (→ (Result Unit FileError)) (! fs)
      (path-done (path-rename (path-pair from to))))

    ;; Removes a file or a symbolic link, never a directory.

    (define (remove-file (path String)) (→ (Result Unit FileError)) (! fs)
      (path-done (path-remove-file path)))

    ;; Removes an empty directory.

    (define (remove-directory (path String)) (→ (Result Unit FileError)) (! fs)
      (path-done (path-remove-directory path)))

    ;; Removes what is at `path` and, if it is a directory, everything in it
    ;; first. A symbolic link is removed, never followed.

    (define (remove-tree (path String)) (→ (Result Unit FileError)) (! fs)
      (match (file-status path)
        ((Ok status) (match (● status kind)
                       ((Directory) (match (list-directory path)
                                      ((Ok names) (remove-entries path names))
                                      ((Err error) (Err error))))
                       (_ (remove-file path))))
        ((Err error) (Err error))))

    (define (remove-entries (directory String) (names (List String)))
      (→ (Result Unit FileError))
      (! fs)
      (match names
        ((Nil) (remove-directory directory))
        ((Cons name rest) (match (remove-tree (string-append directory "/" name))
                            ((Ok _) (remove-entries directory rest))
                            (failed failed)))))

    ;; The names in a directory, without "." and "..", in the order of
    ;; their scalars, whatever order the host keeps them in.

    (define (list-directory (path String)) (→ (Result (List String) FileError)) (! fs)
      (match (path-result (path-list path))
        ((Ok 0) (Ok (Nil)))
        ((Ok count) (Ok (reply-names count)))
        ((Err error) (Err error))))

    ;; The reply's `count` scalars, split at each NUL. They are read from
    ;; the end, so each name's characters arrive in order.

    (define (reply-names (count I32)) (→ (List String)) (! fs)
      (let loop ((index (- count 1)) (name (Nil)) (names (Nil)))
        (if (< index 0)
            (Cons (list->string name) names)
            (let ((char (reply-character index)))
              (if (char=? char #\null)
                  (loop (- index 1) (Nil) (Cons (list->string name) names))
                  (loop (- index 1) (Cons char name) names))))))

    (define (reply-text (count I32)) (→ String) (! fs)
      (string-generate (i32->i64 count) (lambda (index) (reply-character (i64->i32 index)))))

    ;; The status of the path itself: a symbolic link is a SymbolicLink,
    ;; whatever it names.

    (define (file-status (path String)) (→ (Result FileStatus FileError)) (! fs)
      (status-result (path-status path)))

    ;; The status of what a read of `path` finds, following each symbolic
    ;; link to the file it names, so never a SymbolicLink. A link that names
    ;; nothing is NotFound here, though file-status finds the link.

    (define (followed-status (path String)) (→ (Result FileStatus FileError)) (! fs)
      (status-result (path-followed-status path)))

    (define (status-result (code I32)) (→ (Result FileStatus FileError)) (! fs)
      (match (path-result code)
        ((Ok kind) (Ok (FileStatus (file-kind kind) (status-size) (status-modified))))
        ((Err error) (Err error))))

    (define (file-kind (code I32)) (→ FileKind)
      (case code
        ((0) (RegularFile))
        ((1) (Directory))
        ((2) (SymbolicLink))
        (else (OtherKind))))

    ;; Makes `path` a symbolic link to `target`, in `ln -s` order. The
    ;; target is kept as given: a relative one is read from the link's own
    ;; directory.

    (define (make-symbolic-link (target String) (path String)) (→ (Result Unit FileError)) (! fs)
      (path-done (path-make-link (path-pair target path))))

    ;; A symbolic link's target. A path that is not a link is OtherError.

    (define (read-symbolic-link (path String)) (→ (Result String FileError)) (! fs)
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
      (define show
        (lambda (error) (match error
                          ((ReadFailed error) (show error))
                          ((NotRegularFile) "not a regular file")
                          ((TooLong) "the file is too long")
                          ((NotText) "the file is not UTF-8 text")
                          ((ChangedWhileRead) "the file changed while it was read")))))

    ;; The text of the regular file at `path`, if it holds at most `limit`
    ;; bytes of UTF-8. The path must name the file itself: a symbolic link
    ;; is not followed. The text is one version of the file, which kept its
    ;; length and modification time while it was read. Unlike read-file,
    ;; each failure is a value, so a service can answer it.
    ;; crates/snail-core-support/src/paths.rs numbers the refusals after
    ;; FileError's codes.

    (define (read-text-file (path String) (limit I64)) (→ (Result String TextError)) (! fs)
      (let ((code (path-read-text limit path)))
        (case code
          ((-6) (Err (NotRegularFile)))
          ((-7) (Err (TooLong)))
          ((-8) (Err (NotText)))
          ((-9) (Err (ChangedWhileRead)))
          (else (match (path-result code)
                  ((Ok count) (Ok (reply-text count)))
                  ((Err error) (Err (ReadFailed error))))))))

    ;; Writes are whole values, with an explicit policy for the leaf path.
    ;; CreateNew refuses every existing leaf, including a dangling symlink.
    ;; ReplaceExisting never creates a file; CreateOrReplace permits either.
    (enum WriteMode (CreateNew) (ReplaceExisting) (CreateOrReplace))

    (define (write-mode-code (mode WriteMode)) (→ I32)
      (match mode ((CreateNew) 0) ((ReplaceExisting) 1) ((CreateOrReplace) 2)))

    ;; A failure is a value. The path is staged before the text, separated
    ;; by NUL, so a path holding NUL fails before the scalar service runs.

    (define (write-text-file (path String) (text String) (mode WriteMode))
      (→ (Result Unit FileError))
      (! fs)
      (match (string-index path #\null)
        ((Some _) (Err (OtherError)))
        ((None) (path-done (path-write-text (write-mode-code mode) (path-pair path text))))))

    ;; ---- Clock ----

    ;; Nanoseconds since an origin the host chooses, which only ever grow:
    ;; the difference between two readings is the time between them.
    (effect clock
      ((monotonic-nanoseconds (dyn (Fn → I64))))
      (default ((monotonic-nanoseconds support-monotonic-nanoseconds))))

    (extern support-monotonic-nanoseconds
            "snail.core.support"
            "snail:clock/monotonic"
            (impl (Fn → I64)))

    ;; ---- Command line ----

    ;; The program's arguments, starting with its own path. They never change
    ;; while it runs, so reading them is total.
    (extern argument-count "snail.core.support" "snail:process/argument-count" (impl (Fn → I32)))
    (extern argument-length
            "snail.core.support"
            "snail:process/argument-length"
            (impl (Fn I32 → I32)))
    (extern argument-character
            "snail.core.support"
            "snail:process/argument-character"
            (impl (Fn I32 I32 → Char)))

    (define (command-line) (→ (List String))
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
    (extern variable-length
            "snail.core.support"
            "snail:process/variable-length"
            (impl (Fn String → I32)))
    (extern variable-character
            "snail.core.support"
            "snail:process/variable-character"
            (impl (Fn I32 String → Char)))
    (extern directory-length
            "snail.core.support"
            "snail:process/directory-length"
            (impl (Fn → I32)))
    (extern directory-character
            "snail.core.support"
            "snail:process/directory-character"
            (impl (Fn I32 → Char)))

    (define (environment-variable (name String)) (→ (Option String))
      (let ((length (variable-length name)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (variable-character (i64->i32 position) name)))))))

    (define (working-directory) (→ (Option String))
      (let ((length (directory-length)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (directory-character (i64->i32 position))))))))

    ))
