;; One parsed project and a serial target traversal. Actual compiler
;; requests discover dependencies, even inside generated-library producers.
;; Completed targets name immutable generation files; public links are only
;; for external consumers. Launch descriptions are not executed by a build.
(define-library (lofi project-build)
  (export build-project)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (only (scheme process-context) get-environment-variable)
   (chibi filesystem)
   (chibi pathname)
   (only (chibi process) process->output+error+status)
   (only (chibi string) string-prefix? string-split)
   (only (srfi 95) sort)
   (only (lofi base) match Some None Pair Pair-first string-join)
   (lofi project)
   (lofi build))
  (begin

    ;; ---- Build requests ----

    (define (build-project root project name release?)
      (let* ((filename (path-join project "project.datum"))
             (targets (Project-builds (parse-project (read-file filename) filename)))
             (active '()) (completed '()))
        (define (build-once target)
          (let ((name (target-name target)))
            (when (member name active)
              (error (string-append "artifact dependency cycle: " (string-join (reverse (cons name active)) " -> "))))
            (cond ((assoc name completed) => cdr)
                  (else
                   (let ((previous active))
                     (dynamic-wind (lambda () (set! active (cons name previous)))
                         (lambda ()
                           (let ((files (build-target root project target release?)))
                             (set! completed (cons (cons name files) completed))
                             files))
                         (lambda () (set! active previous))))))))
        (define (resolve name)
          (let ((target (required-target targets name filename)))
            (match target
              ((BrowserTarget _) (build-once target))
              (_ (error "artifact target must be a browser build" name)))))
        (with-artifact-resolver resolve (lambda () (build-once (required-target targets name filename))))
        (path-join project "build" name)))

    (define (required-target targets name filename)
      (match (find-target targets name)
        ((Some target) target)
        ((None) (error "unknown project build target" name filename))))

    (define (build-target root project target release?)
      (let* ((name (target-name target)) (output (prepare-output! project name))
             (generation (create-staging-directory (path-directory output))))
        (guard (failure (#t (guard (ignored (#t #f)) (delete-file-hierarchy generation)) (raise failure)))
          (call-with-output-file (path-join generation ".lofi-target") (lambda (port) (write-string name port)))
          (package-target! root project target generation release?)
          (unless (chmod generation #o755) (error "cannot make project output readable" generation))
          ;; Every fallible preparation precedes publication. The cleanup
          ;; guard must never delete a successfully published generation.
          (let ((files (generation-files generation)))
            (check-output! output name)
            (publish-target! generation output)
            files))))

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

    ;; ---- Completed files ----

    ;; Packaging has stopped. Each tree entry is visited once, giving unique
    ;; relative names; sorting establishes the compiler resolver's order.
    ;; Backing paths stay in this generation, never through build/TARGET.
    (define (generation-files generation)
      (sort (collect-files generation "") (lambda (a b) (string<? (Pair-first a) (Pair-first b)))))

    (define (collect-files generation relative)
      (let ((names (directory-names (path-join generation relative))))
        (apply append
               (map (lambda (name)
                      (if (and (string=? relative "") (string=? name ".lofi-target"))
                          '()
                          (collect-entry generation (if (string=? relative "") name (string-append relative "/" name)))))
                    names))))

    (define (collect-entry generation relative)
      (let ((path (path-join generation relative)))
        (cond ((file-link? path) (error "completed output cannot contain a symbolic link" path))
              ((file-directory? path) (collect-files generation relative))
              ((file-regular? path) (list (Pair relative path)))
              (else (error "completed output must contain regular files and directories" path)))))

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
      (for-each (lambda (name) (copy-public-entry! (path-join source name) (path-join output name)))
                (directory-names source)))

    (define (copy-public-entry! source destination)
      (when (or (file-link-status destination) (string=? (path-strip-directory destination) ".lofi-publish"))
        (error "public file conflicts with a build artifact" source))
      (cond ((file-link? source) (error "public files cannot be symbolic links" source))
            ((file-directory? source)
             (unless (create-directory destination) (error "cannot create public output directory" destination))
             (copy-public! source destination))
            ((file-regular? source) (copy-file! source destination))
            (else (error "public entry must be a regular file or directory" source))))

    ;; Chibi silently accepts a partial listing after readdir fails. The
    ;; required Node host has a checked reader. No shell interprets this
    ;; command or its path; NUL separates names and cannot occur in one.
    ;; This cold builder pays one Node startup per directory, keeping all
    ;; traversal and packaging policy here instead of adding a second walker.
    (define (directory-names directory)
      (let ((result (process->output+error+status
                     (list (or (get-environment-variable "NODE") "node") "--input-type=module" "--eval"
                           "import {readdirSync} from 'node:fs'; process.stdout.write(readdirSync(process.argv[1]).join('\\0'));" directory))))
        (unless (zero? (caddr result)) (error "cannot read directory" directory (cadr result)))
        (if (string=? (car result) "") '() (string-split (car result) (integer->char 0)))))

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
          (error "cannot publish project output" output))))

    ))
