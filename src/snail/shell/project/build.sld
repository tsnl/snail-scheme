;; A project's build: each target compiled, linked and packaged into a
;; generation of its own, then published by replacing the target's link at
;; once. The project planner (snail shell project plan) hands out waves
;; of phases that can run now, dependencies first: a
;; phase builds a target into its generation, or runs a producer, whose
;; output refines the plan. A phase that embeds a target's files is first
;; given those of each target it embeds, built in an earlier phase.
;;
;; A debug or release build links each program into one module. A
;; development build compiles a target a library at a time, in the session
;; the target's last development build left, so it compiles again only the
;; libraries an edit reaches, and assembles each module in-process (snail
;; shell assembler), which only the toolchain's runtime can.
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
   Development
   Failure
   CompileFailure
   BuildFailure
   failure->string
   Output
   Candidate
   Retained
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
   (only (snail shell compiler session)
         Session
         make-session
         build-session)
   (snail shell compiler inputs)
   (snail shell project plan)
   (snail shell process)
   (snail shell assembler)
   (snail shell json)
   (snail shell json read)
   (snail shell compiler sha256)
   (snail shell utf8))
  (begin

    ;; ---- Tools and modes ----

    ;; What a build runs besides the compiler: `root` holds the standard
    ;; libraries (src/), the browser host's files and the native runner,
    ;; `runtime` is the runtime module a program is linked with, and `node`
    ;; runs producers. Assembly and linking use the toolchain runtime.
    (struct Tools
      ((root String)
       (runtime String)
       (node String)))

    ;; Debug and release both link the program into one module, without
    ;; function-body optimization. A development build
    ;; leaves a module per library, each an object of the project's store,
    ;; with modules.json naming them in link order and the runtime, which
    ;; both hosts link as the program starts.
    (enum Mode
      (Debug)
      (Release)
      (Development))

    ;; ---- Failures ----

    ;; Why a build stopped: a compile's diagnostics, each naming its source
    ;; point, or a failure of the build's own work, which names a file or a
    ;; command.
    (enum Failure
      (CompileFailure ((diagnostics Diagnostics)))
      (BuildFailure ((message String))))

    (: failure->string (impl (Fn Failure -> String)))
    (define (failure->string failure)
      (match failure
        ((CompileFailure diagnostics) (diagnostics->string diagnostics))
        ((BuildFailure message) message)))

    ;; A build stops at the first failure it meets, and nothing after the
    ;; failure runs, so a yield to this effect saves no frames. `attempt`
    ;; turns the work into a Result.
    (effect building
      ((ctl stop (dyn (Fn Failure -> Never)))))

    (: fail-build (All (A) (impl (Fn String -> A ! building))))
    (define (fail-build message)
      (absurd (stop (BuildFailure message))))

    (: attempt (All (T e) (impl (Fn (dyn (Fn -> T ! building e)) -> (Result T Failure) ! e))))
    (define (attempt work)
      (handle building
          ((stop (lambda (failure) (Err failure))))
        (Ok (work))))

    ;; A compile that fails stops the build with its diagnostic. The plan
    ;; supplies every input a phase needs before it runs, so a compile that
    ;; asks for one names a need the planner missed.
    (: compiled
       (All (T e) (requires (Copy T)) (impl (Fn (dyn (Fn -> T ! compile e)) -> T ! building e))))
    (define (compiled work)
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (absurd (stop (CompileFailure diagnostics))))
        ((Err (Requested request))
         (fail-build (string-append "internal error: the build plan did not supply the input "
                                    (request->string request))))))

    ;; ---- Projects ----

    ;; The project described by `directory`'s project.datum.
    (: read-project (impl (Fn String -> (Result Project Failure) ! fs)))
    (define (read-project directory)
      (let ((file (project-file directory)))
        (attempt (lambda ()
                   (unless (file-exists? file)
                     (fail-build (string-append "there is no project file at " file)))
                   (compiled (lambda () (parse-project (read-file file) file)))))))

    (: project-file (impl (Fn String -> String)))
    (define (project-file directory)
      (string-append directory "/project.datum"))

    ;; One build's fixed context: what it runs, the project and its
    ;; description, the mode, the scratch directory its compiles and
    ;; producers work in, which no other build shares, and the prefix its
    ;; generations' names begin with.
    (struct Builder
      ((tools Tools)
       (project String)
       (description Project)
       (mode Mode)
       (scratch String)
       (prefix String)))

    ;; A project's build targets as the planner takes them, in declaration
    ;; order: each entry and library root found in the project's directory,
    ;; and the standard libraries' directory after the roots.
    (: plan-targets (impl (Fn Builder -> (List Target) ! fs building)))
    (define (plan-targets builder)
      (map (lambda (target)
             (match target
               ((ProgramTarget program)
                (Target (::name program)
                        #f
                        (entry-source builder #f (::entry program))
                        (library-directories builder (::libraries program))
                        (::loc program)))
               ((BrowserTarget browser)
                (Target (::name browser)
                        #t
                        (entry-source builder #t (::entry browser))
                        (library-directories builder (::libraries browser))
                        (::loc browser)))))
           (::builds (::description builder))))

    ;; Entry selection emits ordinary source, so normal import resolution,
    ;; type checking and instance selection establish its contract. A digest
    ;; names immutable scaffolding: development sessions keep the same source
    ;; identity, and concurrent builds never replace one another's entry.
    (: entry-source (impl (Fn Builder Bool ProjectEntry -> String ! fs building)))
    (define (entry-source builder browser? entry)
      (match entry
        ((SourceEntry path) (in-project builder path))
        ((ApplicationEntry library name)
         (let* ((text (application-source browser? library name))
                (directory (string-append (::project builder) "/build/.snail-entry"))
                (file
                 (string-append directory "/" (bytes->hex (sha256 (string->utf8 text))) ".sld")))
           (expect-done (make-directories directory) (string-append "cannot make " directory))
           (unless (file-exists? file)
             (let ((writing (string-append file ".writing."
                                           (bytes->hex
                                            (sha256 (string->utf8 (::scratch builder)))))))
               (write-file writing text)
               (expect-done (rename-file writing file) (string-append "cannot place " file))))
           file))))

    (: application-source (impl (Fn Bool (List String) String -> String)))
    (define (application-source browser? library name)
      (string-append "(import (snail core base) (snail shell application) "
                     (if browser? "(snail shell page) " "")
                     "(prefix (" (string-join library " ") ") selected:))\n"
                     (if browser?
                         "(define-page-entry selected:"
                         "(start (ann (Entry) (Entry selected:")
                     name (if browser? ")\n" ")))\n")))

    (: in-project (impl (Fn Builder ProjectPath -> String)))
    (define (in-project builder path)
      (if (string=? (::text path) ".")
          (::project builder)
          (string-append (::project builder) "/" (::text path))))

    (: library-directories (impl (Fn Builder (List ProjectPath) -> (List String))))
    (define (library-directories builder roots)
      (append (map (lambda (root) (in-project builder root)) roots)
              (list (string-append (::root (::tools builder)) "/src"))))

    (: root-target (impl (Fn (List Target) String String -> Target ! building)))
    (define (root-target targets file name)
      (match (find (lambda (target) (string=? (::name target) name)) targets)
        ((Some target) target)
        ((None) (fail-build (string-append "unknown project build target " name " in " file)))))

    ;; ---- A build ----

    ;; A target's generation: the target's name, the directory that holds
    ;; what was built for it, and its digest, which a change to any file in
    ;; it changes and nothing else does. A development build counts the
    ;; modules it holds and how many of those it compiled; a linked build
    ;; holds one, which it compiled. `files` are the digests of its files
    ;; but its modules and linked files, whose names are already digests,
    ;; by relative name. `linked` holds the paths of the files its program
    ;; links; editing one compiles the library that links it again.
    (struct Output
      ((name String)
       (directory String)
       (digest String)
       (compiled I64)
       (modules I64)
       (files (List (Pair String String)))
       (linked (List String))))

    ;; What a build made and has not published: each target's generation,
    ;; in plan order, which puts the first root first.
    (struct Candidate
      ((project String)
       (outputs (List Output))))

    ;; What a target's development builds carry from one to the next: the
    ;; session its compile left, the entry and library directories it was
    ;; made for, and each module as assembled. The two change together, so
    ;; a module the session did not compile again has the text it had when
    ;; it was assembled, and the build reuses its digest and bytes.
    (struct Retained
      ((name String)
       (entry String)
       (directories (List String))
       (session Session)
       (modules (List Assembled))))

    ;; A module as assembled: its library, its bytes, and their digest,
    ;; which names the object it is placed as.
    (struct Assembled
      ((library String)
       (digest String)
       (bytes Bytes)))

    ;; A built target: its node in the plan, its generation, and the files
    ;; in it, each relative name with its path, in name order.
    (struct Generation
      ((node I64)
       (output Output)
       (files (List (Pair String String)))))

    ;; What a build has made so far: the inputs the next phase compiles
    ;; with, the targets built, the names of those whose files the inputs
    ;; already hold, each target's retained session, and the failure that
    ;; stopped the build, if one did. No phase runs after a failure, and
    ;; the sessions the phases before it advanced stay advanced.
    (struct Progress
      ((inputs Inputs)
       (generations (List Generation))
       (supplied (List String))
       (retained (List Retained))
       (failure (Option Failure))))

    ;; Builds the targets `names` of the project described by `project`, in
    ;; its directory `directory`, naming each generation with `prefix`. The
    ;; build works in a directory of its own in `scratch`, removed after. It
    ;; answers what it built, and what the sessions in `retained` became:
    ;; a failed build keeps each session it advanced.
    (: build-project
       (impl (Fn Tools String Project (List String) Mode String String (List Retained)
                 -> (Pair (Result Candidate Failure) (List Retained))
                 ! mut fs clock process)))
    (define (build-project tools directory project names mode scratch prefix retained)
      (match (attempt (lambda () (fresh-scratch scratch)))
        ((Err failure) (Pair (Err failure) retained))
        ((Ok working)
         (let ((built (build-roots (Builder tools directory project mode working prefix)
                                   names
                                   (still-built project retained))))
           (remove-tree working)
           built))))

    (: fresh-scratch (impl (Fn String -> String ! fs clock building)))
    (define (fresh-scratch scratch)
      (expect-done (make-directories scratch) (string-append "cannot make " scratch))
      (fresh-directory (string-append scratch "/build-") "" (monotonic-nanoseconds)))

    ;; A target's session goes with the target.
    (: still-built (impl (Fn Project (List Retained) -> (List Retained))))
    (define (still-built project retained)
      (filter (lambda (entry)
                (match (find-target (::builds project) (::name entry))
                  ((Some _) #t)
                  ((None) #f)))
              retained))

    (: build-roots
       (impl (Fn Builder
                 (List String)
                 (List Retained)
                 ->
                 (Pair (Result Candidate Failure) (List Retained))
                 ! mut fs clock process)))
    (define (build-roots builder names retained)
      (match (attempt (lambda () (plan-roots builder names)))
        ((Err failure) (Pair (Err failure) retained))
        ((Ok plan)
         (let ((progress (run-waves builder plan (Progress no-inputs (Nil) (Nil) retained (None)))))
           (Pair (outcome builder progress) (::retained progress))))))

    (: plan-roots (impl (Fn Builder (List String) -> Plan ! fs building)))
    (define (plan-roots builder names)
      (let* ((targets (plan-targets builder))
             (file (project-file (::project builder)))
             (roots (map (lambda (name) (root-target targets file name)) names))
             (printed (in-scratch builder "plan")))
        (expect-done (make-directories printed) (string-append "cannot make " printed))
        (compiled (lambda () (plan-build targets roots no-inputs printed)))))

    ;; A build that failed discards every generation it made.
    (: outcome (impl (Fn Builder Progress -> (Result Candidate Failure) ! fs)))
    (define (outcome builder progress)
      (match (::failure progress)
        ((Some failure)
         (discard (map ::output (::generations progress)))
         (Err failure))
        ((None)
         (Ok (Candidate (::project builder)
                        (map ::output (by-node (::generations progress))))))))

    ;; Runs each wave's phases in order. A wave that leaves phases waiting
    ;; has run the producers whose outputs they need, and the plan refined
    ;; with them hands out the next.
    (: run-waves (impl (Fn Builder Plan Progress -> Progress ! mut fs clock process)))
    (define (run-waves builder plan progress)
      (let* ((wave (next-phases plan))
             (plan (::second wave))
             (progress (fold-left (lambda (progress entry) (run-phase builder plan entry progress))
                                  progress
                                  (::first wave))))
        (if (and (phases-left? plan) (not (failed? progress)))
            (match (attempt (lambda ()
                              (compiled (lambda () (refine-plan plan (::inputs progress))))))
              ((Ok refined) (run-waves builder refined progress))
              ((Err failure) (Progress-failure-set progress (Some failure))))
            progress)))

    (: failed? (impl (Fn Progress -> Bool)))
    (define (failed? progress)
      (match (::failure progress)
        ((Some _) #t)
        ((None) #f)))

    ;; A phase after a failure does not run; a phase that fails records it.
    (: run-phase
       (impl (Fn Builder Plan (Pair I64 Phase) Progress -> Progress ! mut fs clock process)))
    (define (run-phase builder plan entry progress)
      (if (failed? progress)
          progress
          (match (attempt (lambda () (phase-work builder plan entry progress)))
            ((Ok advanced) advanced)
            ((Err failure) (Progress-failure-set progress (Some failure))))))

    (: phase-work
       (impl
        (Fn Builder Plan (Pair I64 Phase) Progress -> Progress ! mut fs clock process building)))
    (define (phase-work builder plan entry progress)
      (let ((progress (supply-embedded builder (embedded-names plan (::first entry)) progress)))
        (match (::second entry)
          ((ProducePhase producer)
           (Progress-inputs-set progress
                                (produce builder
                                         (::first entry)
                                         producer
                                         (::inputs progress))))
          ((BuildPhase target) (build-target builder (::first entry) target progress)))))

    ;; The targets whose files the phase at `node` embeds: the builds among
    ;; its needs, each built in an earlier wave, or earlier in this one.
    (: embedded-names (impl (Fn Plan I64 -> (List String))))
    (define (embedded-names plan node)
      (let ((steps (::steps plan)))
        (match (::needs (vector-ref steps node))
          ((Known nodes)
           (concatenate (map (lambda (need)
                               (match (::phase (vector-ref steps need))
                                 ((BuildPhase target) (list (::name target)))
                                 (_ (Nil))))
                             nodes)))
          ((Waiting _ _) (panic "internal error: a wave handed out a waiting phase")))))

    ;; Each embedded target's files join the inputs once, read as they are
    ;; in its generation.
    (: supply-embedded (impl (Fn Builder (List String) Progress -> Progress ! fs building)))
    (define (supply-embedded builder names progress)
      (fold-left (lambda (progress name)
                   (if (member? name (::supplied progress))
                       progress
                       (Progress-supplied-set
                        (Progress-inputs-set progress
                                             (supply-artifact (::inputs progress)
                                                              name
                                                              (snapshot (generation-named progress
                                                                                          name))))
                        (Cons name (::supplied progress)))))
                 progress
                 names))

    (: generation-named (impl (Fn Progress String -> Generation)))
    (define (generation-named progress name)
      (match (find
              (lambda (generation) (string=? (::name (::output generation)) name))
              (::generations progress))
        ((Some generation) generation)
        ((None) (panic (string-append "internal error: the build plan embeds " name
                                      " before building it")))))

    ;; A development generation holds no objects: its manifest names the
    ;; store they are in. The snapshot an embedding build gets carries
    ;; them, each at store/sha256/DIGEST, and a manifest that says so, so
    ;; an embedded page is complete wherever it is served from.
    (: snapshot (impl (Fn Generation -> ArtifactFiles ! fs building)))
    (define (snapshot generation)
      (let ((files (map (lambda (file) (Pair (::first file) (read-bytes (::second file))))
                        (::files generation))))
        (match (assoc-ref files "modules.json")
          ((Some bytes)
           (with-objects (::directory (::output generation)) files bytes))
          ((None) files))))

    (: with-objects (impl (Fn String ArtifactFiles Bytes -> ArtifactFiles ! fs building)))
    (define (with-objects directory files bytes)
      (match (manifest-json bytes)
        ((Some json)
         (let ((store (string-append directory "/" (json-text json "store"))))
           (list-sort (lambda (a b) (string<? (::first a) (::first b)))
                      (append (map (lambda (file)
                                     (if (string=? (::first file) "modules.json")
                                         (Pair "modules.json"
                                               (string->utf8 (json->string (store-set json))))
                                         file))
                                   files)
                              (map (lambda (digest)
                                     (Pair (object-path "store" digest)
                                           (read-bytes (object-path store digest))))
                                   (manifest-digests json))))))
        ((None) (fail-build (string-append directory "/modules.json is not a manifest")))))

    (: manifest-json (impl (Fn Bytes -> (Option Json))))
    (define (manifest-json bytes)
      (match (utf8->string bytes)
        ((Ok text) (string->json text))
        ((Err _) (None))))

    ;; The digests of the objects a manifest names: the runtime, each
    ;; module and each linked file.
    (: manifest-digests (impl (Fn Json -> (List String))))
    (define (manifest-digests json)
      (map (lambda (entry) (json-text entry "digest"))
           (concatenate (list (match (json-member json "runtime")
                                ((Some runtime) (list runtime))
                                ((None) (Nil)))
                              (json-array json "modules")
                              (json-array json "files")))))

    ;; The manifest with its objects in store/ beside it.
    (: store-set (impl (Fn Json -> Json)))
    (define (store-set json)
      (match json
        ((JsonObject members)
         (JsonObject (map (lambda (member)
                            (if (string=? (::first member) "store")
                                (Pair "store" (JsonString "store/"))
                                member))
                          members)))
        (_ json)))

    (: json-text (impl (Fn Json String -> String)))
    (define (json-text json name)
      (match (json-member json name)
        ((Some (JsonString text)) text)
        (_ "")))

    (: json-array (impl (Fn Json String -> (List Json))))
    (define (json-array json name)
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    (: by-node (impl (Fn (List Generation) -> (List Generation))))
    (define (by-node generations)
      (list-sort (lambda (a b) (< (::node a) (::node b))) generations))

    ;; ---- Targets ----

    ;; Builds a target into a new generation, which goes if the build of it
    ;; fails. A development build's session advances once its modules are
    ;; assembled, so a failure packaging the target keeps it.
    (: build-target (impl (Fn Builder I64 Target Progress -> Progress ! mut fs clock building)))
    (define (build-target builder node target progress)
      (let* ((name (::name target))
             (directory (prepare-generation builder name))
             (program (removing directory
                                (lambda () (build-program builder node target directory progress))))
             (progress (Progress-retained-set progress (::retained program))))
        (match (attempt (lambda () (package builder target directory)))
          ((Ok files)
           (Progress-generations-set progress
                                     (Cons (Generation node
                                                       (program-output program name directory files)
                                                       files)
                                           (::generations progress))))
          ((Err failure)
           (remove-tree directory)
           (Progress-failure-set progress (Some failure))))))

    ;; `work`'s value; when it fails, `directory` goes before the failure
    ;; does.
    (: removing (All (T e) (impl (Fn String (dyn (Fn -> T ! building e)) -> T ! fs building e))))
    (define (removing directory work)
      (match (attempt work)
        ((Ok value) value)
        ((Err failure)
         (remove-tree directory)
         (absurd (stop failure)))))

    ;; What building a target's program left: how many modules it compiled
    ;; of how many, the files it links, by their sources' paths, and the
    ;; sessions as they are after it.
    (struct Program
      ((compiled I64)
       (modules I64)
       (linked (List String))
       (retained (List Retained))))

    (: program-output (impl (Fn Program String String (List (Pair String String)) -> Output ! fs)))
    (define (program-output program name directory files)
      (let ((digests (file-digests files)))
        (Output name
                directory
                (generation-digest files digests)
                (::compiled program)
                (::modules program)
                digests
                (::linked program))))

    ;; The target's program in its generation, with the files it links: one
    ;; module for a debug or release build, a module per library for a
    ;; development build.
    (: build-program (impl (Fn Builder I64 Target String Progress -> Program ! mut fs building)))
    (define (build-program builder node target directory progress)
      (in-working builder
                  node
                  (lambda (working)
                    (match (::mode builder)
                      ((Development) (develop-program builder target directory working progress))
                      (_
                       (let ((links (link-program builder
                                                  (::entry target)
                                                  (::directories target)
                                                  (::inputs progress)
                                                  working
                                                  (string-append directory "/program.wasm"))))
                         (place-links (string-append directory "/store")
                                      (base-name directory)
                                      links)
                         (Program 1
                                  1
                                  (map ::path links)
                                  (::retained progress))))))))

    ;; A browser target's host files and public tree; then the files the
    ;; generation holds.
    (: package (impl (Fn Builder Target String -> (List (Pair String String)) ! fs building)))
    (define (package builder target directory)
      (when (::browser? target)
        (package-browser builder (::name target) directory))
      (generation-files directory))

    ;; `work` in a directory of its own in the build's scratch, removed after.
    (: in-working (All (T e) (impl (Fn Builder I64 (dyn (Fn String -> T ! fs e)) -> T ! fs e))))
    (define (in-working builder node work)
      (let ((working (in-scratch builder (string-append "phase-" (show node)))))
        (make-directories working)
        (let ((result (work working)))
          (remove-tree working)
          result)))

    (: in-scratch (impl (Fn Builder String -> String)))
    (define (in-scratch builder name)
      (string-append (::scratch builder) "/" name))

    ;; ---- Programs ----

    ;; The program at `entry`, compiled in this process to one module and
    ;; linked with the runtime into `output`; the files it links ship beside
    ;; it. The compile's own files stay in `working`.
    (: link-program
       (impl (Fn Builder String (List String) Inputs String String -> (List LinkedFile)
                 ! mut fs building)))
    (define (link-program builder entry directories inputs working output)
      (let ((program (compiled (lambda ()
                                 (source->wat directories
                                              entry
                                              (lambda (loading forms)
                                                (generated-syntax working
                                                                  directories
                                                                  loading
                                                                  forms))
                                              inputs)))))
        (match (link (::text program)
                     (read-bytes (::runtime (::tools builder))))
          ((Ok bytes) (write-bytes output bytes))
          ((Err message) (fail-build (string-append "cannot link program: " message))))
        (::links program)))

    ;; ---- Objects ----

    ;; Each file the program links is an object of a store: a file at
    ;; STORE/sha256/DIGEST, named for the SHA-256 of its bytes, placed once
    ;; however many libraries link it, where its host reads it when the
    ;; program first asks for it. A linked program's objects are in store/
    ;; beside it. A development build's generations share the project's
    ;; store, build/.snail-store, which their manifests name relative to
    ;; themselves, so a generation holds no object, and an edit that
    ;; changes no file adds none. Each object placed is answered with its
    ;; digest and size, for the manifest.
    (: place-links
       (impl (Fn String String (List LinkedFile) -> (List (Pair String I64)) ! fs building)))
    (define (place-links store token links)
      (map (lambda (link) (place-link store token link))
           (delete-duplicates (lambda (a b) (string=? (::digest a) (::digest b)))
                              links)))

    ;; A file is named for the digest of the bytes its compile read, so the
    ;; bytes placed must be those: a file edited since fails the build, and
    ;; the next one compiles against its new bytes.
    (: place-link (impl (Fn String String LinkedFile -> (Pair String I64) ! fs building)))
    (define (place-link store token link)
      (let ((from (::path link)) (digest (::digest link)))
        (unless (kind-is? from (RegularFile))
          (fail-build
           (string-append "cannot place the linked file " from ": there is no file there")))
        (let ((bytes (read-bytes from)))
          (unless (string=? (bytes->hex (sha256 bytes)) digest)
            (fail-build (string-append "the linked file " from " changed during the build")))
          (place-object store token digest bytes)
          (Pair digest (vector-length bytes)))))

    ;; An object already in the store is left as it is: its bytes are what
    ;; its name says. A new one is written beside its place, under a name
    ;; this build alone writes, and renamed into it, so a reader never sees
    ;; a partial object, and two builds placing one object at once each
    ;; rename the same bytes.
    (: place-object (impl (Fn String String String Bytes -> Unit ! fs building)))
    (define (place-object store token digest bytes)
      (let ((to (object-path store digest)))
        (unless (kind-is? to (RegularFile))
          (expect-done (make-directories (directory-part to)) (string-append "cannot make " to))
          (let ((writing (string-append to ".writing." token)))
            (write-bytes writing bytes)
            (expect-done (rename-file writing to) (string-append "cannot place " to))))))

    (: object-path (impl (Fn String String -> String)))
    (define (object-path store digest)
      (string-append store "/sha256/" digest))

    ;; The store a project's development builds share.
    (: project-store (impl (Fn Builder -> String)))
    (define (project-store builder)
      (string-append (::project builder) "/build/.snail-store"))

    ;; What a manifest says of its store: the path, relative to the
    ;; manifest, with a trailing slash.
    (: shared-store String)
    (define shared-store "../.snail-store/")

    ;; ---- Development builds ----

    ;; The target compiled in its retained session, or in a new one when
    ;; there is none or its entry or library directories changed; then each
    ;; module written to the generation, assembled again only when the
    ;; session compiled it again. The session the compile left is retained
    ;; with the modules it was assembled into.
    (: develop-program
       (impl (Fn Builder Target String String Progress -> Program ! mut fs building)))
    (define (develop-program builder target directory working progress)
      (let* ((previous (retained-for (::retained progress) target))
             (built (compiled (lambda ()
                                (build-session (::session previous)
                                               (::entry target)
                                               (lambda (loading forms)
                                                 (generated-syntax working
                                                                   (::directories target)
                                                                   loading
                                                                   forms))
                                               (::inputs progress)))))
             (modules (assemble-modules (::first built) (::modules previous)))
             (links (concatenate (map ::links (::first built)))))
        (write-modules builder
                       directory
                       modules
                       (place-links (project-store builder) (base-name directory) links))
        (Program (length (filter ::compiled? (::first built)))
                 (length modules)
                 (map ::path links)
                 (Cons (Retained (::name target)
                                 (::entry target)
                                 (::directories target)
                                 (::second built)
                                 modules)
                       (filter
                        (lambda (entry) (not (string=? (::name entry) (::name target))))
                        (::retained progress))))))

    (: retained-for (impl (Fn (List Retained) Target -> Retained)))
    (define (retained-for retained target)
      (match (find (lambda (entry)
                     (and (string=? (::name entry) (::name target))
                          (string=? (::entry entry) (::entry target))
                          (same-strings? (::directories entry) (::directories target))))
                   retained)
        ((Some entry) entry)
        ((None)
         (Retained (::name target)
                   (::entry target)
                   (::directories target)
                   (make-session (::directories target))
                   (Nil)))))

    (: same-strings? (impl (Fn (List String) (List String) -> Bool)))
    (define (same-strings? a b)
      (match (Pair a b)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x a-rest) (Cons y b-rest)) (and (string=? x y) (same-strings? a-rest b-rest)))
        (_ #f)))

    ;; Each module as this build has it: as the last build assembled it when
    ;; the session did not compile it again, which keeps its text.
    (: assemble-modules (impl (Fn (List Built) (List Assembled) -> (List Assembled) ! building)))
    (define (assemble-modules built previous)
      (map (lambda (module)
             (match (if (::compiled? module)
                        (None)
                        (find (lambda (assembled)
                                (string=? (::library assembled) (::name module)))
                              previous))
               ((Some assembled) assembled)
               ((None) (assemble-module module))))
           built))

    (: assemble-module (impl (Fn Built -> Assembled ! building)))
    (define (assemble-module module)
      (let ((text (::text module)))
        (match (assemble text)
          ((Ok bytes) (Assembled (::name module) (bytes->hex (sha256 bytes)) bytes))
          ((Err message)
           (fail-build (string-append "internal error: cannot assemble the module of "
                                      (::name module)
                                      ": "
                                      message))))))

    ;; The modules and the runtime they link with, each placed as an
    ;; object of the project's store, and modules.json in the generation
    ;; naming them, in link order, with the files the program links.
    (: write-modules
       (impl (Fn Builder String (List Assembled) (List (Pair String I64)) -> Unit ! fs building)))
    (define (write-modules builder directory modules files)
      (let ((store (project-store builder))
            (token (base-name directory))
            (runtime (read-bytes (::runtime (::tools builder)))))
        (for-each (lambda (module)
                    (place-object store token (::digest module) (::bytes module)))
                  modules)
        (let ((runtime-digest (bytes->hex (sha256 runtime))))
          (place-object store token runtime-digest runtime)
          (write-file (string-append directory "/modules.json")
                      (json->string (manifest (Pair runtime-digest (vector-length runtime))
                                              modules
                                              files))))))

    ;; The manifest: the store its objects are in, relative to it, the
    ;; runtime, each module in link order, and each file the program links,
    ;; every object by digest with its size.
    (: manifest (impl (Fn (Pair String I64) (List Assembled) (List (Pair String I64)) -> Json)))
    (define (manifest runtime modules files)
      (JsonObject
       (list (Pair "runtime" (object-json runtime))
             (Pair "store" (JsonString shared-store))
             (Pair "modules"
                   (JsonArray (map (lambda (module)
                                     (JsonObject
                                      (Cons (Pair "name" (JsonString (::library module)))
                                            (object-members (Pair (::digest module)
                                                                  (vector-length
                                                                   (::bytes module)))))))
                                   modules)))
             (Pair "files" (JsonArray (map object-json files))))))

    ;; An object as a manifest names it: its digest and size.
    (: object-json (impl (Fn (Pair String I64) -> Json)))
    (define (object-json object)
      (JsonObject (object-members object)))

    (: object-members (impl (Fn (Pair String I64) -> (List (Pair String Json)))))
    (define (object-members object)
      (list (Pair "digest" (JsonString (::first object)))
            (Pair "size" (JsonInteger (::second object)))))

    ;; Runs a command to its end, and stops the build with what it wrote to
    ;; stderr unless it exits with status 0.
    (: run-command (impl (Fn Command String -> Unit ! process building)))
    (define (run-command command name)
      (match (run command #u8())
        ((Err error) (fail-build (string-append "cannot run " name ": " (::code error))))
        ((Ok captured)
         (match (::exit captured)
           ((Exited 0) (unit))
           (exit (fail-build (string-append name " failed: " (failure-text captured exit))))))))

    ;; A failed command's stderr, or how it ended when it wrote nothing
    ;; that reads as text.
    (: failure-text (impl (Fn Captured Exit -> String)))
    (define (failure-text captured exit)
      (match (utf8->string (::stderr captured))
        ((Ok stderr) (if (string=? stderr "") (how-it-ended exit) stderr))
        ((Err _) (how-it-ended exit))))

    (: how-it-ended (impl (Fn Exit -> String)))
    (define (how-it-ended exit)
      (match exit
        ((Exited code) (string-append "exited with " (show code)))
        ((Signaled name) (string-append "ended by " name))))

    ;; ---- Producers ----

    ;; A producer is compiled from the source the planner printed, linked,
    ;; and run to write its library's syntax, which the
    ;; inputs supply from then on.
    (: produce (impl (Fn Builder I64 Producer Inputs -> Inputs ! mut fs process building)))
    (define (produce builder node producer inputs)
      (in-working builder
                  node
                  (lambda (working)
                    (let ((program (string-append working "/producer.wasm"))
                          (output (string-append working "/output.syntax")))
                      (place-links (string-append working "/store")
                                   "producer"
                                   (link-program builder
                                                 (::source producer)
                                                 (::directories producer)
                                                 inputs
                                                 working
                                                 program))
                      (run-producer builder program output)
                      (supply-producer producer inputs output)))))

    (: run-producer (impl (Fn Builder String String -> Unit ! fs process building)))
    (define (run-producer builder program output)
      (let ((tools (::tools builder)))
        (run-command (Command (::node tools)
                              (list "--no-warnings"
                                    (string-append (::root tools) "/host/native/run-snail.mjs")
                                    program
                                    output)
                              ".")
                     "the producer")
        (unless (file-exists? output)
          (fail-build "the producer did not write its generated library"))))

    ;; The producer is read back from its printed source, so the inputs
    ;; hold the text a compile looks its output up by.
    (: supply-producer (impl (Fn Producer Inputs String -> Inputs ! fs building)))
    (define (supply-producer producer inputs output)
      (let ((text (compiled (lambda ()
                              (printed-producer-text (::directories producer)
                                                     (::source producer))))))
        (unless (string=? (producer-key text) (::key producer))
          (panic "internal error: a producer's printed text does not have its key"))
        (supply-generated inputs text (read-bytes output))))

    ;; ---- Browser packages ----

    (: browser-files (List String))
    (define browser-files
      (list "host.mjs"
            "application.mjs"
            "runtime.mjs"
            "memory.mjs"
            "tasks.mjs"
            "entry.mjs"
            "renderer.mjs"
            "hud.mjs"
            "pictures.mjs"
            "storage.mjs" "load.mjs" "style.css" "ui.mjs" "dom.mjs" "fetch.mjs" "install.mjs"
            "snail-icon.svg" "snail-icon-192.png" "snail-icon-512.png"))

    ;; The names some build writes at a generation's root, whether or not
    ;; this one does: a release build writes program.wasm, and store/ when
    ;; its program links files, a development build modules.json. A public
    ;; tree may use none of them, so one that builds in one mode, or with
    ;; one set of linked files, builds in every other.
    (: generated-names (List String))
    (define generated-names
      (append (list "program.wasm" "modules.json" "store" ".snail-target") browser-files))

    ;; The browser host's files, then the target's public tree, if it has
    ;; one. The page is the project's own index.html; none is generated.
    ;; UTF-8 pages receive a manifest link; a development page is also told
    ;; where modules.json is. A public manifest replaces the default whole.
    (: package-browser (impl (Fn Builder String String -> Unit ! fs building)))
    (define (package-browser builder name directory)
      (copy-browser-assets builder name directory)
      (ensure-web-manifest (string-append (base-name (::project builder)) " / " name)
                           directory)
      (prepare-browser-page directory (development? builder)))

    ;; Public assets were copied first. A supplied manifest is a complete
    ;; replacement; the default is a regular file in the same output tree.
    (: ensure-web-manifest (impl (Fn String String -> Unit ! fs)))
    (define (ensure-web-manifest name directory)
      (let ((path (string-append directory "/manifest.webmanifest")))
        (unless (file-exists? path)
          (write-file path (json->string (web-app-manifest name))))))

    (: prepare-browser-page (impl (Fn String Bool -> Unit ! fs)))
    (define (prepare-browser-page directory development)
      (let ((path (string-append directory "/index.html")))
        (when (kind-is? path (RegularFile))
          (match (utf8->string (read-bytes path))
            ((Err _) (unit))
            ((Ok text) (write-file path (with-web-app text development)))))))

    (: development? (impl (Fn Builder -> Bool)))
    (define (development? builder)
      (match (::mode builder)
        ((Development) #t)
        (_ #f)))

    (: copy-browser-assets (impl (Fn Builder String String -> Unit ! fs building)))
    (define (copy-browser-assets builder name directory)
      (for-each (lambda (file)
                  (copy-into
                   (string-append (::root (::tools builder)) "/host/browser/" file)
                   (string-append directory "/" file)
                   (string-append "cannot copy the browser host's " file)))
                browser-files)
      (match (find-target (::builds (::description builder)) name)
        ((Some (BrowserTarget browser))
         (match (::public browser)
           ((Some path) (copy-public (public-directory builder path) directory #t))
           ((None) (unit))))
        (_ (unit))))

    ;; The public directory, which may not be the project's own or lie in
    ;; its build output, and whose every component is a directory, not a
    ;; link.
    (: public-directory (impl (Fn Builder ProjectPath -> String ! fs building)))
    (define (public-directory builder path)
      (let ((text (::text path)))
        (when (or (string=? text ".") (string=? (first-component text) "build"))
          (fail-build (string-append "public directory overlaps project build output: " text)))
        (fold-left (lambda (directory part)
                     (let ((next (string-append directory "/" part)))
                       (unless (kind-is? next (Directory))
                         (fail-build (string-append
                                      "public path must contain only directories, not links: "
                                      next)))
                       next))
                   (::project builder)
                   (split-path text))))

    ;; Copies a public tree into the generation. Nothing in it may replace
    ;; a file the build made, use a name reserved at the root, or be
    ;; anything but a regular file or a directory.
    (: copy-public (impl (Fn String String Bool -> Unit ! fs building)))
    (define (copy-public source output top?)
      (for-each (lambda (name)
                  (let ((from (string-append source "/" name)) (to (string-append output "/" name)))
                    (when (or (and top? (member? name generated-names))
                              (exists? to)
                              (string=? name ".snail-publish"))
                      (fail-build
                       (string-append "public file conflicts with a build artifact: " from)))
                    (match (status-kind from)
                      ((Some (SymbolicLink))
                       (fail-build (string-append "public files cannot be symbolic links: " from)))
                      ((Some (Directory))
                       (make-directory to)
                       (copy-public from to #f))
                      ((Some (RegularFile)) (copy-into from to (string-append "cannot copy " from)))
                      (_ (fail-build (string-append
                                      "public entry must be a regular file or directory: "
                                      from))))))
                (directory-names source)))

    ;; ---- Generations ----

    ;; A new generation for the target `name` in the project's build
    ;; directory, holding only its ownership marker. The output link there,
    ;; if any, must be one a build published.
    (: prepare-generation (impl (Fn Builder String -> String ! fs clock building)))
    (define (prepare-generation builder name)
      (let ((build (string-append (::project builder) "/build")))
        (when (kind-is? build (SymbolicLink))
          (fail-build (string-append "project build directory cannot be a symbolic link: " build)))
        (expect-done (make-directories build) (string-append "cannot make " build))
        (check-output (string-append build "/" name) name)
        (let ((directory (fresh-directory (string-append build "/" (::prefix builder))
                                          (string-append "-" name)
                                          (monotonic-nanoseconds))))
          (write-file (string-append directory "/.snail-target") name)
          directory)))

    ;; A directory `STEM N SUFFIX` that no other build has made, as mkdtemp
    ;; makes one: N starts at `token`, and goes up while the name is taken.
    (: fresh-directory (impl (Fn String String I64 -> String ! fs building)))
    (define (fresh-directory stem suffix token)
      (let ((directory (string-append stem (show token) suffix)))
        (match (make-directory directory)
          ((Ok _) directory)
          ((Err (AlreadyExists)) (fresh-directory stem suffix (+ token 1)))
          ((Err error) (fail-build (string-append "cannot make " directory ": " (show error)))))))

    ;; An output is replaced only when it is a link to a generation beside
    ;; it whose marker names the target.
    (: check-output (impl (Fn String String -> Unit ! fs building)))
    (define (check-output output name)
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

    (: unmanaged (All (A) (impl (Fn String -> A ! building))))
    (define (unmanaged output)
      (fail-build (string-append "refusing to replace an unmanaged project output: " output)))

    ;; The files of a completed generation, each relative name with its
    ;; path, in name order, without the root's ownership marker.
    (: generation-files (impl (Fn String -> (List (Pair String String)) ! fs building)))
    (define (generation-files directory)
      (list-sort (lambda (a b) (string<? (::first a) (::first b)))
                 (files-under directory "")))

    ;; The digest of each file of a generation but its objects, which are
    ;; named for theirs, by name.
    (: file-digests (impl (Fn (List (Pair String String)) -> (List (Pair String String)) ! fs)))
    (define (file-digests files)
      (map (lambda (file)
             (Pair (::first file) (bytes->hex (sha256 (read-bytes (::second file))))))
           (filter (lambda (file) (not (content-named? (::first file)))) files)))

    (: content-named? (impl (Fn String -> Bool)))
    (define (content-named? name)
      (starts-with? name "store/"))

    ;; A digest of a generation's files: each relative name, with its
    ;; file's digest, but only the name of an object, which is the digest
    ;; of its bytes.
    (: generation-digest
       (impl (Fn (List (Pair String String)) (List (Pair String String)) -> String)))
    (define (generation-digest files digests)
      (bytes->hex
       (sha256
        (string->utf8
         (json->string
          (JsonArray (map (lambda (file)
                            (JsonArray (Cons (JsonString (::first file))
                                             (match (assoc-ref digests (::first file))
                                               ((Some digest) (list (JsonString digest)))
                                               ((None) (Nil))))))
                          files)))))))

    (: files-under (impl (Fn String String -> (List (Pair String String)) ! fs building)))
    (define (files-under directory relative)
      (concatenate
       (map (lambda (name)
              (let* ((file (if (string=? relative "") name (string-append relative "/" name)))
                     (path (string-append directory "/" file)))
                (match (status-kind path)
                  ((Some (Directory)) (files-under directory file))
                  ((Some (RegularFile)) (list (Pair file path)))
                  (_ (fail-build (string-append
                                  "completed output must contain regular files and directories: "
                                  path))))))
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
    (: publish-project (impl (Fn Candidate -> (Result Unit String) ! fs)))
    (define (publish-project candidate)
      (let ((outputs (::outputs candidate)) (project (::project candidate)))
        (match (attempt
                (lambda () (for-each (lambda (output) (prepare-link project output)) outputs)))
          ((Err failure) (discard outputs) (Err (failure->string failure)))
          ((Ok _) (rename-links project outputs)))))

    ;; Removes a candidate's generations, publishing none of them.
    (: discard-candidate (impl (Fn Candidate -> Unit ! fs)))
    (define (discard-candidate candidate)
      (discard (::outputs candidate)))

    (: prepare-link (impl (Fn String Output -> Unit ! fs building)))
    (define (prepare-link project output)
      (let ((directory (::directory output)))
        (check-output (output-link project output) (::name output))
        (expect-done (make-symbolic-link (base-name directory)
                                         (string-append directory "/.snail-publish"))
                     (string-append "cannot link " directory))))

    (: rename-links (impl (Fn String (List Output) -> (Result Unit String) ! fs)))
    (define (rename-links project outputs)
      (match outputs
        ((Nil) (Ok (unit)))
        ((Cons output rest)
         (match (rename-file (string-append (::directory output) "/.snail-publish")
                             (output-link project output))
           ((Ok _) (rename-links project rest))
           ((Err error)
            (discard outputs)
            (Err (string-append "cannot publish " (::name output) ": " (show error))))))))

    (: output-link (impl (Fn String Output -> String)))
    (define (output-link project output)
      (string-append project "/build/" (::name output)))

    ;; A removal that fails leaves that generation; the failure the build
    ;; met is the one it reports.
    (: discard (impl (Fn (List Output) -> Unit ! fs)))
    (define (discard outputs)
      (for-each (lambda (output)
                  (remove-tree (::directory output))
                  (unit))
                outputs))

    ;; ---- Files ----

    ;; The kind of what is at `path`, not following a link, or None when
    ;; nothing is.
    (: status-kind (impl (Fn String -> (Option FileKind) ! fs)))
    (define (status-kind path)
      (match (file-status path)
        ((Ok status) (Some (::kind status)))
        ((Err _) (None))))

    (: kind-is? (impl (Fn String FileKind -> Bool ! fs)))
    (define (kind-is? path kind)
      (match (Pair (status-kind path) kind)
        ((Pair (Some (RegularFile)) (RegularFile)) #t)
        ((Pair (Some (Directory)) (Directory)) #t)
        ((Pair (Some (SymbolicLink)) (SymbolicLink)) #t)
        (_ #f)))

    (: exists? (impl (Fn String -> Bool ! fs)))
    (define (exists? path)
      (match (status-kind path)
        ((Some _) #t)
        ((None) #f)))

    (: directory-names (impl (Fn String -> (List String) ! fs building)))
    (define (directory-names path)
      (match (list-directory path)
        ((Ok names) names)
        ((Err error) (fail-build (string-append "cannot read directory " path ": " (show error))))))

    ;; Copies a file's bytes to `to`, making its directory first.
    (: copy-into (impl (Fn String String String -> Unit ! fs building)))
    (define (copy-into from to failure)
      (unless (kind-is? from (RegularFile))
        (fail-build (string-append failure ": there is no file at " from)))
      (expect-done (make-directories (directory-part to)) failure)
      (write-bytes to (read-bytes from)))

    (: expect-done
       (All (T) (requires (Copy T)) (impl (Fn (Result T FileError) String -> Unit ! building))))
    (define (expect-done result failure)
      (match result
        ((Ok _) (unit))
        ((Err error) (fail-build (string-append failure ": " (show error))))))

    ;; ---- Text ----

    (: starts-with? (impl (Fn String String -> Bool)))
    (define (starts-with? text prefix)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (: split-path (impl (Fn String -> (List String))))
    (define (split-path path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (: first-component (impl (Fn String -> String)))
    (define (first-component path)
      (match (string-index path #\/)
        ((Some index) (substring path 0 index))
        ((None) path)))

    (: base-name (impl (Fn String -> String)))
    (define (base-name path)
      (match (last (split-path path))
        ((Some name) name)
        ((None) path)))

    ;; The directory that holds `path`, which has at least one slash.
    (: directory-part (impl (Fn String -> String)))
    (define (directory-part path)
      (substring path 0 (- (string-length path) (+ (string-length (base-name path)) 1))))

    ))
