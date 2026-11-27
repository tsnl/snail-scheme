;; A named base identifies a repository. Git records its checkout path in
;; .gitmodules and its commit in the parent tree. Only the path is needed
;; here. Git parses its own configuration file without contacting a remote.
(define-library (snail shell project submodule)
  (export
   base-checkout-path)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell compiler read) Loc compile-error)
   (only (snail shell process) Processes Command Exited)
   (only (snail shell text) string-downcase)
   (only (snail shell utf8) utf8->string))
  (begin

    ;; ---- Base references ----

    (define (base-checkout-path (processes Processes)
                                (fs Fs)
                                (root String)
                                (reference String)
                                (loc Loc))
      (→ String)
      (let ((text (string-downcase reference)) (prefix "github.com:"))
        (if (prefix? text prefix)
            (let ((name (substring text (string-length prefix) (string-length text))))
              (github-checkout processes fs root (github-name name loc) loc))
            reference)))

    (define (github-checkout (processes Processes) (fs Fs) (root String) (repo String) (loc Loc))
      (→ String)
      (let ((file (string-append root "/.gitmodules"))
            (reference (string-append "github.com:" repo)))
        (match (matching-paths (submodule-fields processes file loc) repo loc)
          ((Cons path (Nil)) (submodule-checkout fs root path reference loc))
          ((Nil) (compile-error loc (string-append "no submodule for " reference " in " file
                                                   ". Add it with git submodule add https://github.com/"
                                                   repo
                                                   ".git or use a local path.")))
          (paths (compile-error loc (string-append reference " matches multiple submodules: "
                                                   (string-join paths ", ")
                                                   ". Use a local path."))))))

    (define (github-name (name String) (loc Loc)) (→ String)
      (let ((id (without-suffix (without-suffix name "/") ".git")))
        (match (string-index id #\/)
          ((Some slash)
           (if (and (component? (substring id 0 slash))
                    (component? (substring id (+ slash 1) (string-length id))))
               id (compile-error loc "expected github.com:OWNER/REPO")))
          ((None) (compile-error loc "expected github.com:OWNER/REPO")))))

    (define (component? (part String)) (→ Bool)
      (and (not (member? part (list "" "." "..")))
           (every? (lambda (c) (or (and (<= #\a c) (<= c #\z))
                                   (and (<= #\0 c) (<= c #\9))
                                   (member? c (list #\- #\_ #\.)))) (string->list part))))

    (define (url-names? (url String) (repo String)) (→ Bool)
      (let ((remote (without-suffix (without-suffix (string-downcase url) "/") ".git")))
        (any? (lambda (prefix) (string=? remote (string-append prefix repo)))
              (list "https://github.com/" "https://github.com:443/" "git@github.com:"
                    "ssh://git@github.com/" "ssh://git@github.com:22/"))))

    (define (prefix? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (without-suffix (text String) (suffix String)) (→ String)
      (let ((end (- (string-length text) (string-length suffix))))
        (if (and (>= end 0) (string=? (substring text end (string-length text)) suffix))
            (substring text 0 end) text)))

    ;; ---- Reading .gitmodules ----

    (type Fields (List (Pair String String)))

    (define (submodule-fields (processes Processes) (file String) (loc Loc)) (→ Fields)
      (let ((command (new Command (program "git") (directory ".")
                          (arguments (list "config" "--no-includes" "--null" "--file" file
                                           "--get-regexp" "^submodule\\..*\\.(path|url)$")))))
        (match ((● processes run) command #u8())
          ((Err error) (compile-error loc (string-append "cannot run git config: " (● error code))))
          ((Ok result)
           (match (● result exit)
             ((Exited 1) (Nil))
             ((Exited 0) (match (utf8->string (● result stdout))
                           ((Ok text) (config-fields text loc))
                           ((Err _) (compile-error loc (string-append file " must be UTF-8")))))
             (_ (compile-error loc (string-append "git config could not read " file))))))))

    ;; Git returns KEY, a newline, VALUE and a NUL. Subsection names can
    ;; contain spaces and dots. A quoted path can even contain a newline.
    (define (config-fields (text String) (loc Loc)) (→ Fields)
      (if (string=? text "") (Nil)
          (match (string-index text #\null)
            ((Some end)
             (let ((entry (substring text 0 end)))
               (match (string-index entry #\newline)
                 ((Some cut)
                  (Cons (new Pair (first (substring entry 0 cut))
                             (second (substring entry (+ cut 1) end)))
                        (config-fields (substring text (+ end 1) (string-length text)) loc)))
                 ((None) (compile-error loc "expected a value from git config")))))
            ((None) (compile-error loc "incomplete output from git config")))))

    (define (matching-paths (fields Fields) (repo String) (loc Loc)) (→ (List String))
      (let loop ((entries fields) (paths (Nil)))
        (match entries
          ((Nil) (delete-duplicates string=? (reverse paths)))
          ((Cons (Pair key value) rest)
           (let ((section (without-suffix key ".url")))
             (if (and (not (string=? section key)) (url-names? value repo))
                 (match (assoc-ref fields (string-append section ".path"))
                   ((Some path) (loop rest (Cons path paths)))
                   ((None) (compile-error loc (string-append "missing path for " section))))
                 (loop rest paths)))))))

    (define (submodule-checkout (fs Fs) (root String) (path String) (reference String) (loc Loc))
      (→ String)
      (when (or (string=? path "") (char=? (string-ref path 0) #\/))
        (compile-error loc "expected a relative submodule path in .gitmodules"))
      (match (list-directory fs (string-append root "/" path))
        ((Ok (Cons _ _)) path)
        ((Err (NotFound)) (uninitialized reference path loc))
        ((Ok (Nil)) (uninitialized reference path loc))
        ((Err error) (compile-error loc (string-append path ": " (show error))))))

    (define (uninitialized (reference String) (path String) (loc Loc)) (→ String)
      (compile-error loc (string-append reference " is not checked out at " path
                                        ". Run git submodule update --init --recursive.")))

    ))
