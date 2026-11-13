;; A snapshot of ignored disk paths in a Git worktree. Git owns pattern
;; matching, nested rules, standard excludes and the index: tracked files
;; stay visible. This is a native library, not a portable pattern parser.
(define-library (snail shell gitignore)
  (export
   IgnoreSnapshot
   read-gitignore
   ignored?)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail core table)
   (snail shell process)
   (snail shell task)
   (snail shell utf8))
  (begin

    ;; ---- Snapshots ----

    ;; Keys are repository-relative filenames or directory prefixes ending in `/`.
    ;; Git collapses a directory only when it contains no tracked files.
    ;; The project prefix comes from Git, so symlinked project roots work too.
    ;; Callers ask about project-relative paths. A snapshot describes disk
    ;; at the time of the query; it does not predict ignores for new files.
    (record IgnoreSnapshot
      ((prefix String)
       (paths (Table Unit))))

    ;; None means Git is unavailable or the directory is outside a worktree.
    ;; Once a repository is found, failures are errors, never partial results.

    (define (read-gitignore (directory String))
      (→ (Result (Option IgnoreSnapshot) String))
      (! mut host tasks process)
      (match (git-output directory (list "rev-parse" "--is-inside-work-tree" "--show-prefix"))
        ((Err message) (Err message))
        ((Ok (None)) (Ok (None)))
        ((Ok (Some result))
         (match (worktree-prefix result)
           ((Err message) (Err message))
           ((Ok (None)) (Ok (None)))
           ((Ok (Some prefix)) (query-ignored directory prefix))))))

    ;; The first line is fixed vocabulary; the remaining prefix may contain
    ;; newlines. A bare repository and Git's own metadata are not worktrees.

    (define (worktree-prefix (result Captured)) (→ (Result (Option String) String))
      (match (● result exit)
        ((Exited 128) (Ok (None)))
        ((Exited 0)
         (match (decoded (● result stdout))
           ((Err message) (Err message))
           ((Ok text)
            (cond ((and (>= (string-length text) 6) (string=? (substring text 0 6) "false\n"))
                   (Ok (None)))
                  ((and (>= (string-length text) 5) (string=? (substring text 0 5) "true\n"))
                   (match (project-prefix (substring text 5 (string-length text)))
                     ((Ok prefix) (Ok (Some prefix)))
                     ((Err message) (Err message))))
                  (else (Err "gitignore: malformed worktree response"))))))
        (_ (Err (git-failure result)))))

    ;; One final newline frames the prefix; newlines inside names stay intact.

    (define (project-prefix (text String)) (→ (Result String String))
      (let ((length (string-length text)))
        (if (and (> length 0) (char=? (string-ref text (- length 1)) #\newline)
                 (or (= length 1) (char=? (string-ref text (- length 2)) #\/)))
            (Ok (substring text 0 (- length 1)))
            (Err "gitignore: malformed project prefix"))))

    ;; Git changes directories physically. Each slash in its normalized prefix
    ;; names one parent back to the root, even if the caller used a symlink.

    (define (back-to-root (prefix String)) (→ String)
      (fold-left (lambda (path char) (if (char=? char #\/) (string-append path "../") path))
                 "./" (string->list prefix)))

    ;; Query from the worktree root: Git fails when ls-files starts deep
    ;; inside a directory excluded by an ancestor. A literal pathspec limits
    ;; the traversal to this project, even if its name contains glob syntax.
    ;; Its trailing slash must go too, or Git repeats that prefix failure.

    (define (query-ignored (directory String) (prefix String))
      (→ (Result (Option IgnoreSnapshot) String))
      (! mut host tasks process)
      (match (git-output directory (list "-C" (back-to-root prefix) "--literal-pathspecs"
                                         "ls-files" "--others" "--ignored" "--exclude-standard"
                                         "--directory"
                                         "-z"
                                         "--"
                                         (if (string=? prefix "") "."
                                             (substring prefix 0 (- (string-length prefix) 1)))))
        ((Err message) (Err message))
        ((Ok (None)) (Err "gitignore: Git became unavailable during the query"))
        ((Ok (Some result))
         (match (● result exit)
           ((Exited 0)
            (match (decoded (● result stdout))
              ((Err message) (Err message))
              ((Ok paths) (parse-paths prefix paths))))
           (_ (Err (git-failure result)))))))

    (define (ignored? (snapshot IgnoreSnapshot) (relative String)) (→ Bool)
      (let* ((path (string-append (● snapshot prefix) relative))
             (paths (● snapshot paths)))
        (or (table-contains? paths path)
            (table-contains? paths (string-append path "/"))
            (let loop ((at 0))
              (and (< at (string-length path))
                   (or (and (char=? (string-ref path at) #\/)
                            (table-contains? paths (substring path 0 (+ at 1))))
                       (loop (+ at 1))))))))

    ;; NUL framing preserves spaces, newlines, backslashes and Unicode.
    ;; Parse once into membership evidence; a truncated record is an error.

    (define (parse-paths (prefix String) (text String)) (→ (Result (Option IgnoreSnapshot) String))
      (let loop ((start 0) (at 0) (paths (empty-table)))
        (cond ((= at (string-length text))
               (if (= start at) (Ok (Some (new IgnoreSnapshot (prefix prefix) (paths paths))))
                   (Err "gitignore: truncated path record")))
              ((char=? (string-ref text at) #\null)
               (loop (+ at 1) (+ at 1)
                     (table-set paths (substring text start at) (unit))))
              (else (loop start (+ at 1) paths)))))

    (define (decoded (bytes Bytes)) (→ (Result String String))
      (match (utf8->string bytes)
        ((Ok text) (Ok text))
        ((Err _) (Err "gitignore: Git returned a path that is not UTF-8"))))

    (define (git-failure (result Captured)) (→ String)
      (match (utf8->string (● result stderr))
        ((Ok text) (string-append "gitignore: Git failed: " text))
        ((Err _) "gitignore: Git failed")))

    ;; ---- Native query ----

    ;; Each query owns its process and pipes. Both readers run while Git
    ;; runs, so a full pipe cannot deadlock it and other service tasks can
    ;; progress. No persistent child, shared cache or shell interpretation.

    (define (git-output (directory String) (arguments (List String)))
      (→ (Result (Option Captured) String))
      (! mut host tasks process)
      (match (spawn (new Command (program "git") (arguments arguments) (directory directory)))
        ((Err error)
         (if (string=? (● error code) "ENOENT") (Ok (None))
             (Err (string-append "gitignore: " (● error code)))))
        ((Ok child)
         (close-input child)
         (collect-git child))))

    (define (collect-git (child Process))
      (→ (Result (Option Captured) String))
      (! mut host tasks process)
      (let ((errors (make-mailbox)))
        (dispatch-local
         (once (lambda () (mailbox-post errors (read-pipe child (Stderr) 65536 (Nil))))))
        (let* ((output (read-pipe child (Stdout) 16777216 (Nil)))
               (error (mailbox-receive errors))
               (exit (wait-exit child)))
          (close-process child)
          (match (new Pair (first output) (second error))
            ((Pair (Err message) _) (Err message))
            ((Pair _ (Err message)) (Err message))
            ((Pair (Ok stdout) (Ok stderr))
             (match exit
               ((Ok ended) (Ok (Some (new Captured (exit ended) (stdout stdout) (stderr stderr)))))
               ((Err error) (Err (string-append "gitignore: " (● error code))))))))))

    ;; Close on any read failure so the other reader wakes too. Bounds are
    ;; explicit failures, rather than a quietly truncated exclusion set.

    (define (read-pipe (child Process) (stream Stream) (remaining I64) (chunks (List Bytes)))
      (→ (Result Bytes String))
      (! tasks process)
      (match (read-output child stream 65536)
        ((Err error)
         (close-process child)
         (Err (string-append "gitignore: " (● error code))))
        ((Ok (None)) (Ok (vector-concatenate (reverse chunks))))
        ((Ok (Some bytes))
         (if (> (vector-length bytes) remaining)
             (begin (close-process child) (Err "gitignore: Git output exceeds the query limit"))
             (read-pipe child stream (- remaining (vector-length bytes)) (Cons bytes chunks))))))))
