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
;; The compiler runs in this program; Binaryen's tools, which link a
;; program with the runtime, and Node, which runs producers, run as
;; commands, through `run` (snail shell process). A build that fails removes
;; every generation it made, and only those, so the outputs of earlier
;; builds stay published.
(define-library (snail shell project build)
  (export
   Tools
   Tools-root
   Tools-runtime
   Tools-node
   Mode
   Debug
   Release
   Development
   Failure
   CompileFailure
   BuildFailure
   failure->string
   Output
   Output-name
   Output-directory
   Output-digest
   Output-files
   Output-linked
   Output-compiled
   Output-modules
   Candidate
   Candidate-project
   Candidate-outputs
   Retained
   read-project
   build-project
   publish-project
   discard-candidate)
  (import
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
         build-session
         Built-compiled?)
   (snail shell compiler inputs)
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
    ;; `runtime` is the runtime module a program is linked with, and `node`
    ;; runs producers. Binaryen's tools are found on PATH, unless WASM_AS,
    ;; WASM_OPT or WASM_MERGE names another.
    (struct Tools
      ((root String)
       (runtime String)
       (node String)))

    ;; A debug build optimizes a little, a release build as far as Binaryen
    ;; goes, and both link the program into one module. A development build
    ;; leaves a module per library, with modules.json naming them in link
    ;; order and the runtime as runtime.wasm, which both hosts link as the
    ;; program starts.
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

    (: failure->string (-> Failure String))
    (define (failure->string failure)
      (match failure
        ((CompileFailure diagnostics) (diagnostics->string diagnostics))
        ((BuildFailure message) message)))

    ;; A build stops at the first failure it meets, and nothing after the
    ;; failure runs, so a yield to this effect saves no frames. `attempt`
    ;; turns the work into a Result.
    (effect building
      ((ctl stop (-> Failure Never))))

    (: fail-build (All (A) (-> String A ! building)))
    (define (fail-build message)
      (absurd (stop (BuildFailure message))))

    (: attempt (All (T e) (-> (-> T ! building e) (Result T Failure) ! e)))
    (define (attempt work)
      (handle building
          ((stop (lambda (failure) (Err failure))))
        (Ok (work))))

    ;; A compile that fails stops the build with its diagnostic. The plan
    ;; supplies every input a phase needs before it runs, so a compile that
    ;; asks for one names a need the planner missed.
    (: compiled (All (T e) (requires (Copy T)) (-> (-> T ! compile e) T ! building e)))
    (define (compiled work)
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (absurd (stop (CompileFailure diagnostics))))
        ((Err (Requested request))
         (fail-build (string-append "internal error: the build plan did not supply the input "
                                    (request->string request))))))

    ;; ---- Projects ----

    ;; The project described by `directory`'s project.datum.
    (: read-project (-> String (Result Project Failure) ! fs))
    (define (read-project directory)
      (let ((file (project-file directory)))
        (attempt (lambda ()
                   (unless (file-exists? file)
                     (fail-build (string-append "there is no project file at " file)))
                   (compiled (lambda () (parse-project (read-file file) file)))))))

    (: project-file (-> String String))
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
    (: plan-targets (-> Builder (List Target)))
    (define (plan-targets builder)
      (map (lambda (target)
             (match target
               ((ProgramTarget program)
                (Target (ProgramBuild-name program)
                        #f
                        (in-project builder (ProgramBuild-entry program))
                        (library-directories builder (ProgramBuild-libraries program))
                        (ProgramBuild-loc program)))
               ((BrowserTarget browser)
                (Target (BrowserBuild-name browser)
                        #t
                        (in-project builder (BrowserBuild-entry browser))
                        (library-directories builder (BrowserBuild-libraries browser))
                        (BrowserBuild-loc browser)))))
           (Project-builds (Builder-description builder))))

    (: in-project (-> Builder ProjectPath String))
    (define (in-project builder path)
      (if (string=? (ProjectPath-text path) ".")
          (Builder-project builder)
          (string-append (Builder-project builder) "/" (ProjectPath-text path))))

    (: library-directories (-> Builder (List ProjectPath) (List String)))
    (define (library-directories builder roots)
      (append (map (lambda (root) (in-project builder root)) roots)
              (list (string-append (Tools-root (Builder-tools builder)) "/src"))))

    (: root-target (-> (List Target) String String Target ! building))
    (define (root-target targets file name)
      (match (find (lambda (target) (string=? (Target-name target) name)) targets)
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
    ;; it was assembled, and the build reuses its file and bytes.
    (struct Retained
      ((name String)
       (entry String)
       (directories (List String))
       (session Session)
       (modules (List Assembled))))

    ;; A module as assembled: its library, its file in the generation,
    ;; named for the digest of its text, and its bytes.
    (struct Assembled
      ((library String)
       (file String)
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
       (-> Tools String Project (List String) Mode String String (List Retained)
           (Pair (Result Candidate Failure) (List Retained))
           ! mut fs clock process))
    (define (build-project tools directory project names mode scratch prefix retained)
      (match (attempt (lambda () (fresh-scratch scratch)))
        ((Err failure) (Pair (Err failure) retained))
        ((Ok working)
         (let ((built (build-roots (Builder tools directory project mode working prefix)
                                   names
                                   (still-built project retained))))
           (remove-tree working)
           built))))

    (: fresh-scratch (-> String String ! fs clock building))
    (define (fresh-scratch scratch)
      (expect-done (make-directories scratch) (string-append "cannot make " scratch))
      (fresh-directory (string-append scratch "/build-") "" (monotonic-nanoseconds)))

    ;; A target's session goes with the target.
    (: still-built (-> Project (List Retained) (List Retained)))
    (define (still-built project retained)
      (filter (lambda (entry)
                (match (find-target (Project-builds project) (Retained-name entry))
                  ((Some _) #t)
                  ((None) #f)))
              retained))

    (: build-roots
       (-> Builder (List String) (List Retained) (Pair (Result Candidate Failure) (List Retained))
           ! mut fs clock process))
    (define (build-roots builder names retained)
      (match (attempt (lambda () (plan-roots builder names)))
        ((Err failure) (Pair (Err failure) retained))
        ((Ok plan)
         (let ((progress (run-waves builder plan (Progress no-inputs (Nil) (Nil) retained (None)))))
           (Pair (outcome builder progress) (Progress-retained progress))))))

    (: plan-roots (-> Builder (List String) Plan ! fs building))
    (define (plan-roots builder names)
      (let* ((targets (plan-targets builder))
             (file (project-file (Builder-project builder)))
             (roots (map (lambda (name) (root-target targets file name)) names))
             (printed (in-scratch builder "plan")))
        (expect-done (make-directories printed) (string-append "cannot make " printed))
        (compiled (lambda () (plan-build targets roots no-inputs printed)))))

    ;; A build that failed discards every generation it made.
    (: outcome (-> Builder Progress (Result Candidate Failure) ! fs))
    (define (outcome builder progress)
      (match (Progress-failure progress)
        ((Some failure)
         (discard (map Generation-output (Progress-generations progress)))
         (Err failure))
        ((None)
         (Ok (Candidate (Builder-project builder)
                        (map Generation-output (by-node (Progress-generations progress))))))))

    ;; Runs each wave's phases in order. A wave that leaves phases waiting
    ;; has run the producers whose outputs they need, and the plan refined
    ;; with them hands out the next.
    (: run-waves (-> Builder Plan Progress Progress ! mut fs clock process))
    (define (run-waves builder plan progress)
      (let* ((wave (next-phases plan))
             (plan (Pair-second wave))
             (progress (fold-left (lambda (progress entry) (run-phase builder plan entry progress))
                                  progress
                                  (Pair-first wave))))
        (if (and (phases-left? plan) (not (failed? progress)))
            (match (attempt (lambda ()
                              (compiled (lambda () (refine-plan plan (Progress-inputs progress))))))
              ((Ok refined) (run-waves builder refined progress))
              ((Err failure) (Progress-failure-set progress (Some failure))))
            progress)))

    (: failed? (-> Progress Bool))
    (define (failed? progress)
      (match (Progress-failure progress)
        ((Some _) #t)
        ((None) #f)))

    ;; A phase after a failure does not run; a phase that fails records it.
    (: run-phase (-> Builder Plan (Pair I64 Phase) Progress Progress ! mut fs clock process))
    (define (run-phase builder plan entry progress)
      (if (failed? progress)
          progress
          (match (attempt (lambda () (phase-work builder plan entry progress)))
            ((Ok advanced) advanced)
            ((Err failure) (Progress-failure-set progress (Some failure))))))

    (: phase-work
       (-> Builder Plan (Pair I64 Phase) Progress Progress ! mut fs clock process building))
    (define (phase-work builder plan entry progress)
      (let ((progress (supply-embedded builder (embedded-names plan (Pair-first entry)) progress)))
        (match (Pair-second entry)
          ((ProducePhase producer)
           (Progress-inputs-set progress
                                (produce builder
                                         (Pair-first entry)
                                         producer
                                         (Progress-inputs progress))))
          ((BuildPhase target) (build-target builder (Pair-first entry) target progress)))))

    ;; The targets whose files the phase at `node` embeds: the builds among
    ;; its needs, each built in an earlier wave, or earlier in this one.
    (: embedded-names (-> Plan I64 (List String)))
    (define (embedded-names plan node)
      (let ((steps (Plan-steps plan)))
        (match (Step-needs (vector-ref steps node))
          ((Known nodes)
           (concatenate (map (lambda (need)
                               (match (Step-phase (vector-ref steps need))
                                 ((BuildPhase target) (list (Target-name target)))
                                 (_ (Nil))))
                             nodes)))
          ((Waiting _ _) (panic "internal error: a wave handed out a waiting phase")))))

    ;; Each embedded target's files join the inputs once, read as they are
    ;; in its generation.
    (: supply-embedded (-> Builder (List String) Progress Progress ! fs))
    (define (supply-embedded builder names progress)
      (fold-left (lambda (progress name)
                   (if (member? name (Progress-supplied progress))
                       progress
                       (Progress-supplied-set
                        (Progress-inputs-set progress
                                             (supply-artifact (Progress-inputs progress)
                                                              name
                                                              (snapshot (generation-named progress
                                                                                          name))))
                        (Cons name (Progress-supplied progress)))))
                 progress
                 names))

    (: generation-named (-> Progress String Generation))
    (define (generation-named progress name)
      (match (find
              (lambda (generation) (string=? (Output-name (Generation-output generation)) name))
              (Progress-generations progress))
        ((Some generation) generation)
        ((None) (panic (string-append "internal error: the build plan embeds " name
                                      " before building it")))))

    (: snapshot (-> Generation ArtifactFiles ! fs))
    (define (snapshot generation)
      (map (lambda (file) (Pair (Pair-first file) (read-bytes (Pair-second file))))
           (Generation-files generation)))

    (: by-node (-> (List Generation) (List Generation)))
    (define (by-node generations)
      (list-sort (lambda (a b) (< (Generation-node a) (Generation-node b))) generations))

    ;; ---- Targets ----

    ;; Builds a target into a new generation, which goes if the build of it
    ;; fails. A development build's session advances once its modules are
    ;; assembled, so a failure packaging the target keeps it.
    (: build-target (-> Builder I64 Target Progress Progress ! mut fs clock process building))
    (define (build-target builder node target progress)
      (let* ((name (Target-name target))
             (directory (prepare-generation builder name))
             (program (removing directory
                                (lambda () (build-program builder node target directory progress))))
             (progress (Progress-retained-set progress (Program-retained program))))
        (match (attempt (lambda () (package builder target directory)))
          ((Ok files)
           (Progress-generations-set progress
                                     (Cons (Generation node
                                                       (program-output program name directory files)
                                                       files)
                                           (Progress-generations progress))))
          ((Err failure)
           (remove-tree directory)
           (Progress-failure-set progress (Some failure))))))

    ;; `work`'s value; when it fails, `directory` goes before the failure
    ;; does.
    (: removing (All (T e) (-> String (-> T ! building e) T ! fs building e)))
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

    (: program-output (-> Program String String (List (Pair String String)) Output ! fs))
    (define (program-output program name directory files)
      (let ((digests (file-digests files)))
        (Output name
                directory
                (generation-digest files digests)
                (Program-compiled program)
                (Program-modules program)
                digests
                (Program-linked program))))

    ;; The target's program in its generation, with the files it links: one
    ;; module for a debug or release build, a module per library for a
    ;; development build.
    (: build-program (-> Builder I64 Target String Progress Program ! mut fs process building))
    (define (build-program builder node target directory progress)
      (in-working builder
                  node
                  (lambda (working)
                    (match (Builder-mode builder)
                      ((Development) (develop-program builder target directory working progress))
                      (_
                       (let ((links (link-program builder
                                                  (Target-entry target)
                                                  (Target-directories target)
                                                  (Progress-inputs progress)
                                                  working
                                                  (string-append directory "/program.wasm"))))
                         (place-links directory links)
                         (Program 1
                                  1
                                  (map LinkedFile-path links)
                                  (Progress-retained progress))))))))

    ;; A browser target's host files and public tree; then the files the
    ;; generation holds.
    (: package (-> Builder Target String (List (Pair String String)) ! fs building))
    (define (package builder target directory)
      (when (Target-browser? target)
        (package-browser builder (Target-name target) directory))
      (generation-files directory))

    ;; `work` in a directory of its own in the build's scratch, removed after.
    (: in-working (All (T e) (-> Builder I64 (-> String T ! fs e) T ! fs e)))
    (define (in-working builder node work)
      (let ((working (in-scratch builder (string-append "phase-" (show node)))))
        (make-directories working)
        (let ((result (work working)))
          (remove-tree working)
          result)))

    (: in-scratch (-> Builder String String))
    (define (in-scratch builder name)
      (string-append (Builder-scratch builder) "/" name))

    ;; ---- Programs ----

    ;; The program at `entry`, compiled in this process to one module and
    ;; linked with the runtime into `output`; the files it links ship beside
    ;; it. The compile's own files stay in `working`.
    (: link-program
       (-> Builder String (List String) Inputs String String (List LinkedFile)
           ! mut fs process building))
    (define (link-program builder entry directories inputs working output)
      (let ((program (compiled (lambda ()
                                 (source->wat directories
                                              entry
                                              (lambda (loading forms)
                                                (generated-syntax working
                                                                  directories
                                                                  loading
                                                                  forms))
                                              inputs))))
            (text (string-append working "/program.wat")))
        (write-file text (WholeProgram-text program))
        (link builder text working output)
        (WholeProgram-links program)))

    ;; Each file the program links goes to resources/DIGEST beside it, once
    ;; however many libraries link its bytes, where its host reads it when
    ;; the program first asks for it.
    (: place-links (-> String (List LinkedFile) Unit ! fs building))
    (define (place-links directory links)
      (for-each (lambda (link) (place-link directory link))
                (delete-duplicates (lambda (a b)
                                     (string=? (LinkedFile-digest a) (LinkedFile-digest b)))
                                   links)))

    ;; A file is named for the digest of the bytes its compile read, so the
    ;; bytes placed must be those: a file edited since fails the build, and
    ;; the next one compiles against its new bytes.
    (: place-link (-> String LinkedFile Unit ! fs building))
    (define (place-link directory link)
      (let ((from (LinkedFile-path link))
            (to (string-append directory "/resources/" (LinkedFile-digest link))))
        (unless (kind-is? from (RegularFile))
          (fail-build
           (string-append "cannot place the linked file " from ": there is no file there")))
        (let ((bytes (read-bytes from)))
          (unless (string=? (bytes->hex (sha256 bytes)) (LinkedFile-digest link))
            (fail-build (string-append "the linked file " from " changed during the build")))
          (expect-done (make-directories (directory-part to)) (string-append "cannot make " to))
          (write-bytes to bytes))))

    ;; ---- Development builds ----

    ;; The target compiled in its retained session, or in a new one when
    ;; there is none or its entry or library directories changed; then each
    ;; module written to the generation, assembled again only when the
    ;; session compiled it again. The session the compile left is retained
    ;; with the modules it was assembled into.
    (: develop-program (-> Builder Target String String Progress Program ! mut fs building))
    (define (develop-program builder target directory working progress)
      (let* ((previous (retained-for (Progress-retained progress) target))
             (built (compiled (lambda ()
                                (build-session (Retained-session previous)
                                               (Target-entry target)
                                               (lambda (loading forms)
                                                 (generated-syntax working
                                                                   (Target-directories target)
                                                                   loading
                                                                   forms))
                                               (Progress-inputs progress)))))
             (modules (assemble-modules (Pair-first built) (Retained-modules previous)))
             (links (concatenate (map Built-links (Pair-first built)))))
        (write-modules builder directory modules)
        (place-links directory links)
        (Program (length (filter Built-compiled? (Pair-first built)))
                 (length modules)
                 (map LinkedFile-path links)
                 (Cons (Retained (Target-name target)
                                 (Target-entry target)
                                 (Target-directories target)
                                 (Pair-second built)
                                 modules)
                       (filter
                        (lambda (entry) (not (string=? (Retained-name entry) (Target-name target))))
                        (Progress-retained progress))))))

    (: retained-for (-> (List Retained) Target Retained))
    (define (retained-for retained target)
      (match (find (lambda (entry)
                     (and (string=? (Retained-name entry) (Target-name target))
                          (string=? (Retained-entry entry) (Target-entry target))
                          (same-strings? (Retained-directories entry) (Target-directories target))))
                   retained)
        ((Some entry) entry)
        ((None)
         (Retained (Target-name target)
                   (Target-entry target)
                   (Target-directories target)
                   (make-session (Target-directories target))
                   (Nil)))))

    (: same-strings? (-> (List String) (List String) Bool))
    (define (same-strings? a b)
      (match (Pair a b)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x a-rest) (Cons y b-rest)) (and (string=? x y) (same-strings? a-rest b-rest)))
        (_ #f)))

    ;; Each module as this build has it: as the last build assembled it when
    ;; the session did not compile it again, which keeps its text.
    (: assemble-modules (-> (List Built) (List Assembled) (List Assembled) ! building))
    (define (assemble-modules built previous)
      (map (lambda (module)
             (match (if (Built-compiled? module)
                        (None)
                        (find (lambda (assembled)
                                (string=? (Assembled-library assembled) (Built-name module)))
                              previous))
               ((Some assembled) assembled)
               ((None) (assemble-module module))))
           built))

    (: assemble-module (-> Built Assembled ! building))
    (define (assemble-module module)
      (let ((text (Built-text module)))
        (match (assemble text)
          ((Ok bytes)
           (Assembled (Built-name module)
                      (string-append "modules/" (bytes->hex (sha256 (string->utf8 text))) ".wasm")
                      bytes))
          ((Err message)
           (fail-build (string-append "internal error: cannot assemble the module of "
                                      (Built-name module)
                                      ": "
                                      message))))))

    ;; The modules, modules.json naming them in link order, and the runtime
    ;; they link with as runtime.wasm.
    (: write-modules (-> Builder String (List Assembled) Unit ! fs building))
    (define (write-modules builder directory modules)
      (expect-done (make-directory (string-append directory "/modules"))
                   (string-append "cannot make " directory "/modules"))
      (for-each (lambda (module)
                  (write-bytes (string-append directory "/" (Assembled-file module))
                               (Assembled-bytes module)))
                modules)
      (copy-into (Tools-runtime (Builder-tools builder))
                 (string-append directory "/runtime.wasm")
                 "cannot copy the runtime")
      (write-file (string-append directory "/modules.json") (json->string (manifest modules))))

    (: manifest (-> (List Assembled) Json))
    (define (manifest modules)
      (JsonObject
       (list (Pair "runtime" (JsonString "runtime.wasm"))
             (Pair "modules"
                   (JsonArray (map (lambda (module)
                                     (JsonObject
                                      (list (Pair "name" (JsonString (Assembled-library module)))
                                            (Pair "file" (JsonString (Assembled-file module))))))
                                   modules))))))

    ;; ---- Linking ----

    (: wasm-features (List String))
    (define wasm-features
      (list "--enable-gc" "--enable-reference-types" "--enable-tail-call" "--enable-bulk-memory"
            "--enable-nontrapping-float-to-int" "--enable-sign-ext" "--enable-mutable-globals"))

    ;; Libraries built apart, and plugins loaded at run time, read one
    ;; another's structs and call one another's closures, so neither level
    ;; assumes a closed world. A development build links only its
    ;; producers, as a debug build does.
    (: optimization (-> Mode (List String)))
    (define (optimization mode)
      (match mode
        ((Release) (list "-O3" "--always-inline-max-function-size=40" "--converge"))
        (_ (list "-O1"))))

    ;; The runtime routes its diagnostics through this adapter, which also
    ;; exports the cleanup entry point the host calls.
    (: adapter-text String)
    (define adapter-text
      (string-join
       (list "(module"
             "  (import \"snail.core.support\" \"snail:report-error\" (func $report (param i32 i32)))"
             "  (import \"snail.core.support\" \"snail:io/close-all\" (func $close (result i32)))"
             "  (export \"diagnostics/report-error\" (func $report))"
             "  (export \"close-resources\" (func $close)))"
             "")
       "\n"))

    ;; Assembles the text at `wat`, optimizes it, and merges it with the
    ;; runtime and the adapter into `output`, keeping only the exports a
    ;; host reads. Each intermediate module stays in `working`.
    (: link (-> Builder String String String Unit ! fs process building))
    (define (link builder wat working output)
      (let ((raw (string-append working "/program.raw.wasm"))
            (module (string-append working "/program.module.wasm"))
            (adapter-wat (string-append working "/adapter.wat"))
            (adapter (string-append working "/adapter.wasm"))
            (linked (string-append working "/program.linked.wasm"))
            (mode (optimization (Builder-mode builder))))
        (run-tool "WASM_AS" "wasm-as" (append (Cons "-g" wasm-features) (list wat "-o" raw)))
        (run-tool "WASM_OPT"
                  "wasm-opt"
                  (concatenate (list (Cons "-g" wasm-features) mode (list raw "-o" module))))
        (write-file adapter-wat adapter-text)
        (run-tool "WASM_AS" "wasm-as" (append wasm-features (list adapter-wat "-o" adapter)))
        (run-tool "WASM_MERGE"
                  "wasm-merge"
                  (append (Cons "-g" wasm-features)
                          (list module "snail.abi" (Tools-runtime (Builder-tools builder))
                                "snail.core.support" adapter "snail.platform" "-o" linked)))
        (run-tool "WASM_OPT"
                  "wasm-opt"
                  (concatenate
                   (list (Cons "-g" wasm-features)
                         (list "--remove-exports" "--pass-arg=remove-exports@snail:*,diagnostics/*")
                         mode
                         (list linked "-o" output))))))

    ;; Runs a tool, named by `variable` when it is set.
    (: run-tool (-> String String (List String) Unit ! process building))
    (define (run-tool variable default arguments)
      (let ((program (match (environment-variable variable)
                       ((Some program) program)
                       ((None) default))))
        (run-command (Command program arguments ".") program)))

    ;; Runs a command to its end, and stops the build with what it wrote to
    ;; stderr unless it exits with status 0.
    (: run-command (-> Command String Unit ! process building))
    (define (run-command command name)
      (match (run command #u8())
        ((Err error) (fail-build (string-append "cannot run " name ": " (ProcessError-code error))))
        ((Ok captured)
         (match (Captured-exit captured)
           ((Exited 0) (unit))
           (exit (fail-build (string-append name " failed: " (failure-text captured exit))))))))

    ;; A failed command's stderr, or how it ended when it wrote nothing
    ;; that reads as text.
    (: failure-text (-> Captured Exit String))
    (define (failure-text captured exit)
      (match (utf8->string (Captured-stderr captured))
        ((Ok stderr) (if (string=? stderr "") (how-it-ended exit) stderr))
        ((Err _) (how-it-ended exit))))

    (: how-it-ended (-> Exit String))
    (define (how-it-ended exit)
      (match exit
        ((Exited code) (string-append "exited with " (show code)))
        ((Signaled name) (string-append "ended by " name))))

    ;; ---- Producers ----

    ;; A producer is compiled from the source the planner printed, linked
    ;; for debugging, and run to write its library's syntax, which the
    ;; inputs supply from then on.
    (: produce (-> Builder I64 Producer Inputs Inputs ! mut fs process building))
    (define (produce builder node producer inputs)
      (in-working builder
                  node
                  (lambda (working)
                    (let ((program (string-append working "/producer.wasm"))
                          (output (string-append working "/output.syntax")))
                      (place-links working
                                   (link-program (Builder-mode-set builder (Debug))
                                                 (Producer-source producer)
                                                 (Producer-directories producer)
                                                 inputs
                                                 working
                                                 program))
                      (run-producer builder program output)
                      (supply-producer producer inputs output)))))

    (: run-producer (-> Builder String String Unit ! fs process building))
    (define (run-producer builder program output)
      (let ((tools (Builder-tools builder)))
        (run-command (Command (Tools-node tools)
                              (list "--no-warnings"
                                    (string-append (Tools-root tools) "/host/native/run-snail.mjs")
                                    program
                                    output)
                              ".")
                     "the producer")
        (unless (file-exists? output)
          (fail-build "the producer did not write its generated library"))))

    ;; The producer is read back from its printed source, so the inputs
    ;; hold the text a compile looks its output up by.
    (: supply-producer (-> Producer Inputs String Inputs ! fs building))
    (define (supply-producer producer inputs output)
      (let ((text (compiled (lambda ()
                              (printed-producer-text (Producer-directories producer)
                                                     (Producer-source producer))))))
        (unless (string=? (producer-key text) (Producer-key producer))
          (panic "internal error: a producer's printed text does not have its key"))
        (supply-generated inputs text (read-bytes output))))

    ;; ---- Browser packages ----

    (: browser-files (List String))
    (define browser-files
      (list "host.mjs" "runtime.mjs" "tasks.mjs" "entry.mjs" "renderer.mjs" "hud.mjs" "pictures.mjs"
            "storage.mjs" "load.mjs" "style.css" "ui.mjs" "dom.mjs" "fetch.mjs"))

    ;; The names some build writes at a generation's root, whether or not
    ;; this one does: a release build writes program.wasm, a development
    ;; build modules/, modules.json and runtime.wasm, and a program that
    ;; links files resources/. A public tree may use none of them, so one
    ;; that builds in one mode, or with one set of linked files, builds in
    ;; every other.
    (: generated-names (List String))
    (define generated-names
      (append
       (list "program.wasm" "modules" "modules.json" "runtime.wasm" "resources" ".snail-target")
       browser-files))

    ;; The browser host's files, then the target's public tree, if it has
    ;; one. The page is the project's own index.html; none is generated, but
    ;; a development build's page is told where modules.json is.
    (: package-browser (-> Builder String String Unit ! fs building))
    (define (package-browser builder name directory)
      (copy-browser-host builder name directory)
      (let ((page (string-append directory "/index.html")))
        (when (and (development? builder) (kind-is? page (RegularFile)))
          (write-file page
                      (string-append (read-file page)
                                     "\n<meta name=\"snail-modules\" content=\"./modules.json\">\n")))))

    (: development? (-> Builder Bool))
    (define (development? builder)
      (match (Builder-mode builder)
        ((Development) #t)
        (_ #f)))

    (: copy-browser-host (-> Builder String String Unit ! fs building))
    (define (copy-browser-host builder name directory)
      (for-each (lambda (file)
                  (copy-into
                   (string-append (Tools-root (Builder-tools builder)) "/host/browser/" file)
                   (string-append directory "/" file)
                   (string-append "cannot copy the browser host's " file)))
                browser-files)
      (match (find-target (Project-builds (Builder-description builder)) name)
        ((Some (BrowserTarget browser))
         (match (BrowserBuild-public browser)
           ((Some path) (copy-public (public-directory builder path) directory #t))
           ((None) (unit))))
        (_ (unit))))

    ;; The public directory, which may not be the project's own or lie in
    ;; its build output, and whose every component is a directory, not a
    ;; link.
    (: public-directory (-> Builder ProjectPath String ! fs building))
    (define (public-directory builder path)
      (let ((text (ProjectPath-text path)))
        (when (or (string=? text ".") (string=? (first-component text) "build"))
          (fail-build (string-append "public directory overlaps project build output: " text)))
        (fold-left (lambda (directory part)
                     (let ((next (string-append directory "/" part)))
                       (unless (kind-is? next (Directory))
                         (fail-build (string-append
                                      "public path must contain only directories, not links: "
                                      next)))
                       next))
                   (Builder-project builder)
                   (split-path text))))

    ;; Copies a public tree into the generation. Nothing in it may replace
    ;; a file the build made, use a name reserved at the root, or be
    ;; anything but a regular file or a directory.
    (: copy-public (-> String String Bool Unit ! fs building))
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
    (: prepare-generation (-> Builder String String ! fs clock building))
    (define (prepare-generation builder name)
      (let ((build (string-append (Builder-project builder) "/build")))
        (when (kind-is? build (SymbolicLink))
          (fail-build (string-append "project build directory cannot be a symbolic link: " build)))
        (expect-done (make-directories build) (string-append "cannot make " build))
        (check-output (string-append build "/" name) name)
        (let ((directory (fresh-directory (string-append build "/" (Builder-prefix builder))
                                          (string-append "-" name)
                                          (monotonic-nanoseconds))))
          (write-file (string-append directory "/.snail-target") name)
          directory)))

    ;; A directory `STEM N SUFFIX` that no other build has made, as mkdtemp
    ;; makes one: N starts at `token`, and goes up while the name is taken.
    (: fresh-directory (-> String String I64 String ! fs building))
    (define (fresh-directory stem suffix token)
      (let ((directory (string-append stem (show token) suffix)))
        (match (make-directory directory)
          ((Ok _) directory)
          ((Err (AlreadyExists)) (fresh-directory stem suffix (+ token 1)))
          ((Err error) (fail-build (string-append "cannot make " directory ": " (show error)))))))

    ;; An output is replaced only when it is a link to a generation beside
    ;; it whose marker names the target.
    (: check-output (-> String String Unit ! fs building))
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

    (: unmanaged (All (A) (-> String A ! building)))
    (define (unmanaged output)
      (fail-build (string-append "refusing to replace an unmanaged project output: " output)))

    ;; The files of a completed generation, each relative name with its
    ;; path, in name order, without the root's ownership marker.
    (: generation-files (-> String (List (Pair String String)) ! fs building))
    (define (generation-files directory)
      (list-sort (lambda (a b) (string<? (Pair-first a) (Pair-first b)))
                 (files-under directory "")))

    ;; The digest of each file of a generation but its modules and linked
    ;; files, which are named for theirs, by name.
    (: file-digests (-> (List (Pair String String)) (List (Pair String String)) ! fs))
    (define (file-digests files)
      (map (lambda (file)
             (Pair (Pair-first file) (bytes->hex (sha256 (read-bytes (Pair-second file))))))
           (filter (lambda (file) (not (content-named? (Pair-first file)))) files)))

    (: content-named? (-> String Bool))
    (define (content-named? name)
      (or (starts-with? name "modules/") (starts-with? name "resources/")))

    ;; A digest of a generation's files: each relative name, with its
    ;; file's digest, but only the name of a module or a linked file, which
    ;; is the digest of the text it was assembled from or of its bytes.
    (: generation-digest (-> (List (Pair String String)) (List (Pair String String)) String))
    (define (generation-digest files digests)
      (bytes->hex
       (sha256
        (string->utf8
         (json->string
          (JsonArray (map (lambda (file)
                            (JsonArray (Cons (JsonString (Pair-first file))
                                             (match (assoc-ref digests (Pair-first file))
                                               ((Some digest) (list (JsonString digest)))
                                               ((None) (Nil))))))
                          files)))))))

    (: files-under (-> String String (List (Pair String String)) ! fs building))
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
    (: publish-project (-> Candidate (Result Unit String) ! fs))
    (define (publish-project candidate)
      (let ((outputs (Candidate-outputs candidate)) (project (Candidate-project candidate)))
        (match (attempt
                (lambda () (for-each (lambda (output) (prepare-link project output)) outputs)))
          ((Err failure) (discard outputs) (Err (failure->string failure)))
          ((Ok _) (rename-links project outputs)))))

    ;; Removes a candidate's generations, publishing none of them.
    (: discard-candidate (-> Candidate Unit ! fs))
    (define (discard-candidate candidate)
      (discard (Candidate-outputs candidate)))

    (: prepare-link (-> String Output Unit ! fs building))
    (define (prepare-link project output)
      (let ((directory (Output-directory output)))
        (check-output (output-link project output) (Output-name output))
        (expect-done (make-symbolic-link (base-name directory)
                                         (string-append directory "/.snail-publish"))
                     (string-append "cannot link " directory))))

    (: rename-links (-> String (List Output) (Result Unit String) ! fs))
    (define (rename-links project outputs)
      (match outputs
        ((Nil) (Ok (unit)))
        ((Cons output rest)
         (match (rename-file (string-append (Output-directory output) "/.snail-publish")
                             (output-link project output))
           ((Ok _) (rename-links project rest))
           ((Err error)
            (discard outputs)
            (Err (string-append "cannot publish " (Output-name output) ": " (show error))))))))

    (: output-link (-> String Output String))
    (define (output-link project output)
      (string-append project "/build/" (Output-name output)))

    ;; A removal that fails leaves that generation; the failure the build
    ;; met is the one it reports.
    (: discard (-> (List Output) Unit ! fs))
    (define (discard outputs)
      (for-each (lambda (output)
                  (remove-tree (Output-directory output))
                  (unit))
                outputs))

    ;; ---- Files ----

    ;; The kind of what is at `path`, not following a link, or None when
    ;; nothing is.
    (: status-kind (-> String (Option FileKind) ! fs))
    (define (status-kind path)
      (match (file-status path)
        ((Ok status) (Some (FileStatus-kind status)))
        ((Err _) (None))))

    (: kind-is? (-> String FileKind Bool ! fs))
    (define (kind-is? path kind)
      (match (Pair (status-kind path) kind)
        ((Pair (Some (RegularFile)) (RegularFile)) #t)
        ((Pair (Some (Directory)) (Directory)) #t)
        ((Pair (Some (SymbolicLink)) (SymbolicLink)) #t)
        (_ #f)))

    (: exists? (-> String Bool ! fs))
    (define (exists? path)
      (match (status-kind path)
        ((Some _) #t)
        ((None) #f)))

    (: directory-names (-> String (List String) ! fs building))
    (define (directory-names path)
      (match (list-directory path)
        ((Ok names) names)
        ((Err error) (fail-build (string-append "cannot read directory " path ": " (show error))))))

    ;; Copies a file's bytes to `to`, making its directory first.
    (: copy-into (-> String String String Unit ! fs building))
    (define (copy-into from to failure)
      (unless (kind-is? from (RegularFile))
        (fail-build (string-append failure ": there is no file at " from)))
      (expect-done (make-directories (directory-part to)) failure)
      (write-bytes to (read-bytes from)))

    (: expect-done (All (T) (requires (Copy T)) (-> (Result T FileError) String Unit ! building)))
    (define (expect-done result failure)
      (match result
        ((Ok _) (unit))
        ((Err error) (fail-build (string-append failure ": " (show error))))))

    ;; ---- Text ----

    (: starts-with? (-> String String Bool))
    (define (starts-with? text prefix)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (: split-path (-> String (List String)))
    (define (split-path path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (: first-component (-> String String))
    (define (first-component path)
      (match (string-index path #\/)
        ((Some index) (substring path 0 index))
        ((None) path)))

    (: base-name (-> String String))
    (define (base-name path)
      (match (last (split-path path))
        ((Some name) name)
        ((None) path)))

    ;; The directory that holds `path`, which has at least one slash.
    (: directory-part (-> String String))
    (define (directory-part path)
      (substring path 0 (- (string-length path) (+ (string-length (base-name path)) 1))))

    ))
