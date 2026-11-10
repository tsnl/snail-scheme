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
    (: text-limit I64)
    (define text-limit 8388608)

    (: revision (impl (Fn String -> String)))
    (define (revision text)
      (bytes->hex (sha256 (string->utf8 text))))

    (: contains? (impl (Fn String Char -> Bool)))
    (define (contains? text char)
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
    (: served-path (impl (Fn String -> (Option ProjectPath))))
    (define (served-path path)
      (if (text-file-name? path) (project-path path) (None)))

    (: project-path (impl (Fn String -> (Option ProjectPath))))
    (define (project-path path)
      (let ((parts (split-at-slashes path)))
        (if (and (every? ordinary-part? parts)
                 (not (under-build? parts))
                 (not (contains? path #\null))
                 (not (contains? path #\\)))
            (Some (ProjectPath path parts))
            (None))))

    (: ordinary-part? (impl (Fn String -> Bool)))
    (define (ordinary-part? part)
      (not (member? part (list "" "." ".." ".git"))))

    ;; The build output at the project's root is not a source.
    (: under-build? (impl (Fn (List String) -> Bool)))
    (define (under-build? parts)
      (member? "build" (take parts 1)))

    (: split-at-slashes (impl (Fn String -> (List String))))
    (define (split-at-slashes path)
      (match (string-index path #\/)
        ((Some at)
         (Cons (substring path 0 at)
               (split-at-slashes (substring path (+ at 1) (string-length path)))))
        ((None) (list path))))

    ;; The extensions of the text files the editor opens, in any case.
    (: text-file-name? (impl (Fn String -> Bool)))
    (define (text-file-name? path)
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

    (: ends-with? (impl (Fn String String -> Bool)))
    (define (ends-with? text suffix)
      (let ((start (- (string-length text) (string-length suffix))))
        (and (>= start 0) (string=? (substring text start (string-length text)) suffix))))

    (: absolute (impl (Fn String ProjectPath -> String)))
    (define (absolute root file)
      (string-append root "/" (::path file)))

    ;; The project's root must still be a directory, and each directory on
    ;; the way to the file a directory itself, not a link, so a path cannot
    ;; leave the project.
    (: check-parents (impl (Fn String ProjectPath -> (Result Unit FileRefusal) ! fs)))
    (define (check-parents root file)
      (match (followed-status root)
        ((Ok status)
         (match (::kind status)
           ((Directory) (check-directories root (::parts file)))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    ;; Every part but the last names a directory.
    (: check-directories (impl (Fn String (List String) -> (Result Unit FileRefusal) ! fs)))
    (define (check-directories directory parts)
      (match parts
        ((Cons name (Cons next rest))
         (let ((inner (string-append directory "/" name)))
           (match (file-status inner)
             ((Ok status)
              (match (::kind status)
                ((Directory) (check-directories inner (Cons next rest)))
                (_ (Err (NotServed "project paths cannot traverse symlinks or non-directories")))))
             ((Err error) (Err (DiskFailed error))))))
        (_ (Ok (unit)))))

    ;; ---- Listing ----

    ;; The paths the service serves among `paths`, which name files under
    ;; the project, as the observer's inventory does: relative to the
    ;; project, and in order.
    (: project-text-paths
       (impl (Fn String (List String) -> (Result (List String) FileRefusal) ! fs)))
    (define (project-text-paths root paths)
      (match (followed-status root)
        ((Ok status)
         (match (::kind status)
           ((Directory) (Ok (list-sort string<? (served-among root paths))))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    (: served-among (impl (Fn String (List String) -> (List String))))
    (define (served-among root paths)
      (let ((prefix (string-append root "/")))
        (fold-right (lambda (path served)
                      (match (served-under prefix path)
                        ((Some file) (Cons (::path file) served))
                        ((None) served)))
                    (Nil)
                    paths)))

    ;; The served path that `path` names, if it is under `prefix`.
    (: served-under (impl (Fn String String -> (Option ProjectPath))))
    (define (served-under prefix path)
      (let ((length (string-length prefix)))
        (if (and (>= (string-length path) length) (string=? (substring path 0 length) prefix))
            (served-path (substring path length (string-length path)))
            (None))))

    ;; Directories in the same inventory, relative to the root. Unlike a
    ;; text path, a directory needs no filename extension.
    (: project-directory-paths (impl (Fn String (List String) -> (List String))))
    (define (project-directory-paths root paths)
      (let ((prefix (string-append root "/")))
        (list-sort string<?
                   (fold-right (lambda (path found)
                                 (let ((size (string-length prefix)))
                                   (if (and (> (string-length path) size)
                                            (string=? (substring path 0 size) prefix))
                                       (match (project-path
                                               (substring path size (string-length path)))
                                         ((Some entry) (Cons (::path entry) found))
                                         ((None) found))
                                       found)))
                               (Nil) paths))))

    ;; ---- Creating ----

    ;; Only one entry is made. Its parent must already be a real project
    ;; directory. Both scalar operations create exclusively, so a racing
    ;; writer cannot have its file or symbolic link replaced.
    (: create-project-file (impl (Fn String String -> (Result Unit FileRefusal) ! fs)))
    (define (create-project-file root path)
      (create-entry root (served-path path) #f))

    (: create-project-directory (impl (Fn String String -> (Result Unit FileRefusal) ! fs)))
    (define (create-project-directory root path)
      (create-entry root (project-path path) #t))

    (: create-entry (impl (Fn String (Option ProjectPath) Bool -> (Result Unit FileRefusal) ! fs)))
    (define (create-entry root found directory)
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
    (: read-project-text (impl (Fn String String -> (Result ProjectText FileRefusal) ! fs)))
    (define (read-project-text root path)
      (match (served-path path)
        ((Some file) (snapshot root file))
        ((None) (Err (NotServed "invalid project text path")))))

    (: snapshot (impl (Fn String ProjectPath -> (Result ProjectText FileRefusal) ! fs)))
    (define (snapshot root file)
      (match (check-parents root file)
        ((Ok _) (current-text root file))
        ((Err refusal) (Err refusal))))

    (: current-text (impl (Fn String ProjectPath -> (Result ProjectText FileRefusal) ! fs)))
    (define (current-text root file)
      (match (read-text-file (absolute root file) text-limit)
        ((Ok text)
         (if (contains? text #\null)
             (Err (NotServed "text files cannot contain NUL bytes"))
             (Ok (ProjectText text (revision text)))))
        ((Err error) (Err (text-refusal error)))))

    (: text-refusal (impl (Fn TextError -> FileRefusal)))
    (define (text-refusal error)
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
    (: save-project-text
       (impl (Fn String String String String -> (Result ProjectText FileRefusal) ! fs modes)))
    (define (save-project-text root path expected text)
      (match (Pair (served-path path) (text-problem text))
        ((Pair _ (Some message)) (Err (NotServed message)))
        ((Pair (Some file) (None)) (save-checked root file expected text))
        ((Pair (None) (None)) (Err (NotServed "invalid project text path")))))

    (: text-problem (impl (Fn String -> (Option String))))
    (define (text-problem text)
      (cond ((contains? text #\null) (Some "expected well-formed text without NUL"))
            ((> (vector-length (string->utf8 text)) text-limit)
             (Some "text files may contain at most 8 MiB"))
            (else (None))))

    (: save-checked
       (impl (Fn String ProjectPath String String -> (Result ProjectText FileRefusal) ! fs modes)))
    (define (save-checked root file expected text)
      (match (staging root)
        ((Ok directory)
         (let ((saved (save-staged root file expected text (string-append directory "/contents"))))
           (remove-tree directory)
           saved))
        ((Err refusal) (Err refusal))))

    ;; The file on disk is still the revision `expected`. A file gone, or
    ;; no longer one the service serves, has changed as much as one with
    ;; other bytes.
    (: expect (impl (Fn String ProjectPath String -> (Result Unit FileRefusal) ! fs)))
    (define (expect root file expected)
      (match (snapshot root file)
        ((Ok current)
         (if (string=? (::revision current) expected) (Ok (unit)) (Err (ChangedOnDisk))))
        ((Err (DiskFailed (NotFound))) (Err (ChangedOnDisk)))
        ((Err (DiskFailed (NotADirectory))) (Err (ChangedOnDisk)))
        ((Err (NotServed _)) (Err (ChangedOnDisk)))
        ((Err refusal) (Err refusal))))

    ;; Writes the text to `staged`, gives it the file's mode once the
    ;; revision is checked, and renames it over the file.
    (: save-staged
       (impl (Fn String
                 ProjectPath
                 String
                 String
                 String
                 ->
                 (Result ProjectText FileRefusal)
                 ! fs modes)))
    (define (save-staged root file expected text staged)
      (match (write-text-file staged text (CreateNew))
        ((Ok _)
         (match (expect root file expected)
           ((Ok _) (replace (absolute root file) staged text))
           ((Err refusal) (Err refusal))))
        ((Err error) (Err (DiskFailed error)))))

    (: replace (impl (Fn String String String -> (Result ProjectText FileRefusal) ! fs modes)))
    (define (replace path staged text)
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
    (: staging (impl (Fn String -> (Result String FileRefusal) ! fs)))
    (define (staging root)
      (let ((build (string-append root "/build")))
        (match (file-status build)
          ((Ok status)
           (match (::kind status)
             ((Directory) (fresh-directory build 0))
             (_ (Err (NotServed "project build output must be a directory, not a link")))))
          ((Err _)
           (match (make-directories build)
             ((Ok _) (fresh-directory build 0))
             ((Err error) (Err (DiskFailed error))))))))

    (: fresh-directory (impl (Fn String I64 -> (Result String FileRefusal) ! fs)))
    (define (fresh-directory build number)
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
      ((mode-character (dyn (Fn Char -> Unit)))
       (mode-end (dyn (Fn -> Unit)))
       (mode-command (dyn (Fn I32 -> I32))))
      (default ((mode-character host-argument-character)
                (mode-end host-argument-end)
                (mode-command host-command))))

    (: mode-command-on (impl (Fn String String I32 -> I32 ! modes)))
    (define (mode-command-on name path number)
      (send-mode-text name)
      (send-mode-text path)
      (mode-command number))

    (: send-mode-text (impl (Fn String -> Unit ! modes)))
    (define (send-mode-text text)
      (for-each mode-character (string->list text))
      (mode-end))

    ;; The permission bits of the file at `path`, following links.
    (: file-mode (impl (Fn String -> (Option I32) ! modes)))
    (define (file-mode path)
      (let ((mode (mode-command-on "mode" path 0)))
        (if (< mode 0) (None) (Some mode))))

    (: set-file-mode (impl (Fn String I32 -> Bool ! modes)))
    (define (set-file-mode path mode)
      (= (mode-command-on "chmod" path mode) 0))

    ))
