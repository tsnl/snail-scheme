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
    (struct IgnoreSnapshot
      ((prefix String)
       (paths (Table Unit))))

    ;; None means Git is unavailable or the directory is outside a worktree.
    ;; Once a repository is found, failures are errors, never partial results.
    (: read-gitignore
       (impl (Fn String -> (Result (Option IgnoreSnapshot) String) ! mut tasks process)))
    (define (read-gitignore directory)
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
    (: worktree-prefix (impl (Fn Captured -> (Result (Option String) String))))
    (define (worktree-prefix result)
      (match (::exit result)
        ((Exited 128) (Ok (None)))
        ((Exited 0)
         (match (decoded (::stdout result))
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
    (: project-prefix (impl (Fn String -> (Result String String))))
    (define (project-prefix text)
      (let ((length (string-length text)))
        (if (and (> length 0) (char=? (string-ref text (- length 1)) #\newline)
                 (or (= length 1) (char=? (string-ref text (- length 2)) #\/)))
            (Ok (substring text 0 (- length 1)))
            (Err "gitignore: malformed project prefix"))))

    ;; Git changes directories physically. Each slash in its normalized prefix
    ;; names one parent back to the root, even if the caller used a symlink.
    (: back-to-root (impl (Fn String -> String)))
    (define (back-to-root prefix)
      (fold-left (lambda (path char) (if (char=? char #\/) (string-append path "../") path))
                 "./" (string->list prefix)))

    ;; Query from the worktree root: Git fails when ls-files starts deep
    ;; inside a directory excluded by an ancestor. A literal pathspec limits
    ;; the traversal to this project, even if its name contains glob syntax.
    ;; Its trailing slash must go too, or Git repeats that prefix failure.
    (: query-ignored
       (impl (Fn String String -> (Result (Option IgnoreSnapshot) String) ! mut tasks process)))
    (define (query-ignored directory prefix)
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
         (match (::exit result)
           ((Exited 0)
            (match (decoded (::stdout result))
              ((Err message) (Err message))
              ((Ok paths) (parse-paths prefix paths))))
           (_ (Err (git-failure result)))))))

    (: ignored? (impl (Fn IgnoreSnapshot String -> Bool)))
    (define (ignored? snapshot relative)
      (let* ((path (string-append (::prefix snapshot) relative))
             (paths (::paths snapshot)))
        (or (table-contains? paths path)
            (table-contains? paths (string-append path "/"))
            (let loop ((at 0))
              (and (< at (string-length path))
                   (or (and (char=? (string-ref path at) #\/)
                            (table-contains? paths (substring path 0 (+ at 1))))
                       (loop (+ at 1))))))))

    ;; NUL framing preserves spaces, newlines, backslashes and Unicode.
    ;; Parse once into membership evidence; a truncated record is an error.
    (: parse-paths (impl (Fn String String -> (Result (Option IgnoreSnapshot) String))))
    (define (parse-paths prefix text)
      (let loop ((start 0) (at 0) (paths empty-table))
        (cond ((= at (string-length text))
               (if (= start at) (Ok (Some (IgnoreSnapshot prefix paths)))
                   (Err "gitignore: truncated path record")))
              ((char=? (string-ref text at) #\null)
               (loop (+ at 1) (+ at 1)
                     (table-set paths (substring text start at) (unit))))
              (else (loop start (+ at 1) paths)))))

    (: decoded (impl (Fn Bytes -> (Result String String))))
    (define (decoded bytes)
      (match (utf8->string bytes)
        ((Ok text) (Ok text))
        ((Err _) (Err "gitignore: Git returned a path that is not UTF-8"))))

    (: git-failure (impl (Fn Captured -> String)))
    (define (git-failure result)
      (match (utf8->string (::stderr result))
        ((Ok text) (string-append "gitignore: Git failed: " text))
        ((Err _) "gitignore: Git failed")))

    ;; ---- Native query ----

    ;; Each query owns its process and pipes. Both readers run while Git
    ;; runs, so a full pipe cannot deadlock it and other service tasks can
    ;; progress. No persistent child, shared cache or shell interpretation.
    (: git-output
       (impl (Fn String (List String) -> (Result (Option Captured) String) ! mut tasks process)))
    (define (git-output directory arguments)
      (match (spawn (Command "git" arguments directory))
        ((Err error)
         (if (string=? (::code error) "ENOENT") (Ok (None))
             (Err (string-append "gitignore: " (::code error)))))
        ((Ok child)
         (close-input child)
         (collect-git child))))

    (: collect-git (impl (Fn Process -> (Result (Option Captured) String) ! mut tasks process)))
    (define (collect-git child)
      (let ((errors (make-mailbox)))
        (dispatch-local
         (once (lambda () (mailbox-post errors (read-pipe child (Stderr) 65536 (Nil))))))
        (let* ((output (read-pipe child (Stdout) 16777216 (Nil)))
               (error (mailbox-receive errors))
               (exit (wait-exit child)))
          (close-process child)
          (match (Pair output error)
            ((Pair (Err message) _) (Err message))
            ((Pair _ (Err message)) (Err message))
            ((Pair (Ok stdout) (Ok stderr))
             (match exit
               ((Ok ended) (Ok (Some (Captured ended stdout stderr))))
               ((Err error) (Err (string-append "gitignore: " (::code error))))))))))

    ;; Close on any read failure so the other reader wakes too. Bounds are
    ;; explicit failures, rather than a quietly truncated exclusion set.
    (: read-pipe
       (impl (Fn Process Stream I64 (List Bytes) -> (Result Bytes String) ! tasks process)))
    (define (read-pipe child stream remaining chunks)
      (match (read-output child stream 65536)
        ((Err error)
         (close-process child)
         (Err (string-append "gitignore: " (::code error))))
        ((Ok (None)) (Ok (vector-concatenate (reverse chunks))))
        ((Ok (Some bytes))
         (if (> (vector-length bytes) remaining)
             (begin (close-process child) (Err "gitignore: Git output exceeds the query limit"))
             (read-pipe child stream (- remaining (vector-length bytes)) (Cons bytes chunks))))))))
