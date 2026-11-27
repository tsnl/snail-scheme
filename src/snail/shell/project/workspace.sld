;; Each workspace adds its src/ to one local chain. Once the directories
;; agree on every shared path, the compiler can use its ordinary lookup.
(define-library (snail shell project workspace)
  (export
   workspace-above
   workspace-directories
   directory-of
   split-path)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell compiler read) Loc Syntax Form Ident Atom DString compile-error read-text))
  (begin

    ;; ---- Discovery ----

    (define (manifest (root String)) (→ String)
      (string-append root "/snail-scheme-workspace.datum"))

    (define (declared? (fs Fs) (root String)) (→ Bool)
      (match (file-status fs (manifest root))
        ((Err (NotFound)) #f)
        (_ #t)))

    ;; Prefer the nearest declaration. Remember the first src/ on the way
    ;; up for a standalone checkout written before workspaces had a file.
    (define (workspace-above (fs Fs) (directory String)) (→ (Option String))
      (let loop ((root directory) (standalone (None)))
        (if (declared? fs root)
            (Some root)
            (let ((nearest (match standalone
                             ((Some _) standalone)
                             ((None) (if (file-exists? fs (string-append root "/src"))
                                         (Some root) (None))))))
              (if (string=? root "") nearest (loop (directory-of root) nearest))))))

    (define (directory-of (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 index))
              (else (loop (- index 1))))))

    (define (split-path (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    ;; ---- The base chain ----

    (define (file-loc (path String)) (→ Loc)
      (new Loc (file path) (line 0) (column 0)))

    (define (workspace-directories (fs Fs) (root String) (standard String)) (→ (List String))
      (if (declared? fs root)
          (let ((physical (physical-directory fs "" root (Nil) (file-loc (manifest root)))))
            (source-directories fs (base-chain fs physical (Nil))))
          (let ((own (string-append root "/src")))
            (if (string=? root standard) (list own) (list own (string-append standard "/src"))))))

    (define (base-chain (fs Fs) (root String) (parents (List String))) (→ (List String))
      (let ((chain (Cons root parents)) (path (manifest root)))
        (when (member? root parents)
          (compile-error (file-loc path)
                         (string-append "workspace base cycle: "
                                        (string-join (reverse chain) " → "))))
        (match (read-base fs root path)
          ((Some base) (base-chain fs base chain))
          ((None) (reverse chain)))))

    (define (read-base (fs Fs) (root String) (path String)) (→ (Option String))
      (match (read-text-file fs path 1048576)
        ((Err (ReadFailed (NotFound)))
         (match (source-directory fs root)
           ((Some _) (None))
           ((None) (compile-error (file-loc path) "base workspace needs a manifest or src/"))))
        ((Err error) (compile-error (file-loc path) (show error)))
        ((Ok text)
         (match (read-text text path)
           ((Cons (Form (Cons (Ident "workspace" _ _) clauses) loc) (Nil))
            (workspace-base fs root clauses loc))
           (_ (compile-error (file-loc path) "expected one (workspace ...) declaration"))))))

    (define (workspace-base (fs Fs) (root String) (clauses (List Syntax)) (loc Loc))
      (→ (Option String))
      (match clauses
        ((Nil) (None))
        ((Cons (Form (Cons (Ident "extends" _ _) (Cons (Atom (DString path) at) (Nil))) _) (Nil))
         (when (or (string=? path "") (member? #\null (string->list path)))
           (compile-error at "extends needs a nonempty local path without NUL"))
         (Some (physical-directory fs root path (Nil) at)))
        (_ (compile-error loc "expected (workspace) or (workspace (extends \"path\"))"))))

    ;; Resolve links before .. so aliases of the same checkout have one
    ;; identity. `links` holds only the targets currently being followed.
    ;; The empty prefix denotes /, as it does in directory-of.
    (define (physical-directory (fs Fs)
                                (parent String)
                                (path String)
                                (links (List String))
                                (loc Loc))
      (→ String)
      (fold-left (lambda (directory name)
                   (cond ((or (string=? name "") (string=? name ".")) directory)
                         ((string=? name "..") (directory-of directory))
                         (else (physical-child fs directory name links loc))))
                 (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/)) "" parent)
                 (split-path path)))

    (define (physical-child (fs Fs)
                            (directory String)
                            (name String)
                            (links (List String))
                            (loc Loc))
      (→ String)
      (let ((path (string-append directory "/" name)))
        (match (file-status fs path)
          ((Err error) (compile-error loc (string-append path ": " (show error))))
          ((Ok status)
           (match (● status kind)
             ((Directory) path)
             ((SymbolicLink)
              (when (member? path links)
                (compile-error loc (string-append "symbolic link cycle at " path)))
              (match (read-symbolic-link fs path)
                ((Ok target) (physical-directory fs directory target (Cons path links) loc))
                ((Err error) (compile-error loc (string-append path ": " (show error))))))
             (_ (compile-error loc (string-append "expected a workspace directory at " path))))))))

    ;; ---- The shared src/ tree ----

    (define (source-directory (fs Fs) (root String)) (→ (Option String))
      (let ((src (string-append root "/src")))
        (match (followed-status fs src)
          ((Err (NotFound)) (None))
          ((Err error) (compile-error (file-loc src) (show error)))
          ((Ok status) (match (● status kind)
                         ((Directory) (Some src))
                         (_ (compile-error (file-loc src) "expected a source directory")))))))

    (define (source-directories (fs Fs) (roots (List String))) (→ (List String))
      (reverse (fold-left (lambda (seen root)
                            (match (source-directory fs root)
                              ((None) seen)
                              ((Some src)
                               (for-each (lambda (other) (check-shared-directory fs other src))
                                         seen)
                               (Cons src seen))))
                          (Nil) roots)))

    ;; Descend only where both roots contribute. A link occupies one
    ;; entry, so following a link can never hide another workspace's files.
    (define (check-shared-directory (fs Fs) (left String) (right String)) (→ Unit)
      (match (list-directory fs left)
        ((Err error) (compile-error (file-loc left) (show error)))
        ((Ok names)
         (for-each (lambda (name) (check-entry fs (string-append left "/" name)
                                               (string-append right "/" name))) names))))

    (define (check-entry (fs Fs) (left String) (right String)) (→ Unit)
      (match (file-status fs right)
        ((Err (NotFound)) (unit))
        ((Err error) (compile-error (file-loc right) (show error)))
        ((Ok b)
         (match (file-status fs left)
           ((Err error) (compile-error (file-loc left) (show error)))
           ((Ok a)
            (match (new Pair (first (● a kind)) (second (● b kind)))
              ((Pair (Directory) (Directory)) (check-shared-directory fs left right))
              (_ (compile-error (file-loc left)
                                (string-append "workspace source conflict: "
                                               left
                                               " and "
                                               right)))))))))

    ))
