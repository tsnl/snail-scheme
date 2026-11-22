;; Input and output ports, files, directories, the clock, and what a
;; program was started with, each a capability: a value a function is
;; given, and so may use. A port, a clock and an environment are records of
;; functions, which a program may make for itself, to keep what is written
;; or to fix the time. `Fs` is the host's file system whole, and holds
;; nothing: having it is the permission. The host's own are made from a
;; `Host`, which a target holds and gives to the program's `main`
;; (src/snail/target).
(define-library (snail core io)
  (export
   Host
   unsafe-host
   InputPort
   OutputPort
   standard-input
   standard-output
   write-char
   newline
   write-line
   display
   write
   read-line
   Fs
   host-fs
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
   make-hard-link
   Clock
   host-clock
   Arguments
   host-arguments
   command-line
   ProcessEnvironment
   host-environment)
  (import
   (snail core base))
  (begin

    ;; ---- The host ----

    ;; A `Host` is the ability to make the host's capabilities. Every
    ;; function that makes one takes it, here and in the libraries built on
    ;; this one (`standard-output`, `host-fs`, `host-gpu`, ...), so code
    ;; handed neither a `Host` nor something made from one reaches nothing
    ;; of the host's. A target makes the one there is, with `unsafe-host`,
    ;; and a program's `main` asks it for what it needs (src/snail/target):
    ;; a capability by its type, or the `Host` itself, to make one later or
    ;; not at all.
    (enum Host
      (TheHost))

    (define (unsafe-host) (→ Host)
      (TheHost))

    ;; ---- Ports ----

    ;; A port is the one function that reads or writes it, so a program
    ;; makes its own with `new`: one that keeps what is written, or writes
    ;; it to two ports.
    (record InputPort
      ((read-char (Fn → (Option Char)))))

    (record OutputPort
      ((write-string (Fn String → Unit))))

    ;; Standard input and output.

    (define (standard-input (host Host)) (→ InputPort)
      (new InputPort (read-char read-standard-char)))

    (define (standard-output (host Host)) (→ OutputPort)
      (new OutputPort (write-string write-standard-string)))

    ;; The runtime reserves -3 for borrowed stdin and -2 for borrowed stdout.
    ;; Reading stdin flushes pending stdout first. Only the foreign boundary
    ;; uses -1 for EOF; ports and callers exchange Option Char.
    (define (read-standard-char) (→ (Option Char))
      (let ((code (support-port-read -3)))
        (if (= code -1) (None) (Some (i32->char code)))))

    (define (write-standard-string (text String)) (→ Unit)
      (support-port-write -2 text))

    ;; ---- Text input ----

    ;; The next line of the current input without its newline, or None at the
    ;; end of input.

    (define (read-line (in InputPort)) (→ (Option String))
      (let loop ((chars (Nil)))
        (match (in::read-char)
          ((None) (if (null? chars) (None) (Some (list->string (reverse chars)))))
          ((Some char)
           (if (= char #\newline)
               (Some (list->string (reverse chars)))
               (loop (Cons char chars)))))))

    ;; ---- Text output ----

    (define (write-char (out OutputPort) (char Char)) (→ Unit)
      (out::write-string (make-string 1 char)))

    (define (newline (out OutputPort)) (→ Unit)
      (out::write-string "\n"))

    (define (write-line (out OutputPort) (text String)) (→ Unit)
      (out::write-string (string-append text "\n")))

    (define (display (out OutputPort) (value T)) (→ Unit) (∀ (T)) (⊨ (Show T))
      (out::write-string (show value)))

    (define (write (out OutputPort) (value T)) (→ Unit) (∀ (T)) (⊨ (Repr T))
      (out::write-string (repr value)))

    ;; ---- Files ----

    ;; The host's file system. It holds nothing: a function given one may
    ;; read and write the host's files, and one given none cannot.
    (enum Fs
      (HostFs))

    (define (host-fs (host Host)) (→ Fs)
      (HostFs))

    ;; Each of the runtime's operations receives its complete path. Ports
    ;; are runtime handles; a closed port must not be used again. The path
    ;; operations after them answer a nonnegative result or the negative
    ;; code of a FileError (path-result). What one finds besides, a
    ;; directory's names, a link's target or a status's numbers, waits for
    ;; the reads that follow it (reply-character, status-size and
    ;; status-modified) until the next. One that takes two paths takes them
    ;; as one text, joined by a NUL, which no path can hold (path-pair).

    (extern support-path-exists
            "snail.core.support"
            "snail:io/file-exists"
            (Fn String → I32))
    (extern support-open-input
            "snail.core.support"
            "snail:io/open-input-file"
            (Fn String → I32))
    (extern support-open-output
            "snail.core.support"
            "snail:io/open-output-file"
            (Fn String → I32))
    (extern support-port-read "snail.core.support" "snail:io/read-character" (Fn I32 → I32))
    (extern support-port-read-byte "snail.core.support" "snail:io/read-byte" (Fn I32 → I32))
    (extern support-port-write
            "snail.core.support"
            "snail:io/write-string"
            (Fn I32 String → Unit))
    (extern support-port-write-byte
            "snail.core.support"
            "snail:io/write-byte"
            (Fn I32 I32 → Unit))
    (extern support-port-close "snail.core.support" "snail:io/close" (Fn I32 → Unit))
    (extern support-path-make-directory
            "snail.core.support"
            "snail:io/make-directory"
            (Fn String → I32))
    (extern support-path-rename "snail.core.support" "snail:io/rename" (Fn String → I32))
    (extern support-path-remove-file
            "snail.core.support"
            "snail:io/remove-file"
            (Fn String → I32))
    (extern support-path-remove-directory
            "snail.core.support"
            "snail:io/remove-directory"
            (Fn String → I32))
    (extern support-path-list
            "snail.core.support"
            "snail:io/list-directory"
            (Fn String → I32))
    (extern support-path-status
            "snail.core.support"
            "snail:io/file-status"
            (Fn String → I32))
    (extern support-path-followed-status
            "snail.core.support"
            "snail:io/followed-status"
            (Fn String → I32))
    (extern support-path-make-link
            "snail.core.support"
            "snail:io/make-symbolic-link"
            (Fn String → I32))
    (extern support-path-read-link
            "snail.core.support"
            "snail:io/read-symbolic-link"
            (Fn String → I32))
    (extern support-path-hard-link
            "snail.core.support"
            "snail:io/make-hard-link"
            (Fn String → I32))
    (extern support-reply-character
            "snail.core.support"
            "snail:io/reply-character"
            (Fn I32 → Char))
    (extern support-status-size "snail.core.support" "snail:io/status-size" (Fn → I64))
    (extern support-status-modified
            "snail.core.support"
            "snail:io/status-modified"
            (Fn → I64))
    (extern support-path-read-text
            "snail.core.support"
            "snail:io/read-text"
            (Fn I64 String → I32))
    (extern support-path-write-text
            "snail.core.support"
            "snail:io/write-text"
            (Fn I32 String → I32))

    (define (file-exists? (fs Fs) (path String)) (→ Bool)
      (= (support-path-exists path) 1))

    ;; The whole file as text; the runtime fails the program if it cannot
    ;; be read.

    (define (read-file (fs Fs) (path String)) (→ String)
      (let ((port (support-open-input path)))
        (let ((chars (drain (lambda ()
                              (let ((code (support-port-read port)))
                                (if (= code -1) (None) (Some (i32->char code))))))))
          (support-port-close port)
          (array->string chars))))

    ;; The whole file as bytes, for binary files such as images.

    (define (read-bytes (fs Fs) (path String)) (→ Bytes)
      (let ((port (support-open-input path)))
        (let ((bytes (drain (lambda ()
                              (let ((byte (support-port-read-byte port)))
                                (if (= byte -1) (None) (Some (i32->u8 byte))))))))
          (support-port-close port)
          bytes)))

    ;; Everything `next` gives until it gives None. Items gather a chunk at a
    ;; time, and the chunks are joined at the end, so a file of millions of
    ;; characters or bytes costs a few bytes for each rather than a list
    ;; cell.
    (define chunk-size (→ I64) 4096)

    (define (drain (next (Fn → (Option T))))
      (→ (Array T))
      (∀ (T))
      (let loop ((chunks (Nil)))
        (let ((chunk (next-chunk next)))
          (if (< (array-length chunk) chunk-size)
              (array-concatenate (reverse (Cons chunk chunks)))
              (loop (Cons chunk chunks))))))

    ;; Up to `chunk-size` items, fewer only at the end.

    (define (next-chunk (next (Fn → (Option T))))
      (→ (Array T))
      (∀ (T))
      (let loop ((items (Nil)) (count 0))
        (if (= count chunk-size)
            (list->array (reverse items))
            (match (next)
              ((Some item) (loop (Cons item items) (+ count 1)))
              ((None) (list->array (reverse items)))))))

    (define (write-file (fs Fs) (path String) (text String)) (→ Unit)
      (let ((port (support-open-output path)))
        (support-port-write port text)
        (support-port-close port)))

    ;; Bytes to a binary file, replacing it.

    (define (write-bytes (fs Fs) (path String) (bytes Bytes)) (→ Unit)
      (let ((port (support-open-output path)))
        (let loop ((index 0))
          (when (< index (array-length bytes))
            (support-port-write-byte port (u8->i32 (array-ref bytes index)))
            (loop (+ index 1))))
        (support-port-close port)))

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

    (instance (Show FileError)
      (define (show (error FileError)) (→ String)
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
    (record FileStatus
      ((kind FileKind)
       (size I64)
       (modified I64)))

    ;; A code as the runtime answers it. crates/snail-scheme-support/src/paths.rs gives
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

    (define (make-directory (fs Fs) (path String)) (→ (Result Unit FileError))
      (path-done (support-path-make-directory path)))

    ;; Makes the directory and each missing parent. A directory already there
    ;; is success; anything else there is AlreadyExists.

    (define (make-directories (fs Fs) (path String)) (→ (Result Unit FileError))
      (match (make-directory fs path)
        ((Err (NotFound)) (make-with-parents fs path))
        (made (directory-there fs path made))))

    ;; The last directory is made once its parents are, and may be there by
    ;; then: a trailing or doubled slash names a parent twice, as `a/b` and
    ;; `a/b/`, and another process may have made it meanwhile.

    (define (make-with-parents (fs Fs) (path String)) (→ (Result Unit FileError))
      (match (parent-path path)
        ((Some parent) (match (make-directories fs parent)
                         ((Ok _) (directory-there fs path (make-directory fs path)))
                         (failed failed)))
        ((None) (Err (NotFound)))))

    ;; What making the directory at `path` answered, with AlreadyExists
    ;; made a success when what is there is a directory.

    (define (directory-there (fs Fs) (path String) (made (Result Unit FileError)))
      (→ (Result Unit FileError))
      (match made
        ((Err (AlreadyExists)) (if (directory? fs path) (Ok (unit)) made))
        (_ made)))

    ;; The path up to its last separator, if that leaves a name.

    (define (parent-path (path String)) (→ (Option String))
      (let loop ((index (- (string-length path) 1)))
        (cond ((<= index 0) (None))
              ((char=? (string-ref path index) #\/) (Some (substring path 0 index)))
              (else (loop (- index 1))))))

    (define (directory? (fs Fs) (path String)) (→ Bool)
      (match (file-status fs path)
        ((Ok status) (match (● status kind)
                       ((Directory) #t)
                       (_ #f)))
        ((Err _) #f)))

    ;; Gives `from`'s file or directory the name `to`, replacing a file
    ;; there at once, so a reader of `to` sees the old file or the new one
    ;; and never neither: this is how a writer publishes a complete file.

    (define (rename-file (fs Fs) (from String) (to String)) (→ (Result Unit FileError))
      (path-done (support-path-rename (path-pair from to))))

    ;; Removes a file or a symbolic link, never a directory.

    (define (remove-file (fs Fs) (path String)) (→ (Result Unit FileError))
      (path-done (support-path-remove-file path)))

    ;; Removes an empty directory.

    (define (remove-directory (fs Fs) (path String)) (→ (Result Unit FileError))
      (path-done (support-path-remove-directory path)))

    ;; Removes what is at `path` and, if it is a directory, everything in it
    ;; first. A symbolic link is removed, never followed.

    (define (remove-tree (fs Fs) (path String)) (→ (Result Unit FileError))
      (match (file-status fs path)
        ((Ok status) (match (● status kind)
                       ((Directory) (match (list-directory fs path)
                                      ((Ok names) (remove-entries fs path names))
                                      ((Err error) (Err error))))
                       (_ (remove-file fs path))))
        ((Err error) (Err error))))

    (define (remove-entries (fs Fs) (directory String) (names (List String)))
      (→ (Result Unit FileError))
      (match names
        ((Nil) (remove-directory fs directory))
        ((Cons name rest) (match (remove-tree fs (string-append directory "/" name))
                            ((Ok _) (remove-entries fs directory rest))
                            (failed failed)))))

    ;; The names in a directory, without "." and "..", in the order of
    ;; their scalars, whatever order the host keeps them in.

    (define (list-directory (fs Fs) (path String)) (→ (Result (List String) FileError))
      (match (path-result (support-path-list path))
        ((Ok 0) (Ok (Nil)))
        ((Ok count) (Ok (reply-names fs count)))
        ((Err error) (Err error))))

    ;; The reply's `count` scalars, split at each NUL. They are read from
    ;; the end, so each name's characters arrive in order.

    (define (reply-names (fs Fs) (count I32)) (→ (List String))
      (let loop ((index (- count 1)) (name (Nil)) (names (Nil)))
        (if (< index 0)
            (Cons (list->string name) names)
            (let ((char (support-reply-character index)))
              (if (char=? char #\null)
                  (loop (- index 1) (Nil) (Cons (list->string name) names))
                  (loop (- index 1) (Cons char name) names))))))

    (define (reply-text (fs Fs) (count I32)) (→ String)
      (string-generate (i32->i64 count)
                       (lambda (index) (support-reply-character (i64->i32 index)))))

    ;; The status of the path itself: a symbolic link is a SymbolicLink,
    ;; whatever it names.

    (define (file-status (fs Fs) (path String)) (→ (Result FileStatus FileError))
      (status-result fs (support-path-status path)))

    ;; The status of what a read of `path` finds, following each symbolic
    ;; link to the file it names, so never a SymbolicLink. A link that names
    ;; nothing is NotFound here, though file-status finds the link.

    (define (followed-status (fs Fs) (path String)) (→ (Result FileStatus FileError))
      (status-result fs (support-path-followed-status path)))

    (define (status-result (fs Fs) (code I32)) (→ (Result FileStatus FileError))
      (match (path-result code)
        ((Ok kind)
         (Ok (new FileStatus
               (kind (file-kind kind))
               (size (support-status-size))
               (modified (support-status-modified)))))
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

    (define (make-symbolic-link (fs Fs) (target String) (path String))
      (→ (Result Unit FileError))
      (path-done (support-path-make-link (path-pair target path))))

    ;; A symbolic link's target. A path that is not a link is OtherError.

    (define (read-symbolic-link (fs Fs) (path String)) (→ (Result String FileError))
      (match (path-result (support-path-read-link path))
        ((Ok count) (Ok (reply-text fs count)))
        ((Err error) (Err error))))

    ;; Makes `path` another name for the file `existing` names, without
    ;; copying it: both hold the same bytes while either remains. It fails
    ;; where the two would lie on different file systems.

    (define (make-hard-link (fs Fs) (existing String) (path String))
      (→ (Result Unit FileError))
      (path-done (support-path-hard-link (path-pair existing path))))

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

    (instance (Show TextError)
      (define (show (error TextError)) (→ String)
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
    ;; crates/snail-scheme-support/src/paths.rs numbers the refusals after
    ;; FileError's codes.

    (define (read-text-file (fs Fs) (path String) (limit I64)) (→ (Result String TextError))
      (let ((code (support-path-read-text limit path)))
        (case code
          ((-6) (Err (NotRegularFile)))
          ((-7) (Err (TooLong)))
          ((-8) (Err (NotText)))
          ((-9) (Err (ChangedWhileRead)))
          (else (match (path-result code)
                  ((Ok count) (Ok (reply-text fs count)))
                  ((Err error) (Err (ReadFailed error))))))))

    ;; Writes are whole values, with an explicit policy for the leaf path.
    ;; CreateNew refuses every existing leaf, including a dangling symlink.
    ;; ReplaceExisting never creates a file; CreateOrReplace permits either.
    (enum WriteMode (CreateNew) (ReplaceExisting) (CreateOrReplace))

    (define (write-mode-code (mode WriteMode)) (→ I32)
      (match mode ((CreateNew) 0) ((ReplaceExisting) 1) ((CreateOrReplace) 2)))

    ;; A failure is a value. The path is staged before the text, separated
    ;; by NUL, so a path holding NUL fails before the scalar service runs.

    (define (write-text-file (fs Fs) (path String) (text String) (mode WriteMode))
      (→ (Result Unit FileError))
      (match (string-index path #\null)
        ((Some _) (Err (OtherError)))
        ((None)
         (path-done (support-path-write-text (write-mode-code mode) (path-pair path text))))))

    ;; ---- Clock ----

    ;; Nanoseconds since an origin the clock chooses, which only ever grow:
    ;; the difference between two readings is the time between them. A
    ;; program makes its own to fix the time a test sees.
    (record Clock
      ((monotonic-nanoseconds (Fn → I64))))

    (define (host-clock (host Host)) (→ Clock)
      (new Clock (monotonic-nanoseconds support-monotonic-nanoseconds)))

    (extern support-monotonic-nanoseconds
            "snail.core.support"
            "snail:clock/monotonic"
            (Fn → I64))

    ;; ---- Command line ----

    ;; The arguments a program was started with, first its own path. They
    ;; never change while it runs, but they are the host's to give: a
    ;; program's `main` asks for its `Arguments`, and a test makes its own.
    (record Arguments
      ((values (List String))))

    (define (command-line (arguments Arguments)) (→ (List String))
      (● arguments values))

    (extern argument-count "snail.core.support" "snail:process/argument-count" (Fn → I32))
    (extern argument-length
            "snail.core.support"
            "snail:process/argument-length"
            (Fn I32 → I32))
    (extern argument-character
            "snail.core.support"
            "snail:process/argument-character"
            (Fn I32 I32 → Char))

    (define (host-arguments (host Host)) (→ Arguments)
      (new Arguments (values (host-command-line))))

    (define (host-command-line) (→ (List String))
      (map (lambda (index)
             (let ((argument (i64->i32 index)))
               (string-generate (i32->i64 (argument-length argument))
                                (lambda (position)
                                  (argument-character argument (i64->i32 position))))))
           (iota (i32->i64 (argument-count)))))

    ;; ---- Environment ----

    ;; The environment a program started with: its variables, and the
    ;; working directory, the one relative paths resolve against; a host
    ;; with no filesystem, such as a page, has none. It never changes
    ;; while the program runs. A record of the two functions that read it,
    ;; so a test makes its own.
    (record ProcessEnvironment
      ((variable (Fn String → (Option String)))
       (directory (Fn → (Option String)))))

    (define (host-environment (host Host)) (→ ProcessEnvironment)
      (new ProcessEnvironment (variable host-variable) (directory host-directory)))

    (extern variable-length
            "snail.core.support"
            "snail:process/variable-length"
            (Fn String → I32))
    (extern variable-character
            "snail.core.support"
            "snail:process/variable-character"
            (Fn I32 String → Char))
    (extern directory-length
            "snail.core.support"
            "snail:process/directory-length"
            (Fn → I32))
    (extern directory-character
            "snail.core.support"
            "snail:process/directory-character"
            (Fn I32 → Char))

    (define (host-variable (name String)) (→ (Option String))
      (let ((length (variable-length name)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (variable-character (i64->i32 position) name)))))))

    (define (host-directory) (→ (Option String))
      (let ((length (directory-length)))
        (if (< length 0)
            (None)
            (Some (string-generate (i32->i64 length)
                                   (lambda (position)
                                     (directory-character (i64->i32 position))))))))

    ))
