;; The text files of one project, as `snail dev`'s editor reads and saves
;; them. Disk is authoritative: the service keeps no buffers. A read gives
;; a file's text and its revision, which names the file's bytes, and a save
;; names the revision it replaces, so a save over a file that changed
;; since it was read is refused rather than lost. A save is written beside
;; the build output and renamed over the file, so a build never reads half
;; of one, and the file keeps its mode.
(define-library (snail shell project files)
  (export
   modes
   ProjectText
   FileRefusal
   ChangedOnDisk
   NotServed
   DiskFailed
   text-limit
   project-text-paths
   project-directory-paths
   create-project-file
   create-project-directory
   read-project-text
   save-project-text
   file-mode
   set-file-mode)
  (import
   (snail core base)
   (prefix (snail runtime native files) host-)
   (snail core io)
   (snail shell compiler sha256)
   (snail shell text)
   (snail shell utf8))
  (begin

    ;; ---- Texts and refusals ----

    ;; A file's text and its revision: the lowercase hex SHA-256 digest of
    ;; its bytes. Two versions with the same bytes are one revision, since
    ;; saving over either loses nothing.
    (struct ProjectText
      ((text String)
       (revision String)))

    ;; Why a request was refused: the file is not the revision the request
    ;; names, or the service does not serve the path or the text, or the
    ;; filesystem failed.
    (enum FileRefusal
      (ChangedOnDisk)
      (NotServed
       ((message String)))
      (DiskFailed
       ((error FileError))))

    ;; The most bytes a text file served may hold: 8 MiB.

    (define (text-limit) (→ I64) 8388608)

    (define (revision (text String)) (→ String)
      (bytes->hex (sha256 (string->utf8 text))))

    (define (contains? (text String) (char Char)) (→ Bool)
      (match (string-index text char)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Served paths ----

    ;; A path the service serves: relative to the project, split at its
    ;; slashes, with no empty, `.` or `..` part and nothing under a `.git`,
    ;; nor under the build output at the project's root. A backslash or
    ;; NUL is refused, so the path
    ;; means the same on every host. Constructing one is the check.
    (struct ProjectPath
      ((path String)
       (parts (List String))))

    ;; Text requests additionally require an extension the editor serves.

    (define (served-path (path String)) (→ (Option ProjectPath))
      (if (text-file-name? path) (project-path path) (None)))

    (define (project-path (path String)) (→ (Option ProjectPath))
      (let ((parts (split-at-slashes path)))
        (if (and (every? ordinary-part? parts)
                 (not (under-build? parts))
                 (not (contains? path #\null))
                 (not (contains? path #\\)))
            (Some (ProjectPath path parts))
            (None))))

    (define (ordinary-part? (part String)) (→ Bool)
      (not (member? part (list "" "." ".." ".git"))))

    ;; The build output at the project's root is not a source.

    (define (under-build? (parts (List String))) (→ Bool)
      (member? "build" (take parts 1)))

    (define (split-at-slashes (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some at)
         (Cons (substring path 0 at)
               (split-at-slashes (substring path (+ at 1) (string-length path)))))
        ((None) (list path))))

    ;; The extensions of the text files the editor opens, in any case.

    (define (text-file-name? (path String)) (→ Bool)
      (let ((name (string-downcase path)))
        (or (string=? path ".gitignore") (ends-with? path "/.gitignore")
            (any? (lambda (extension) (ends-with? name (string-append "." extension)))
                  (list "sld"
                        "scm"
                        "datum"
                        "html"
                        "css"
                        "js"
                        "mjs"
                        "json"
                        "webmanifest"
                        "svg"
                        "txt"
                        "md")))))

    (define (ends-with? (text String) (suffix String)) (→ Bool)
      (let ((start (- (string-length text) (string-length suffix))))
        (and (>= start 0) (string=? (substring text start (string-length text)) suffix))))

    (define (absolute (root String) (file ProjectPath)) (→ String)
      (string-append root "/" (● file path)))

    ;; The project's root must still be a directory, and each directory on
    ;; the way to the file a directory itself, not a link, so a path cannot
    ;; leave the project.

    (define (check-parents (root String) (file ProjectPath)) (→ (Result Unit FileRefusal)) (! fs)
      (match (followed-status root)
        ((Ok status)
         (match (● status kind)
           ((Directory) (check-directories root (● file parts)))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    ;; Every part but the last names a directory.

    (define (check-directories (directory String) (parts (List String)))
      (→ (Result Unit FileRefusal))
      (! fs)
      (match parts
        ((Cons name (Cons next rest))
         (let ((inner (string-append directory "/" name)))
           (match (file-status inner)
             ((Ok status)
              (match (● status kind)
                ((Directory) (check-directories inner (Cons next rest)))
                (_ (Err (NotServed "project paths cannot traverse symlinks or non-directories")))))
             ((Err error) (Err (DiskFailed error))))))
        (_ (Ok (unit)))))

    ;; ---- Listing ----

    ;; The paths the service serves among `paths`, which name files under
    ;; the project, as the observer's inventory does: relative to the
    ;; project, and in order.

    (define (project-text-paths (root String) (paths (List String)))
      (→ (Result (List String) FileRefusal))
      (! fs)
      (match (followed-status root)
        ((Ok status)
         (match (● status kind)
           ((Directory) (Ok (list-sort string<? (served-among root paths))))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    (define (served-among (root String) (paths (List String))) (→ (List String))
      (let ((prefix (string-append root "/")))
        (fold-right (lambda (path served)
                      (match (served-under prefix path)
                        ((Some file) (Cons (● file path) served))
                        ((None) served)))
                    (Nil)
                    paths)))

    ;; The served path that `path` names, if it is under `prefix`.

    (define (served-under (prefix String) (path String)) (→ (Option ProjectPath))
      (let ((length (string-length prefix)))
        (if (and (>= (string-length path) length) (string=? (substring path 0 length) prefix))
            (served-path (substring path length (string-length path)))
            (None))))

    ;; Directories in the same inventory, relative to the root. Unlike a
    ;; text path, a directory needs no filename extension.

    (define (project-directory-paths (root String) (paths (List String))) (→ (List String))
      (let ((prefix (string-append root "/")))
        (list-sort string<?
                   (fold-right (lambda (path found)
                                 (let ((size (string-length prefix)))
                                   (if (and (> (string-length path) size)
                                            (string=? (substring path 0 size) prefix))
                                       (match (project-path
                                               (substring path size (string-length path)))
                                         ((Some entry) (Cons (● entry path) found))
                                         ((None) found))
                                       found)))
                               (Nil) paths))))

    ;; ---- Creating ----

    ;; Only one entry is made. Its parent must already be a real project
    ;; directory. Both scalar operations create exclusively, so a racing
    ;; writer cannot have its file or symbolic link replaced.

    (define (create-project-file (root String) (path String)) (→ (Result Unit FileRefusal)) (! fs)
      (create-entry root (served-path path) #f))

    (define (create-project-directory (root String) (path String))
      (→ (Result Unit FileRefusal))
      (! fs)
      (create-entry root (project-path path) #t))

    (define (create-entry (root String) (found (Option ProjectPath)) (directory Bool))
      (→ (Result Unit FileRefusal))
      (! fs)
      (match found
        ((None) (Err (NotServed "invalid project path or unsupported text extension")))
        ((Some path)
         (match (check-parents root path)
           ((Err refusal) (Err refusal))
           ((Ok _)
            (match (if directory
                       (make-directory (absolute root path))
                       (write-text-file (absolute root path) "" (CreateNew)))
              ((Ok _) (Ok (unit)))
              ((Err error) (Err (DiskFailed error)))))))))

    ;; ---- Reading ----

    ;; The text of the file at `path`, relative to the project at `root`.

    (define (read-project-text (root String) (path String))
      (→ (Result ProjectText FileRefusal))
      (! fs)
      (match (served-path path)
        ((Some file) (snapshot root file))
        ((None) (Err (NotServed "invalid project text path")))))

    (define (snapshot (root String) (file ProjectPath)) (→ (Result ProjectText FileRefusal)) (! fs)
      (match (check-parents root file)
        ((Ok _) (current-text root file))
        ((Err refusal) (Err refusal))))

    (define (current-text (root String) (file ProjectPath))
      (→ (Result ProjectText FileRefusal))
      (! fs)
      (match (read-text-file (absolute root file) (text-limit))
        ((Ok text)
         (if (contains? text #\null)
             (Err (NotServed "text files cannot contain NUL bytes"))
             (Ok (ProjectText text (revision text)))))
        ((Err error) (Err (text-refusal error)))))

    (define (text-refusal (error TextError)) (→ FileRefusal)
      (match error
        ((ReadFailed error) (DiskFailed error))
        ((NotRegularFile) (NotServed "expected a regular project file"))
        ((TooLong) (NotServed "text files may contain at most 8 MiB"))
        ((NotText) (NotServed "expected valid UTF-8 text"))
        ((ChangedWhileRead) (ChangedOnDisk))))

    ;; ---- Saving ----

    ;; Replaces the file at `path` with `text`, if the file is still the
    ;; revision `expected`, and gives the text with its new revision. The
    ;; revision is checked once the text is written, just before the
    ;; rename. Rename is atomic, not compare-and-replace: a writer outside
    ;; the service can race that check.

    (define (save-project-text (root String) (path String) (expected String) (text String))
      (→ (Result ProjectText FileRefusal))
      (! fs modes)
      (match (Pair (served-path path) (text-problem text))
        ((Pair _ (Some message)) (Err (NotServed message)))
        ((Pair (Some file) (None)) (save-checked root file expected text))
        ((Pair (None) (None)) (Err (NotServed "invalid project text path")))))

    (define (text-problem (text String)) (→ (Option String))
      (cond ((contains? text #\null) (Some "expected well-formed text without NUL"))
            ((> (vector-length (string->utf8 text)) (text-limit))
             (Some "text files may contain at most 8 MiB"))
            (else (None))))

    (define (save-checked (root String) (file ProjectPath) (expected String) (text String))
      (→ (Result ProjectText FileRefusal))
      (! fs modes)
      (match (staging root)
        ((Ok directory)
         (let ((saved (save-staged root file expected text (string-append directory "/contents"))))
           (remove-tree directory)
           saved))
        ((Err refusal) (Err refusal))))

    ;; The file on disk is still the revision `expected`. A file gone, or
    ;; no longer one the service serves, has changed as much as one with
    ;; other bytes.

    (define (expect (root String) (file ProjectPath) (expected String))
      (→ (Result Unit FileRefusal))
      (! fs)
      (match (snapshot root file)
        ((Ok current)
         (if (string=? (● current revision) expected) (Ok (unit)) (Err (ChangedOnDisk))))
        ((Err (DiskFailed (NotFound))) (Err (ChangedOnDisk)))
        ((Err (DiskFailed (NotADirectory))) (Err (ChangedOnDisk)))
        ((Err (NotServed _)) (Err (ChangedOnDisk)))
        ((Err refusal) (Err refusal))))

    ;; Writes the text to `staged`, gives it the file's mode once the
    ;; revision is checked, and renames it over the file.

    (define (save-staged (root String)
                         (file ProjectPath)
                         (expected String)
                         (text String)
                         (staged String))
      (→ (Result ProjectText FileRefusal))
      (! fs modes)
      (match (write-text-file staged text (CreateNew))
        ((Ok _)
         (match (expect root file expected)
           ((Ok _) (replace (absolute root file) staged text))
           ((Err refusal) (Err refusal))))
        ((Err error) (Err (DiskFailed error)))))

    (define (replace (path String) (staged String) (text String))
      (→ (Result ProjectText FileRefusal))
      (! fs modes)
      (match (file-mode path)
        ((Some mode)
         (if (set-file-mode staged mode)
             (match (rename-file staged path)
               ((Ok _) (Ok (ProjectText text (revision text))))
               ((Err error) (Err (DiskFailed error))))
             (Err (DiskFailed (OtherError)))))
        ((None) (Err (DiskFailed (OtherError))))))

    ;; A directory of this save's own under the build output, which builds
    ;; and the listing leave out, so a partial save is never a source.

    (define (staging (root String)) (→ (Result String FileRefusal)) (! fs)
      (let ((build (string-append root "/build")))
        (match (file-status build)
          ((Ok status)
           (match (● status kind)
             ((Directory) (fresh-directory build 0))
             (_ (Err (NotServed "project build output must be a directory, not a link")))))
          ((Err _)
           (match (make-directories build)
             ((Ok _) (fresh-directory build 0))
             ((Err error) (Err (DiskFailed error))))))))

    (define (fresh-directory (build String) (number I64)) (→ (Result String FileRefusal)) (! fs)
      (let ((directory (string-append build "/.snail-edit-" (show number))))
        (match (make-directory directory)
          ((Ok _) (Ok directory))
          ((Err (AlreadyExists)) (fresh-directory build (+ number 1)))
          ((Err error) (Err (DiskFailed error))))))

    ;; ---- Modes ----

    ;; What WASI cannot do: read and set a file's permission bits, so a
    ;; save keeps the mode of the file it replaces. A command is a name and
    ;; a path, each sent a character at a time, and a number; the host
    ;; answers with a number, -1 for a failure. Only Node implements it.
    (effect modes
      ((mode-character (Fn Char → Unit))
       (mode-end (Fn → Unit))
       (mode-command (Fn I32 → I32)))
      (default ((mode-character host-argument-character)
                (mode-end host-argument-end)
                (mode-command host-command))))

    (define (mode-command-on (name String) (path String) (number I32)) (→ I32) (! modes)
      (send-mode-text name)
      (send-mode-text path)
      (mode-command number))

    (define (send-mode-text (text String)) (→ Unit) (! modes)
      (for-each mode-character (string->list text))
      (mode-end))

    ;; The permission bits of the file at `path`, following links.

    (define (file-mode (path String)) (→ (Option I32)) (! modes)
      (let ((mode (mode-command-on "mode" path 0)))
        (if (< mode 0) (None) (Some mode))))

    (define (set-file-mode (path String) (mode I32)) (→ Bool) (! modes)
      (= (mode-command-on "chmod" path mode) 0))

    ))
