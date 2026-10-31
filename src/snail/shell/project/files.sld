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
   ProjectText-text
   ProjectText-revision
   FileRefusal
   ChangedOnDisk
   NotServed
   DiskFailed
   text-limit
   project-text-paths
   read-project-text
   save-project-text
   file-mode
   set-file-mode)
  (import
   (snail core base)
   (prefix (snail runtime native files) host-)
   (snail core io)
   (snail shell sha256)
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

    (: revision (-> String String))
    (define (revision text)
      (bytes->hex (sha256 (string->utf8 text))))

    (: contains? (-> String Char Bool))
    (define (contains? text char)
      (match (string-index text char)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Served paths ----

    ;; A path the service serves: relative to the project, split at its
    ;; slashes, with no empty, `.` or `..` part and nothing under a `.git`,
    ;; nor under the build output at the project's root, and naming a text
    ;; file by its extension. A backslash or NUL is refused, so the path
    ;; means the same on every host. Constructing one is the check.
    (struct ServedPath
      ((path String)
       (parts (List String))))

    (: served-path (-> String (Option ServedPath)))
    (define (served-path path)
      (let ((parts (split-at-slashes path)))
        (if (and (every? ordinary-part? parts)
                 (not (under-build? parts))
                 (text-file-name? path)
                 (not (contains? path #\null))
                 (not (contains? path #\\)))
            (Some (ServedPath path parts))
            (None))))

    (: ordinary-part? (-> String Bool))
    (define (ordinary-part? part)
      (not (member? part (list "" "." ".." ".git"))))

    ;; The build output at the project's root is not a source.
    (: under-build? (-> (List String) Bool))
    (define (under-build? parts)
      (member? "build" (take parts 1)))

    (: split-at-slashes (-> String (List String)))
    (define (split-at-slashes path)
      (match (string-index path #\/)
        ((Some at)
         (Cons (substring path 0 at)
               (split-at-slashes (substring path (+ at 1) (string-length path)))))
        ((None) (list path))))

    ;; The extensions of the text files the editor opens, in any case.
    (: text-file-name? (-> String Bool))
    (define (text-file-name? path)
      (let ((name (string-downcase path)))
        (any? (lambda (extension) (ends-with? name (string-append "." extension)))
              (list "sld" "scm" "datum" "html" "css" "js" "mjs" "json" "svg" "txt" "md"))))

    (: ends-with? (-> String String Bool))
    (define (ends-with? text suffix)
      (let ((start (- (string-length text) (string-length suffix))))
        (and (>= start 0) (string=? (substring text start (string-length text)) suffix))))

    (: absolute (-> String ServedPath String))
    (define (absolute root file)
      (string-append root "/" (ServedPath-path file)))

    ;; The project's root must still be a directory, and each directory on
    ;; the way to the file a directory itself, not a link, so a path cannot
    ;; leave the project.
    (: check-parents (-> String ServedPath (Result Unit FileRefusal) ! fs))
    (define (check-parents root file)
      (match (followed-status root)
        ((Ok status)
         (match (FileStatus-kind status)
           ((Directory) (check-directories root (ServedPath-parts file)))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    ;; Every part but the last names a directory.
    (: check-directories (-> String (List String) (Result Unit FileRefusal) ! fs))
    (define (check-directories directory parts)
      (match parts
        ((Cons name (Cons next rest))
         (let ((inner (string-append directory "/" name)))
           (match (file-status inner)
             ((Ok status)
              (match (FileStatus-kind status)
                ((Directory) (check-directories inner (Cons next rest)))
                (_ (Err (NotServed "project paths cannot traverse symlinks or non-directories")))))
             ((Err error) (Err (DiskFailed error))))))
        (_ (Ok (unit)))))

    ;; ---- Listing ----

    ;; The paths the service serves among `paths`, which name files under
    ;; the project, as the observer's inventory does: relative to the
    ;; project, and in order.
    (: project-text-paths (-> String (List String) (Result (List String) FileRefusal) ! fs))
    (define (project-text-paths root paths)
      (match (followed-status root)
        ((Ok status)
         (match (FileStatus-kind status)
           ((Directory) (Ok (sort-strings (served-among root paths))))
           (_ (Err (NotServed "the project root must remain a directory")))))
        ((Err error) (Err (DiskFailed error)))))

    (: served-among (-> String (List String) (List String)))
    (define (served-among root paths)
      (let ((prefix (string-append root "/")))
        (fold-right (lambda (path served)
                      (match (served-under prefix path)
                        ((Some file) (Cons (ServedPath-path file) served))
                        ((None) served)))
                    (Nil)
                    paths)))

    ;; The served path that `path` names, if it is under `prefix`.
    (: served-under (-> String String (Option ServedPath)))
    (define (served-under prefix path)
      (let ((length (string-length prefix)))
        (if (and (>= (string-length path) length) (string=? (substring path 0 length) prefix))
            (served-path (substring path length (string-length path)))
            (None))))

    ;; ---- Reading ----

    ;; The text of the file at `path`, relative to the project at `root`.
    (: read-project-text (-> String String (Result ProjectText FileRefusal) ! fs))
    (define (read-project-text root path)
      (match (served-path path)
        ((Some file) (snapshot root file))
        ((None) (Err (NotServed "invalid project text path")))))

    (: snapshot (-> String ServedPath (Result ProjectText FileRefusal) ! fs))
    (define (snapshot root file)
      (match (check-parents root file)
        ((Ok _) (current-text root file))
        ((Err refusal) (Err refusal))))

    (: current-text (-> String ServedPath (Result ProjectText FileRefusal) ! fs))
    (define (current-text root file)
      (match (read-text-file (absolute root file) text-limit)
        ((Ok text)
         (if (contains? text #\null)
             (Err (NotServed "text files cannot contain NUL bytes"))
             (Ok (ProjectText text (revision text)))))
        ((Err error) (Err (text-refusal error)))))

    (: text-refusal (-> TextError FileRefusal))
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
       (-> String String String String (Result ProjectText FileRefusal) ! fs modes))
    (define (save-project-text root path expected text)
      (match (Pair (served-path path) (text-problem text))
        ((Pair _ (Some message)) (Err (NotServed message)))
        ((Pair (Some file) (None)) (save-checked root file expected text))
        ((Pair (None) (None)) (Err (NotServed "invalid project text path")))))

    (: text-problem (-> String (Option String)))
    (define (text-problem text)
      (cond ((contains? text #\null) (Some "expected well-formed text without NUL"))
            ((> (vector-length (string->utf8 text)) text-limit)
             (Some "text files may contain at most 8 MiB"))
            (else (None))))

    (: save-checked
       (-> String ServedPath String String (Result ProjectText FileRefusal) ! fs modes))
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
    (: expect (-> String ServedPath String (Result Unit FileRefusal) ! fs))
    (define (expect root file expected)
      (match (snapshot root file)
        ((Ok current)
         (if (string=? (ProjectText-revision current) expected) (Ok (unit)) (Err (ChangedOnDisk))))
        ((Err (DiskFailed (NotFound))) (Err (ChangedOnDisk)))
        ((Err (DiskFailed (NotADirectory))) (Err (ChangedOnDisk)))
        ((Err (NotServed _)) (Err (ChangedOnDisk)))
        ((Err refusal) (Err refusal))))

    ;; Writes the text to `staged`, gives it the file's mode once the
    ;; revision is checked, and renames it over the file.
    (: save-staged
       (-> String ServedPath String String String (Result ProjectText FileRefusal) ! fs modes))
    (define (save-staged root file expected text staged)
      (match (write-text-file staged text)
        ((Ok _)
         (match (expect root file expected)
           ((Ok _) (replace (absolute root file) staged text))
           ((Err refusal) (Err refusal))))
        ((Err error) (Err (DiskFailed error)))))

    (: replace (-> String String String (Result ProjectText FileRefusal) ! fs modes))
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
    (: staging (-> String (Result String FileRefusal) ! fs))
    (define (staging root)
      (let ((build (string-append root "/build")))
        (match (file-status build)
          ((Ok status)
           (match (FileStatus-kind status)
             ((Directory) (fresh-directory build 0))
             (_ (Err (NotServed "project build output must be a directory, not a link")))))
          ((Err _)
           (match (make-directories build)
             ((Ok _) (fresh-directory build 0))
             ((Err error) (Err (DiskFailed error))))))))

    (: fresh-directory (-> String I64 (Result String FileRefusal) ! fs))
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
      ((mode-character (-> Char Unit))
       (mode-end (-> Unit))
       (mode-command (-> I32 I32)))
      (default ((mode-character host-argument-character)
                (mode-end host-argument-end)
                (mode-command host-command))))

    (: mode-command-on (-> String String I32 I32 ! modes))
    (define (mode-command-on name path number)
      (send-mode-text name)
      (send-mode-text path)
      (mode-command number))

    (: send-mode-text (-> String Unit ! modes))
    (define (send-mode-text text)
      (for-each mode-character (string->list text))
      (mode-end))

    ;; The permission bits of the file at `path`, following links.
    (: file-mode (-> String (Option I32) ! modes))
    (define (file-mode path)
      (let ((mode (mode-command-on "mode" path 0)))
        (if (< mode 0) (None) (Some mode))))

    (: set-file-mode (-> String I32 Bool ! modes))
    (define (set-file-mode path mode)
      (= (mode-command-on "chmod" path mode) 0))

    ;; ---- Sorting ----

    (: sort-strings (-> (List String) (List String)))
    (define (sort-strings strings)
      (if (<= (length strings) 1)
          strings
          (let ((half (quotient (length strings) 2)))
            (merge-strings (sort-strings (take strings half))
                           (sort-strings (list-drop strings half))))))

    (: merge-strings (-> (List String) (List String) (List String)))
    (define (merge-strings left right)
      (match (Pair left right)
        ((Pair (Nil) _) right)
        ((Pair _ (Nil)) left)
        ((Pair (Cons a left-rest) (Cons b right-rest))
         (if (string<? b a)
             (Cons b (merge-strings left right-rest))
             (Cons a (merge-strings left-rest right))))))))
