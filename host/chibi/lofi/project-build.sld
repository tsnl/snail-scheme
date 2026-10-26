;; One parsed project target to one published output directory. Compiler
;; recipes and linking stay in (lofi build); this host module owns files and
;; publication. Launch descriptions are not executed by a build.
(define-library (lofi project-build)
  (export build-project)
  (import
   (scheme base)
   (scheme file)
   (chibi filesystem)
   (chibi pathname)
   (only (chibi string) string-prefix? string-split)
   (only (lofi base) match Some None)
   (lofi project)
   (lofi build))
  (begin

    ;; ---- Build requests ----

    (define (build-project root project name release?)
      (let* ((filename (path-join project "project.datum"))
             (description (parse-project (read-file filename) filename)))
        (match (find-target (Project-builds description) name)
          ((Some target) (build-target root project target release?))
          ((None) (error "unknown project build target" name filename)))))

    (define (build-target root project target release?)
      (let* ((name (target-name target)) (output (prepare-output! project name))
             (generation (create-staging-directory (path-directory output))))
        (guard (failure (#t (delete-file-hierarchy generation) (raise failure)))
          (call-with-output-file (path-join generation ".lofi-target") (lambda (port) (write-string name port)))
          (package-target! root project target generation release?)
          (unless (chmod generation #o755) (error "cannot make project output readable" generation))
          (check-output! output name)
          (publish-target! generation output)
          output)))

    (define (package-target! root project target generation release?)
      (match target
        ((ProgramTarget program)
         (compile-target! root project (ProgramBuild-entry program) (ProgramBuild-libraries program) generation release?))
        ((BrowserTarget browser)
         (compile-target! root project (BrowserBuild-entry browser) (BrowserBuild-libraries browser) generation release?)
         (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join generation file))) app-host-files)
         (match (BrowserBuild-public browser)
           ((Some path) (copy-public! (public-directory project (ProjectPath-text path)) generation))
           ((None) #f)))))

    (define (compile-target! root project entry libraries generation release?)
      (build-program-directory root
                               (append (map (lambda (path) (path-join project (ProjectPath-text path))) libraries) (list (path-join root "lib")))
                               (path-join project (ProjectPath-text entry)) generation release?))

    ;; ---- Public files ----

    (define app-host-files
      '("host.mjs" "runtime.mjs" "tasks.mjs" "entry.mjs" "renderer.mjs" "hud.mjs" "pictures.mjs" "storage.mjs" "load.mjs" "style.css"))

    ;; Output cannot be an input of the recursive copy. Reject symlinks in
    ;; the public path as well as its tree, so aliases cannot reintroduce it.
    (define (public-directory project path)
      (let ((parts (string-split path #\/)))
        (when (or (string=? path ".") (string=? (car parts) "build"))
          (error "public directory overlaps project build output" path))
        (let loop ((directory project) (parts parts))
          (if (null? parts)
              directory
              (let ((next (path-join directory (car parts))))
                (unless (and (not (file-link? next)) (file-directory? next)) (error "public path must contain only directories, not links" next))
                (loop next (cdr parts)))))))

    (define (copy-public! source output)
      ;; Chibi returns () on opendir failure. Successful POSIX enumeration
      ;; includes . and .., even in an empty directory.
      (let ((names (directory-files source)))
        (when (null? names) (error "cannot read public directory" source))
        (for-each (lambda (name)
                    (unless (member name '("." ".."))
                      (copy-public-entry! (path-join source name) (path-join output name))))
                  names)))

    (define (copy-public-entry! source destination)
      (when (or (file-link-status destination) (string=? (path-strip-directory destination) ".lofi-publish"))
        (error "public file conflicts with a build artifact" source))
      (cond ((file-link? source) (error "public files cannot be symbolic links" source))
            ((file-directory? source)
             (unless (create-directory destination) (error "cannot create public output directory" destination))
             (copy-public! source destination))
            ((file-regular? source) (copy-file! source destination))
            (else (error "public entry must be a regular file or directory" source))))

    ;; ---- Publication ----

    ;; An existing output must be our link to a marked generation. An
    ;; ordinary directory, file or unrelated link is never replaced.
    (define (prepare-output! project name)
      (let* ((directory (path-join project "build")) (output (path-join directory name)))
        (when (file-link? directory) (error "project build directory cannot be a symbolic link" directory))
        (unless (create-directory* directory) (error "cannot create project build directory" directory))
        (check-output! output name)
        output))

    (define (check-output! output name)
      (when (and (file-link-status output) (not (managed-output? output name)))
        (error "refusing to replace an unmanaged project output" output)))

    (define (managed-output? output name)
      (and (file-link? output)
           (let* ((link (read-link output)) (marker (path-join output ".lofi-target")))
             (and (string-prefix? ".lofi-" link) (string=? link (path-strip-directory link))
                  (file-regular? marker) (not (file-link? marker)) (string=? (read-file marker) name)))))

    ;; The link is created inside our generation, then moved to its public
    ;; location. Its relative destination is interpreted there. Prior
    ;; generations stay intact: readers needing one coherent tree resolve
    ;; the output link once and keep that directory for their whole read.
    ;; This is atomic visibility, not power-loss durability.
    (define (publish-target! generation output)
      (let ((link (path-join generation ".lofi-publish")))
        (unless (symbolic-link-file (path-strip-directory generation) link) (error "cannot create project output link" link))
        (unless (rename-file link output)
          (delete-file link)
          (error "cannot publish project output" output))))

    ))
