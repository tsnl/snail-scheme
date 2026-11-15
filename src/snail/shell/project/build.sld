;; A project's build: each target compiled, linked and packaged into a
;; generation of its own, then published by replacing the target's link at
;; once. The project planner (snail shell project plan) hands out waves
;; of phases that can run now, dependencies first: a
;; phase builds a target into its generation, or runs a producer, whose
;; output refines the plan. A phase that embeds a target's files is first
;; given those of each target it embeds, built in an earlier phase.
;;
;; Every build, debug or release, compiles each target library afresh and
;; assembles it in-process (snail shell assembler) into a module of its
;; own, an object of the project's store. The compiler carries no checked
;; code or emitted modules between builds.
;;
;; The compiler, assembler and linker run in this program. Node runs
;; producers through `run` (snail shell process). A build that fails removes
;; every generation it made, and only those, so the outputs of earlier
;; builds stay published.
(define-library (snail shell project build)
  (export
   Tools
   Mode
   Debug
   Release
   Failure
   CompileFailure
   BuildFailure
   failure->string
   Output
   Candidate
   manifest-name
   read-project
   build-project
   publish-project
   discard-candidate)
  (import
   (snail shell project web-app)
   (snail core base)
   (snail core io)
   (snail shell project)
   (snail shell compiler)
   (only (snail shell compiler read)
         Loc
         compile
         compiling
         Failed
         Requested
         Diagnostics
         diagnostics->string)
   (snail shell compiler inputs)
   (only (snail shell compiler check) Typed)
   (snail shell project plan)
   (snail shell process)
   (snail shell assembler)
   (snail shell json)
   (snail shell compiler sha256)
   (snail shell utf8))
  (begin

    ;; ---- Tools and modes ----

    ;; What a build runs besides the compiler: `root` holds the standard
    ;; libraries (src/), the browser host's files and the native runner,
    ;; `runtime` is the runtime module a program is linked with, `toolchain`
    ;; the one a program that links the assembler is, whose services
    ;; include it, and `node` runs producers.
    (record Tools
      ((root String)
       (runtime String)
       (toolchain String)
       (node String)))

    ;; Both modes leave a module per library, each an object of the
    ;; project's store, with NAME.manifest.datum naming them in link order,
    ;; the runtime and the files the program links, which every host links
    ;; as the program starts. Neither runs a function-body optimizer. A
    ;; debug generation links to the objects in the store; a release one
    ;; holds copies, so it can be served or shipped on its own.
    (enum Mode
      (Debug)
      (Release))

    ;; ---- Failures ----

    ;; Why a build stopped: a compile's diagnostics, each naming its source
    ;; point, or a failure of the build's own work, which names a file or a
    ;; command.
    (enum Failure
      (CompileFailure ((diagnostics Diagnostics)))
      (BuildFailure ((message String))))

    (define (failure->string (failure Failure)) (→ String)
      (match failure
        ((CompileFailure diagnostics) (diagnostics->string diagnostics))
        ((BuildFailure message) message)))

    ;; A build stops at the first failure it meets, and nothing after the
    ;; failure runs, so a yield to this effect saves no frames. `attempt`
    ;; turns the work into a Result.
    (effect building
      ((ctl stop (Fn Failure → Never))))

    (define (fail-build (message String)) (→ A) (! building) (∀ (A))
      (absurd (stop (BuildFailure message))))

    (define (attempt (work (Fn → T ! building e))) (→ (Result T Failure)) (! e) (∀ (T e))
      (handle building
          ((stop (lambda (failure) (Err failure))))
        (Ok (work))))

    ;; A compile that fails stops the build with its diagnostic. The plan
    ;; supplies every input a phase needs before it runs, so a compile that
    ;; asks for one names a need the planner missed.

    (define (compiled (work (Fn → T ! compile e)))
      (→ T)
      (! building e)
      (∀ (T e))
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (absurd (stop (CompileFailure diagnostics))))
        ((Err (Requested request))
         (fail-build (string-append "internal error: the build plan did not supply the input "
                                    (request->string request))))))

    ;; ---- Projects ----

    ;; The project described by `directory`'s project.datum.

    (define (read-project (directory String)) (→ (Result Project Failure)) (! fs)
      (let ((file (project-file directory)))
        (attempt (lambda ()
                   (unless (file-exists? file)
                     (fail-build (string-append "there is no project file at " file)))
                   (compiled (lambda () (parse-project (read-file file) file)))))))

    (define (project-file (directory String)) (→ String)
      (string-append directory "/project.datum"))

    ;; One build's fixed context: what it runs, the project and its
    ;; description, the mode, the scratch directory its compiles and
    ;; producers work in, which no other build shares, and the prefix its
    ;; generations' names begin with.
    (record Builder
      ((tools Tools)
       (project String)
       (description Project)
       (mode Mode)
       (scratch String)
       (prefix String)))

    ;; A project's build targets as the planner takes them, in declaration
    ;; order: each entry and library root found in the project's directory,
    ;; and the standard libraries' directory after the roots.

    (define (plan-targets (builder Builder)) (→ (List Target)) (! fs building)
      (map (lambda (target)
             (match target
               ((ProgramTarget program)
                (new Target (name (● program name))
                     (browser? #f)
                     (entry (entry-source builder #f (● program entry)))
                     (directories (library-directories builder (● program libraries)))
                     (loc (● program loc))))
               ((BrowserTarget browser)
                (new Target (name (● browser name))
                     (browser? #t)
                     (entry (entry-source builder #t (● browser entry)))
                     (directories (library-directories builder (● browser libraries)))
                     (loc (● browser loc))))))
           (● (● builder description) builds)))

    ;; Entry selection emits ordinary source, so normal import resolution,
    ;; type checking and instance selection establish its contract. A digest
    ;; names immutable scaffolding: development sessions keep the same source
    ;; identity, and concurrent builds never replace one another's entry.

    (define (entry-source (builder Builder) (browser? Bool) (entry ProjectEntry))
      (→ String)
      (! fs building)
      (match entry
        ((SourceEntry path) (in-project builder path))
        ((ApplicationEntry library name)
         (let* ((text (application-source browser? library name))
                (directory (string-append (● builder project) "/build/.snail-entry"))
                (file
                 (string-append directory "/" (bytes->hex (sha256 (string->utf8 text))) ".sld")))
           (expect-done (make-directories directory) (string-append "cannot make " directory))
           (unless (file-exists? file)
             (let ((writing (string-append file ".writing."
                                           (bytes->hex
                                            (sha256 (string->utf8 (● builder scratch)))))))
               (write-file writing text)
               (expect-done (rename-file writing file) (string-append "cannot place " file))))
           file))))

    (define (application-source (browser? Bool) (library (List String)) (name String)) (→ String)
      ;; The lambda's row follows the selected Application instance, just as
      ;; define-page-entry's does. Importing the entry performs no work.
      (string-append "(import (snail core base) (snail shell application) "
                     (if browser? "(snail shell page) " "")
                     "(prefix (" (string-join library " ") ") selected:))\n"
                     (if browser?
                         "(define-page-entry selected:"
                         "(define main (lambda () (start (ann (new Entry) (Entry selected:")
                     name (if browser? ")\n" ")))))\n")))

    (define (in-project (builder Builder) (path ProjectPath)) (→ String)
      (if (string=? (● path text) ".")
          (● builder project)
          (string-append (● builder project) "/" (● path text))))

    ;; The project's library roots, then the standard libraries' directory,
    ;; unless a root is it, as the repository's own src/ is.

    (define (library-directories (builder Builder) (roots (List ProjectPath))) (→ (List String))
      (let ((directories (map (lambda (root) (in-project builder root)) roots))
            (standard (string-append (● (● builder tools) root) "/src")))
        (if (member? standard directories) directories (append directories (list standard)))))

    (define (root-target (targets (List Target)) (file String) (name String))
      (→ Target)
      (! building)
      (match (find (lambda (target) (string=? (● target name) name)) targets)
        ((Some target) target)
        ((None) (fail-build (string-append "unknown project build target " name " in " file)))))

    ;; ---- A build ----

    ;; A target's generation: the target's name, the directory that holds
    ;; what was built for it, and its digest, which a change to any file in
    ;; it changes and nothing else does. `files` are the digests of its files
    ;; but its objects, whose names are already digests, by relative name.
    ;; `linked` holds the paths of the files its program links. A build
    ;; keeps its program as checked, whose names the language server
    ;; answers for; it lives only as long as the candidate.
    (record Output
      ((name String)
       (directory String)
       (digest String)
       (files (List (Pair String String)))
       (linked (List String))
       (typed (Option Typed))))

    ;; What a build made and has not published: each target's generation,
    ;; in plan order, which puts the first root first.
    (record Candidate
      ((project String)
       (outputs (List Output))))

    ;; A built target: its node in the plan, its generation, and the files
    ;; in it, each relative name with its path, in name order.
    (record Generation
      ((node I64)
       (output Output)
       (files (List (Pair String String)))))

    ;; What a build has made so far: the inputs the next phase compiles
    ;; with, the targets built, the names of those whose files the inputs
    ;; already hold, and the failure that stopped this attempt, if one did.
    ;; No phase runs after a failure.
    (record Progress
      ((inputs Inputs)
       (generations (List Generation))
       (supplied (List String))
       (failure (Option Failure))))

    ;; Build a complete candidate in private scratch. Failure preserves all
    ;; published generations; no compiler state survives this invocation.
    (define (build-project (tools Tools) (directory String) (project Project)
                           (names (List String)) (mode Mode) (scratch String) (prefix String))
      (→ (Result Candidate Failure)) (! mut fs clock process)
      (match (attempt (lambda () (fresh-scratch scratch)))
        ((Err failure) (Err failure))
        ((Ok working)
         (let ((built (build-roots (new Builder
                                     (tools tools)
                                     (project directory)
                                     (description project)
                                     (mode mode)
                                     (scratch working)
                                     (prefix prefix))
                                   names)))
           (remove-tree working)
           built))))

    (define (fresh-scratch (scratch String)) (→ String) (! fs clock building)
      (expect-done (make-directories scratch) (string-append "cannot make " scratch))
      (fresh-directory (string-append scratch "/build-") "" (monotonic-nanoseconds)))

    (define (build-roots (builder Builder) (names (List String)))
      (→ (Result Candidate Failure)) (! mut fs clock process)
      (match (attempt (lambda () (plan-roots builder names)))
        ((Err failure) (Err failure))
        ((Ok plan)
         (outcome builder
                  (run-waves builder
                             plan
                             (new Progress
                               (inputs (no-inputs))
                               (generations (Nil))
                               (supplied (Nil))
                               (failure (None))))))))

    (define (plan-roots (builder Builder) (names (List String))) (→ Plan) (! fs building)
      (let* ((targets (plan-targets builder))
             (file (project-file (● builder project)))
             (roots (map (lambda (name) (root-target targets file name)) names))
             (printed (in-scratch builder "plan")))
        (expect-done (make-directories printed) (string-append "cannot make " printed))
        (compiled (lambda () (plan-build targets roots (no-inputs) printed)))))

    ;; A build that failed discards every generation it made.

    (define (outcome (builder Builder) (progress Progress)) (→ (Result Candidate Failure)) (! fs)
      (match (● progress failure)
        ((Some failure)
         (discard (map (lambda (record) (● record output)) (● progress generations)))
         (Err failure))
        ((None)
         (Ok (new Candidate (project (● builder project))
                  (outputs (map (lambda (record) (● record output))
                                (by-node (● progress generations)))))))))

    ;; Runs each wave's phases in order. A wave that leaves phases waiting
    ;; has run the producers whose outputs they need, and the plan refined
    ;; with them hands out the next.

    (define (run-waves (builder Builder) (plan Plan) (progress Progress))
      (→ Progress)
      (! mut fs clock process)
      (let* ((wave (next-phases plan))
             (plan (● wave second))
             (progress (fold-left (lambda (progress entry) (run-phase builder plan entry progress))
                                  progress
                                  (● wave first))))
        (if (and (phases-left? plan) (not (failed? progress)))
            (match (attempt (lambda ()
                              (compiled (lambda () (refine-plan plan (● progress inputs))))))
              ((Ok refined) (run-waves builder refined progress))
              ((Err failure) (Progress-failure-set progress (Some failure))))
            progress)))

    (define (failed? (progress Progress)) (→ Bool)
      (match (● progress failure)
        ((Some _) #t)
        ((None) #f)))

    ;; A phase after a failure does not run; a phase that fails records it.

    (define (run-phase (builder Builder) (plan Plan) (entry (Pair I64 Phase)) (progress Progress))
      (→ Progress)
      (! mut fs clock process)
      (if (failed? progress)
          progress
          (match (attempt (lambda () (phase-work builder plan entry progress)))
            ((Ok advanced) advanced)
            ((Err failure) (Progress-failure-set progress (Some failure))))))

    (define (phase-work (builder Builder) (plan Plan) (entry (Pair I64 Phase)) (progress Progress))
      (→ Progress)
      (! mut fs clock process building)
      (let ((progress (supply-embedded builder (embedded-names plan (● entry first)) progress)))
        (match (● entry second)
          ((ProducePhase producer)
           (Progress-inputs-set progress
                                (produce builder
                                         (● entry first)
                                         producer
                                         (● progress inputs))))
          ((BuildPhase target) (build-target builder (● entry first) target progress)))))

    ;; The targets whose files the phase at `node` embeds: the builds among
    ;; its needs, each built in an earlier wave, or earlier in this one.

    (define (embedded-names (plan Plan) (node I64)) (→ (List String))
      (let ((steps (● plan steps)))
        (match (● (array-ref steps node) needs)
          ((Known nodes)
           (concatenate (map (lambda (need)
                               (match (● (array-ref steps need) phase)
                                 ((BuildPhase target) (list (● target name)))
                                 (_ (Nil))))
                             nodes)))
          ((Waiting _ _) (panic "internal error: a wave handed out a waiting phase")))))

    ;; Each embedded target's files join the inputs once, read as they are
    ;; in its generation.

    (define (supply-embedded (builder Builder) (names (List String)) (progress Progress))
      (→ Progress)
      (! fs)
      (fold-left (lambda (progress name)
                   (if (member? name (● progress supplied))
                       progress
                       (Progress-supplied-set
                        (Progress-inputs-set progress
                                             (supply-artifact (● progress inputs)
                                                              name
                                                              (snapshot (generation-named progress
                                                                                          name))))
                        (Cons name (● progress supplied)))))
                 progress
                 names))

    (define (generation-named (progress Progress) (name String)) (→ Generation)
      (match (find
              (lambda (generation) (string=? (● (● generation output) name) name))
              (● progress generations))
        ((Some generation) generation)
        ((None) (panic (string-append "internal error: the build plan embeds " name
                                      " before building it")))))

    ;; An embedding build gets a generation's files, the objects of its
    ;; store/ view among them, read as they are, so an embedded page is
    ;; complete wherever it is served from.

    (define (snapshot (generation Generation)) (→ ArtifactFiles) (! fs)
      (map (lambda (file) (new Pair (first (● file first)) (second (read-bytes (● file second)))))
           (● generation files)))

    (define (by-node (generations (List Generation))) (→ (List Generation))
      (list-sort (lambda (a b) (< (● a node) (● b node))) generations))

    ;; ---- Targets ----

    ;; Builds a target into a new generation, which goes if the build of it
    ;; fails. A packaging failure also removes the candidate directory.

    (define (build-target (builder Builder) (node I64) (target Target) (progress Progress))
      (→ Progress)
      (! mut fs clock building)
      (let* ((name (● target name))
             (directory (prepare-generation builder name))
             (program (removing directory
                                (lambda ()
                                  (build-program builder node target directory progress)))))
        (match (attempt (lambda () (package builder target directory)))
          ((Ok files)
           (Progress-generations-set progress
                                     (Cons (new Generation (node node)
                                                (output
                                                 (program-output program name directory files))
                                                (files files))
                                           (● progress generations))))
          ((Err failure)
           (remove-tree directory)
           (Progress-failure-set progress (Some failure))))))

    ;; `work`'s value; when it fails, `directory` goes before the failure
    ;; does.

    (define (removing (directory String) (work (Fn → T ! building e)))
      (→ T)
      (! fs building e)
      (∀ (T e))
      (match (attempt work)
        ((Ok value) value)
        ((Err failure)
         (remove-tree directory)
         (absurd (stop failure)))))

    ;; What building a target's program left: the files it links, by their
    ;; sources' paths, and the program as it was checked.
    (record Program
      ((linked (List String))
       (typed (Option Typed))))

    (define (program-output (program Program)
                            (name String)
                            (directory String)
                            (files (List (Pair String String))))
      (→ Output)
      (! fs)
      (let ((digests (file-digests files)))
        (new Output (name name)
             (directory directory)
             (digest (generation-digest files digests))
             (files digests)
             (linked (● program linked))
             (typed (● program typed)))))

    ;; The target's program in its generation: every library compiled and
    ;; assembled anew, each module an object of the project's store, with
    ;; the files it links. Content digests name objects; they do not decide
    ;; whether compilation runs.

    (define (build-program (builder Builder)
                           (node I64)
                           (target Target)
                           (directory String)
                           (progress Progress))
      (→ Program)
      (! mut fs building)
      (in-working builder node (lambda (working)
                                 (let ((checked (check-target target working progress)))
                                   (write-program builder target directory checked)))))

    (define (check-target (target Target) (working String) (progress Progress)) (→ Checked)
      (! fs building)
      (let ((directories (● target directories)))
        (compiled (lambda ()
                    (source->checked directories
                                     (● target entry)
                                     (lambda (loading forms)
                                       (generated-syntax working directories loading forms))
                                     (● progress inputs))))))

    (define (write-program (builder Builder) (target Target) (directory String) (checked Checked))
      (→ Program)
      (! mut fs building)
      (let* ((built (compiled (lambda () (checked->modules checked))))
             (modules (map assemble-module built))
             (links (concatenate (map (lambda (module) (● module links)) built))))
        (write-manifest builder target directory modules links)
        (new Program
          (linked (map (lambda (file) (● file path)) links))
          (typed (Some (● checked typed))))))

    ;; A browser target's host files and public tree; then the files the
    ;; generation holds.

    (define (package (builder Builder) (target Target) (directory String))
      (→ (List (Pair String String)))
      (! fs building)
      (when (● target browser?)
        (package-browser builder (● target name) directory))
      (generation-files directory))

    ;; `work` in a directory of its own in the build's scratch, removed after.

    (define (in-working (builder Builder) (node I64) (work (Fn String → T ! fs e)))
      (→ T)
      (! fs e)
      (∀ (T e))
      (let ((working (in-scratch builder (string-append "phase-" (show node)))))
        (make-directories working)
        (let ((result (work working)))
          (remove-tree working)
          result)))

    (define (in-scratch (builder Builder) (name String)) (→ String)
      (string-append (● builder scratch) "/" name))

    ;; ---- Programs ----

    ;; The runtime a program links with: the toolchain's, whose services
    ;; include the assembler, for a program that links (snail shell
    ;; assembler), and the plain one otherwise.

    (define (program-runtime (builder Builder) (modules (List (Pair String Bytes)))) (→ String)
      (let ((tools (● builder tools)))
        (if (any? (lambda (module) (string=? (● module first) "snail.shell.assembler")) modules)
            (● tools toolchain)
            (● tools runtime))))

    ;; The program at `entry`, compiled in this process to one module and
    ;; linked with the runtime into `output`; the files it links ship beside
    ;; it. The compile's own files stay in `working`.

    (define (link-program (builder Builder)
                          (runtime String)
                          (entry String)
                          (directories (List String))
                          (inputs Inputs)
                          (working String)
                          (output String))
      (→ (List LinkedFile))
      (! mut fs building)
      (let ((program (compiled (lambda ()
                                 (source->wat directories
                                              entry
                                              (lambda (loading forms)
                                                (generated-syntax working
                                                                  directories
                                                                  loading
                                                                  forms))
                                              inputs)))))
        (match (link (● program text)
                     (read-bytes runtime))
          ((Ok bytes) (write-bytes output bytes))
          ((Err message) (fail-build (string-append "cannot link program: " message))))
        (● program links)))

    ;; ---- Objects ----

    ;; Every object, a module, the runtime or a file the program links, is
    ;; a file of the project's store, build/.snail-store, at
    ;; sha256/AB/DIGEST, named for the SHA-256 of its bytes and sharded by
    ;; its first two hex digits. It is placed once however many builds
    ;; need it, and never rewritten. A generation holds a view of the
    ;; objects its manifest names at the same paths under its own store/:
    ;; links into the project's store in a debug build, copies in a
    ;; release one. Nothing reclaims the store; deleting build/ does.

    (define (project-store (builder Builder)) (→ String)
      (string-append (● builder project) "/build/.snail-store"))

    (define (object-path (store String) (digest String)) (→ String)
      (string-append store "/sha256/" (substring digest 0 2) "/" digest))

    ;; An object already in the store is left as it is: its bytes are what
    ;; its name says. A new one is written beside its place, under a name
    ;; this build alone writes, and renamed into it, so a reader never sees
    ;; a partial object, and two builds placing one object at once each
    ;; rename the same bytes. Answers the object as a manifest names it.

    (define (place-object (store String) (token String) (bytes Bytes)) (→ Object) (! fs building)
      (let* ((digest (bytes->hex (sha256 bytes))) (to (object-path store digest)))
        (unless (kind-is? to (RegularFile))
          (expect-done (make-directories (directory-part to)) (string-append "cannot make " to))
          (let ((writing (string-append to ".writing." token)))
            (write-bytes writing bytes)
            (expect-done (rename-file writing to) (string-append "cannot place " to))))
        (new Object (digest digest) (size (array-length bytes)))))

    ;; An object as a manifest names it.
    (record Object
      ((digest String)
       (size I64)))

    ;; A file is named for the digest of the bytes its compile read, so the
    ;; bytes placed must be those: a file edited since fails the build, and
    ;; the next one compiles against its new bytes.

    (define (place-link (store String) (token String) (link LinkedFile)) (→ Object) (! fs building)
      (let ((from (● link path)))
        (unless (kind-is? from (RegularFile))
          (fail-build
           (string-append "cannot place the linked file " from ": there is no file there")))
        (let ((object (place-object store token (read-bytes from))))
          (unless (string=? (● object digest) (● link digest))
            (fail-build (string-append "the linked file " from " changed during the build")))
          object)))

    ;; The generation's view of an object: a link up to the project's
    ;; store, or a copy. The generation of the target `name` lies beside
    ;; build/NAME, so the link climbs out of store/sha256/AB/ and the
    ;; generation, then one directory for each of NAME's slashes.

    (define (view-object (builder Builder) (name String) (directory String) (object Object))
      (→ Unit)
      (! fs building)
      (let* ((digest (● object digest))
             (at (object-path (string-append directory "/store") digest))
             (from (object-path (project-store builder) digest)))
        (expect-done (make-directories (directory-part at)) (string-append "cannot make " at))
        (match (● builder mode)
          ((Debug)
           (expect-done (make-symbolic-link (object-path (store-from-generation name) digest) at)
                        (string-append "cannot link " at)))
          ((Release) (copy-into from at (string-append "cannot copy " from))))))

    (define (store-from-generation (name String)) (→ String)
      (string-append (string-concatenate (map (lambda (part) "../")
                                              (Cons "" (Cons "" (Cons "" (split-path name))))))
                     ".snail-store"))

    ;; ---- Manifests ----

    (define (assemble-module (module Built)) (→ (Pair String Bytes)) (! building)
      (match (assemble (● module text))
        ((Ok bytes) (new Pair (first (● module name)) (second bytes)))
        ((Err message)
         (fail-build (string-append "internal error: cannot assemble the module of "
                                    (● module name)
                                    ": "
                                    message)))))

    ;; The runtime, each module and each file the program links, placed in
    ;; the project's store and viewed from the generation, and the manifest
    ;; naming them, TARGET.manifest.datum.

    (define (write-manifest (builder Builder)
                            (target Target)
                            (directory String)
                            (modules (List (Pair String Bytes)))
                            (links (List LinkedFile)))
      (→ Unit)
      (! fs building)
      (let* ((store (project-store builder))
             (token (base-name directory))
             (runtime (place-object store token (read-bytes (program-runtime builder modules))))
             (placed (map (lambda (module)
                            (new Pair (first (● module first))
                                 (second (place-object store token (● module second)))))
                          modules))
             (files (map (lambda (link) (place-link store token link)) (distinct-links links))))
        (for-each (lambda (object) (view-object builder (● target name) directory object))
                  (Cons runtime (append (map (lambda (module) (● module second)) placed) files)))
        (write-file (string-append directory "/" (manifest-name (● target name)))
                    (manifest-text runtime placed files))))

    (define (distinct-links (links (List LinkedFile))) (→ (List LinkedFile))
      (delete-duplicates (lambda (a b) (string=? (● a digest) (● b digest))) links))

    ;; The manifest of the target `target`, named for the last part of its
    ;; name: a script's is named for the script.

    (define (manifest-name (target String)) (→ String)
      (string-append (base-name target) ".manifest.datum"))

    ;; One entry a line: `(runtime "DIGEST" SIZE)`, then `(module "LIBRARY"
    ;; "DIGEST" SIZE)` for each library in program order, then `(file
    ;; "DIGEST" SIZE)` for each file the program links. Library names and
    ;; digests hold no quote or backslash.

    (define (manifest-text (runtime Object)
                           (modules (List (Pair String Object)))
                           (files (List Object)))
      (→ String)
      (string-append "("
                     (string-join (Cons (entry-text "runtime" (Nil) runtime)
                                        (append (map (lambda (module)
                                                       (entry-text "module"
                                                                   (list (● module first))
                                                                   (● module second)))
                                                     modules)
                                                (map (lambda (file) (entry-text "file" (Nil) file))
                                                     files)))
                                  "\n ")
                     ")\n"))

    (define (entry-text (kind String) (names (List String)) (object Object)) (→ String)
      (string-append "("
                     kind
                     (string-join (map (lambda (text) (string-append " \"" text "\""))
                                       (append names (list (● object digest))))
                                  "")
                     " "
                     (show (● object size))
                     ")"))

    ;; Runs a command to its end, and stops the build with what it wrote to
    ;; stderr unless it exits with status 0.

    (define (run-command (command Command) (name String)) (→ Unit) (! process building)
      (match (run command #u8())
        ((Err error) (fail-build (string-append "cannot run " name ": " (● error code))))
        ((Ok captured)
         (match (● captured exit)
           ((Exited 0) (unit))
           (exit (fail-build (string-append name " failed: " (failure-text captured exit))))))))

    ;; A failed command's stderr, or how it ended when it wrote nothing
    ;; that reads as text.

    (define (failure-text (captured Captured) (exit Exit)) (→ String)
      (match (utf8->string (● captured stderr))
        ((Ok stderr) (if (string=? stderr "") (how-it-ended exit) stderr))
        ((Err _) (how-it-ended exit))))

    (define (how-it-ended (exit Exit)) (→ String)
      (match exit
        ((Exited code) (string-append "exited with " (show code)))
        ((Signaled name) (string-append "ended by " name))))

    ;; ---- Producers ----

    ;; A producer is compiled from the source the planner printed, linked,
    ;; and run to write its library's syntax, which the
    ;; inputs supply from then on.

    (define (produce (builder Builder) (node I64) (producer Producer) (inputs Inputs))
      (→ Inputs)
      (! mut fs process building)
      (in-working builder
                  node
                  (lambda (working)
                    (let ((program (string-append working "/producer.wasm"))
                          (output (string-append working "/output.syntax")))
                      (place-producer-links builder
                                            working
                                            (link-program builder
                                                          (● (● builder tools) runtime)
                                                          (● producer source)
                                                          (● producer directories)
                                                          inputs
                                                          working
                                                          program))
                      (run-producer builder program output)
                      (supply-producer producer inputs output)))))

    ;; A producer is one linked module, whose linked files are objects of
    ;; store/ beside it, copied there from the project's store.

    (define (place-producer-links (builder Builder) (working String) (links (List LinkedFile)))
      (→ Unit)
      (! fs building)
      (for-each (lambda (link)
                  (let ((object (place-link (project-store builder) "producer" link)))
                    (copy-into (object-path (project-store builder) (● object digest))
                               (object-path (string-append working "/store") (● object digest))
                               (string-append "cannot copy " (● link path)))))
                (distinct-links links)))

    (define (run-producer (builder Builder) (program String) (output String))
      (→ Unit)
      (! fs process building)
      (let ((tools (● builder tools)))
        (run-command (new Command (program (● tools node))
                          (arguments (list "--no-warnings"
                                           (string-append (● tools root)
                                                          "/host/native/run-snail.mjs")
                                           program
                                           output))
                          (directory "."))
                     "the producer")
        (unless (file-exists? output)
          (fail-build "the producer did not write its generated library"))))

    ;; The producer is read back from its printed source, so the inputs
    ;; hold the text a compile looks its output up by.

    (define (supply-producer (producer Producer) (inputs Inputs) (output String))
      (→ Inputs)
      (! fs building)
      (let ((text (compiled (lambda ()
                              (printed-producer-text (● producer directories)
                                                     (● producer source))))))
        (unless (string=? (producer-key text) (● producer key))
          (panic "internal error: a producer's printed text does not have its key"))
        (supply-generated inputs text (read-bytes output))))

    ;; ---- Browser packages ----

    (define (browser-files) (→ (List String))
      (list "host.mjs"
            "application.mjs"
            "runtime.mjs"
            "tasks.mjs"
            "entry.mjs"
            "renderer.mjs"
            "hud.mjs"
            "pictures.mjs"
            "storage.mjs" "load.mjs" "style.css" "ui.mjs" "dom.mjs" "fetch.mjs" "install.mjs"
            "snail-icon.svg" "snail-icon-192.png" "snail-icon-512.png"))

    ;; The names a build of `target` writes at its generation's root: its
    ;; manifest, store/, the ownership marker and the browser host's files.
    ;; A public tree may use none of them.

    (define (generated-names (target String)) (→ (List String))
      (append (list (manifest-name target) "store" ".snail-target") (browser-files)))

    ;; The browser host's files, then the target's public tree, if it has
    ;; one. The page is the project's own index.html; none is generated.
    ;; UTF-8 pages receive a web-app manifest link and are told where the
    ;; program's manifest is. A public web-app manifest replaces the default
    ;; whole.

    (define (package-browser (builder Builder) (name String) (directory String))
      (→ Unit)
      (! fs building)
      (copy-browser-assets builder name directory)
      (ensure-web-manifest (string-append (base-name (● builder project)) " / " name)
                           directory)
      (prepare-browser-page directory (manifest-name name)))

    ;; Public assets were copied first. A supplied manifest is a complete
    ;; replacement; the default is a regular file in the same output tree.

    (define (ensure-web-manifest (name String) (directory String)) (→ Unit) (! fs)
      (let ((path (string-append directory "/manifest.webmanifest")))
        (unless (file-exists? path)
          (write-file path (json->string (web-app-manifest name))))))

    (define (prepare-browser-page (directory String) (program String)) (→ Unit) (! fs)
      (let ((path (string-append directory "/index.html")))
        (when (kind-is? path (RegularFile))
          (match (utf8->string (read-bytes path))
            ((Err _) (unit))
            ((Ok text) (write-file path (with-web-app text program)))))))

    (define (copy-browser-assets (builder Builder) (name String) (directory String))
      (→ Unit)
      (! fs building)
      (for-each (lambda (file)
                  (copy-into
                   (string-append (● (● builder tools) root) "/host/browser/" file)
                   (string-append directory "/" file)
                   (string-append "cannot copy the browser host's " file)))
                (browser-files))
      (match (find-target (● (● builder description) builds) name)
        ((Some (BrowserTarget browser))
         (match (● browser public)
           ((Some path)
            (copy-public (public-directory builder path) directory (generated-names name)))
           ((None) (unit))))
        (_ (unit))))

    ;; The public directory, which may not be the project's own or lie in
    ;; its build output, and whose every component is a directory, not a
    ;; link.

    (define (public-directory (builder Builder) (path ProjectPath)) (→ String) (! fs building)
      (let ((text (● path text)))
        (when (or (string=? text ".") (string=? (first-component text) "build"))
          (fail-build (string-append "public directory overlaps project build output: " text)))
        (fold-left (lambda (directory part)
                     (let ((next (string-append directory "/" part)))
                       (unless (kind-is? next (Directory))
                         (fail-build (string-append
                                      "public path must contain only directories, not links: "
                                      next)))
                       next))
                   (● builder project)
                   (split-path text))))

    ;; Copies a public tree into the generation. Nothing in it may replace
    ;; a file the build made, use a name `reserved` holds, which are those
    ;; the build writes at the root and none below, or be anything but a
    ;; regular file or a directory.

    (define (copy-public (source String) (output String) (reserved (List String)))
      (→ Unit)
      (! fs building)
      (for-each (lambda (name)
                  (let ((from (string-append source "/" name)) (to (string-append output "/" name)))
                    (when (or (member? name reserved)
                              (exists? to)
                              (string=? name ".snail-publish"))
                      (fail-build
                       (string-append "public file conflicts with a build artifact: " from)))
                    (match (status-kind from)
                      ((Some (SymbolicLink))
                       (fail-build (string-append "public files cannot be symbolic links: " from)))
                      ((Some (Directory))
                       (make-directory to)
                       (copy-public from to (Nil)))
                      ((Some (RegularFile)) (copy-into from to (string-append "cannot copy " from)))
                      (_ (fail-build (string-append
                                      "public entry must be a regular file or directory: "
                                      from))))))
                (directory-names source)))

    ;; ---- Generations ----

    ;; A new generation for the target `name` beside its output link,
    ;; build/NAME, holding only its ownership marker. A script's target is
    ;; named for its path, so its link and generation may lie below build/.
    ;; The output link, if any, must be one a build published.

    (define (prepare-generation (builder Builder) (name String)) (→ String) (! fs clock building)
      (let* ((build (string-append (● builder project) "/build"))
             (output (string-append build "/" name))
             (beside (directory-part output)))
        (when (kind-is? build (SymbolicLink))
          (fail-build (string-append "project build directory cannot be a symbolic link: " build)))
        (expect-done (make-directories beside) (string-append "cannot make " beside))
        (check-output output name)
        (let ((directory (fresh-directory (string-append beside "/" (● builder prefix))
                                          (string-append "-" (base-name name))
                                          (monotonic-nanoseconds))))
          (write-file (string-append directory "/.snail-target") name)
          directory)))

    ;; A directory `STEM N SUFFIX` that no other build has made, as mkdtemp
    ;; makes one: N starts at `token`, and goes up while the name is taken.

    (define (fresh-directory (stem String) (suffix String) (token I64)) (→ String) (! fs building)
      (let ((directory (string-append stem (show token) suffix)))
        (match (make-directory directory)
          ((Ok _) directory)
          ((Err (AlreadyExists)) (fresh-directory stem suffix (+ token 1)))
          ((Err error) (fail-build (string-append "cannot make " directory ": " (show error)))))))

    ;; An output is replaced only when it is a link to a generation beside
    ;; it whose marker names the target.

    (define (check-output (output String) (name String)) (→ Unit) (! fs building)
      (match (status-kind output)
        ((None) (unit))
        ((Some (SymbolicLink))
         (let ((marker (string-append output "/.snail-target")))
           (unless (and (match (read-symbolic-link output)
                          ((Ok link) (and (starts-with? link ".snail-")
                                          (match (string-index link #\/)
                                            ((Some _) #f)
                                            ((None) #t))))
                          ((Err _) #f))
                        (kind-is? marker (RegularFile))
                        (string=? (read-file marker) name))
             (unmanaged output))))
        ((Some _) (unmanaged output))))

    (define (unmanaged (output String)) (→ A) (! building) (∀ (A))
      (fail-build (string-append "refusing to replace an unmanaged project output: " output)))

    ;; The files of a completed generation, each relative name with its
    ;; path, in name order, without the root's ownership marker.

    (define (generation-files (directory String)) (→ (List (Pair String String))) (! fs building)
      (list-sort (lambda (a b) (string<? (● a first) (● b first)))
                 (files-under directory "")))

    ;; The digest of each file of a generation but its objects, which are
    ;; named for theirs, by name.

    (define (file-digests (files (List (Pair String String))))
      (→ (List (Pair String String)))
      (! fs)
      (map (lambda (file)
             (new Pair
               (first (● file first))
               (second (bytes->hex (sha256 (read-bytes (● file second)))))))
           (filter (lambda (file) (not (content-named? (● file first)))) files)))

    ;; A debug generation's store/ holds links to the project's store.

    (define (unexpected-entry (path String)) (→ A) (! building) (∀ (A))
      (fail-build (string-append "completed output must contain regular files and directories: "
                                 path)))

    (define (content-named? (name String)) (→ Bool)
      (starts-with? name "store/"))

    ;; A digest of a generation's files: each relative name, with its
    ;; file's digest, but only the name of an object, which is the digest
    ;; of its bytes.

    (define (generation-digest (files (List (Pair String String)))
                               (digests (List (Pair String String))))
      (→ String)
      (bytes->hex
       (sha256
        (string->utf8
         (json->string
          (JsonArray (map (lambda (file)
                            (JsonArray (Cons (JsonString (● file first))
                                             (match (assoc-ref digests (● file first))
                                               ((Some digest) (list (JsonString digest)))
                                               ((None) (Nil))))))
                          files)))))))

    (define (files-under (directory String) (relative String))
      (→ (List (Pair String String)))
      (! fs building)
      (concatenate
       (map (lambda (name)
              (let* ((file (if (string=? relative "") name (string-append relative "/" name)))
                     (path (string-append directory "/" file)))
                (match (status-kind path)
                  ((Some (Directory)) (files-under directory file))
                  ((Some (RegularFile)) (list (new Pair (first file) (second path))))
                  ((Some (SymbolicLink))
                   (if (content-named? file)
                       (list (new Pair (first file) (second path)))
                       (unexpected-entry path)))
                  (_ (unexpected-entry path)))))
            (filter
             (lambda (name) (not (and (string=? relative "") (string=? name ".snail-target"))))
             (directory-names (if (string=? relative "")
                                  directory
                                  (string-append directory "/" relative)))))))

    ;; ---- Publication ----

    ;; Publishes each generation by replacing its target's link with one to
    ;; it. Every destination is checked, and every new link made beside its
    ;; generation, before any is renamed into place. Each rename is atomic;
    ;; several are not one transaction, so a later rename that fails keeps
    ;; the outputs published before it and removes only the rest.

    (define (publish-project (candidate Candidate)) (→ (Result Unit String)) (! fs)
      (let ((outputs (● candidate outputs)) (project (● candidate project)))
        (match (attempt
                (lambda () (for-each (lambda (output) (prepare-link project output)) outputs)))
          ((Err failure) (discard outputs) (Err (failure->string failure)))
          ((Ok _) (rename-links project outputs)))))

    ;; Removes a candidate's generations, publishing none of them.

    (define (discard-candidate (candidate Candidate)) (→ Unit) (! fs)
      (discard (● candidate outputs)))

    (define (prepare-link (project String) (output Output)) (→ Unit) (! fs building)
      (let ((directory (● output directory)))
        (check-output (output-link project output) (● output name))
        (expect-done (make-symbolic-link (base-name directory)
                                         (string-append directory "/.snail-publish"))
                     (string-append "cannot link " directory))))

    (define (rename-links (project String) (outputs (List Output))) (→ (Result Unit String)) (! fs)
      (match outputs
        ((Nil) (Ok (unit)))
        ((Cons output rest)
         (match (rename-file (string-append (● output directory) "/.snail-publish")
                             (output-link project output))
           ((Ok _) (rename-links project rest))
           ((Err error)
            (discard outputs)
            (Err (string-append "cannot publish " (● output name) ": " (show error))))))))

    (define (output-link (project String) (output Output)) (→ String)
      (string-append project "/build/" (● output name)))

    ;; A removal that fails leaves that generation; the failure the build
    ;; met is the one it reports.

    (define (discard (outputs (List Output))) (→ Unit) (! fs)
      (for-each (lambda (output)
                  (remove-tree (● output directory))
                  (unit))
                outputs))

    ;; ---- Files ----

    ;; The kind of what is at `path`, not following a link, or None when
    ;; nothing is.

    (define (status-kind (path String)) (→ (Option FileKind)) (! fs)
      (match (file-status path)
        ((Ok status) (Some (● status kind)))
        ((Err _) (None))))

    (define (kind-is? (path String) (kind FileKind)) (→ Bool) (! fs)
      (match (new Pair (first (status-kind path)) (second kind))
        ((Pair (Some (RegularFile)) (RegularFile)) #t)
        ((Pair (Some (Directory)) (Directory)) #t)
        ((Pair (Some (SymbolicLink)) (SymbolicLink)) #t)
        (_ #f)))

    (define (exists? (path String)) (→ Bool) (! fs)
      (match (status-kind path)
        ((Some _) #t)
        ((None) #f)))

    (define (directory-names (path String)) (→ (List String)) (! fs building)
      (match (list-directory path)
        ((Ok names) names)
        ((Err error) (fail-build (string-append "cannot read directory " path ": " (show error))))))

    ;; Copies a file's bytes to `to`, making its directory first.

    (define (copy-into (from String) (to String) (failure String)) (→ Unit) (! fs building)
      (unless (kind-is? from (RegularFile))
        (fail-build (string-append failure ": there is no file at " from)))
      (expect-done (make-directories (directory-part to)) failure)
      (write-bytes to (read-bytes from)))

    (define (expect-done (result (Result T FileError)) (failure String))
      (→ Unit)
      (! building)
      (∀ (T))
      (match result
        ((Ok _) (unit))
        ((Err error) (fail-build (string-append failure ": " (show error))))))

    ;; ---- Text ----

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (split-path (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (define (first-component (path String)) (→ String)
      (match (string-index path #\/)
        ((Some index) (substring path 0 index))
        ((None) path)))

    (define (base-name (path String)) (→ String)
      (match (last (split-path path))
        ((Some name) name)
        ((None) path)))

    ;; The directory that holds `path`, which has at least one slash.

    (define (directory-part (path String)) (→ String)
      (substring path 0 (- (string-length path) (+ (string-length (base-name path)) 1))))

    ))
