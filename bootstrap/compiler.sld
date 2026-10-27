;; A resident compiler's native boundary. JavaScript retains Session values,
;; build plans and immutable build inputs as opaque typed references. It
;; receives only parsed records: a project's targets, a plan's phases, a
;; compile's modules. A compile the plan supplied needs no input it lacks;
;; one that asks anyway is projected only after the compiler unwinds.
(import
 (snail-core base)
 (snail-core io)
 (snail-core table)
 (snail-core project)
 (snail-core compiler)
 (snail-core compiler read)
 (snail-core compiler inputs)
 (snail-core compiler session)
 (snail-core compiler plan))

;; ---- Arguments and records ----

(: characters (Ref (List Char)))
(define characters (ref (Nil)))
(: arguments (Ref (List String)))
(define arguments (ref (Nil)))

(: input-character! (-> Char Unit ! mut))
(define (input-character! character)
  (ref-set! characters (Cons character (ref-get characters))))

(: input-end! (-> Unit ! mut))
(define (input-end!)
  (ref-set! arguments (Cons (list->string (reverse (ref-get characters))) (ref-get arguments)))
  (ref-set! characters (Nil)))

(: take-arguments! (-> (List String) ! mut))
(define (take-arguments!)
  (let ((taken (reverse (ref-get arguments))))
    (ref-set! arguments (Nil))
    (ref-set! characters (Nil))
    taken))

;; Only projection performs this effect. It never enters compiler callbacks.
(effect compiler-output
  ((output-text (-> I32 String Unit))
   (output-program (-> Unit))
   (output-browser (-> Unit))
   (output-run (-> Unit))
   (output-module (-> Bool Unit))
   (output-generate (-> Unit))
   (output-artifact (-> I64 I64 Unit))
   (output-diagnostic (-> I64 I64 Unit))
   (output-produce (-> I64 I64 Unit))
   (output-build (-> I64 I64 Unit))
   (output-check (-> I64 I64 Unit))
   (output-waiting (-> Unit)))
  (host "snail-core.compiler"
        ((output-text "text")
         (output-program "program")
         (output-browser "browser")
         (output-run "run")
         (output-module "module")
         (output-generate "generate")
         (output-artifact "artifact")
         (output-diagnostic "diagnostic")
         (output-produce "produce")
         (output-build "build")
         (output-check "check")
         (output-waiting "waiting"))))

;; Reserve before the String argument is staged. Staging that same scalar
;; count cannot grow or move the buffer, so the pointer reaches the leaf host
;; import with its text. The host copies it before another call can stage.
(extern stage-text "snail.library" "snail:io/stage" (-> I32 I32))

(: send-strings (-> (List String) Unit ! compiler-output))
(define (send-strings strings)
  (for-each (lambda (text) (output-text (stage-text (i64->i32 (string-length text))) text)) strings))

;; ---- Source failures ----

;; The host calls this directly after a trusted terminal exit, before another
;; invocation can reset the record. File cleanup does not invalidate WasmGC
;; values. This emits no record for an IO failure or an input request.
(: diagnostic! (-> Unit ! mut compiler-output))
(define (diagnostic!)
  (match (take-compile-error!)
    ((Some diagnostic)
     (let ((loc (SourceDiagnostic-loc diagnostic)))
       (send-strings (list (SourceDiagnostic-message diagnostic) (Loc-file loc)))
       (output-diagnostic (Loc-line loc) (Loc-column loc))))
    ((None) (unit))))

;; ---- Parsed projects ----

(: project! (-> Unit ! mut fs compiler-output))
(define (project!)
  (match (take-arguments!)
    ((Cons path (Nil))
     (let ((project (parse-project (read-file path) path)))
       (for-each send-build (Project-builds project))
       (for-each send-run (Project-runs project))))
    (_ (panic "compiler project: expected one filename"))))

(: send-build (-> BuildTarget Unit ! compiler-output))
(define (send-build target)
  (match target
    ((ProgramTarget program)
     (send-strings (append (list (ProgramBuild-name program) (ProjectPath-text (ProgramBuild-entry program))
                                 (loc->string (ProgramBuild-loc program)))
                           (map ProjectPath-text (ProgramBuild-libraries program))))
     (output-program))
    ((BrowserTarget browser)
     (send-strings (append (list (BrowserBuild-name browser) (ProjectPath-text (BrowserBuild-entry browser))
                                 (loc->string (BrowserBuild-loc browser))
                                 (match (BrowserBuild-public browser) ((Some path) (ProjectPath-text path)) ((None) "")))
                           (map ProjectPath-text (BrowserBuild-libraries browser))))
     (output-browser))))

(: send-run (-> RunTarget Unit ! compiler-output))
(define (send-run run)
  (send-strings (append (list (RunTarget-name run) (ProgramBuild-name (RunTarget-program run))
                              (loc->string (RunTarget-loc run))) (RunTarget-arguments run)))
  (output-run))

;; ---- Build plans ----

;; A project's build targets as the planner takes them, in declaration
;; order: each entry and library root found in the project's `directory`,
;; and the standard libraries' directory after the roots. The host compiles
;; every phase with the directories its record names, so a producer's key,
;; which covers them, is the same in the plan and in the compile.
(: plan-targets (-> String String Project (List Target)))
(define (plan-targets directory standard project)
  (map (lambda (target)
         (match target
           ((ProgramTarget program)
            (Target (ProgramBuild-name program) #f (in-project directory (ProgramBuild-entry program))
                    (library-directories directory standard (ProgramBuild-libraries program))))
           ((BrowserTarget browser)
            (Target (BrowserBuild-name browser) #t (in-project directory (BrowserBuild-entry browser))
                    (library-directories directory standard (BrowserBuild-libraries browser))))))
       (Project-builds project)))

(: in-project (-> String ProjectPath String))
(define (in-project directory path)
  (if (string=? (ProjectPath-text path) ".") directory (string-append directory "/" (ProjectPath-text path))))

(: library-directories (-> String String (List ProjectPath) (List String)))
(define (library-directories directory standard roots)
  (append (map (lambda (root) (in-project directory root)) roots) (list standard)))

;; A root the build asks for by name, to be built or only checked.
(: root-phase (-> (List Target) String Bool String Phase))
(define (root-phase targets file check? name)
  (match (find (lambda (target) (string=? (Target-name target) name)) targets)
    ((Some target) (if check? (CheckPhase target) (BuildPhase target)))
    ((None) (panic (string-append "unknown project build target " name " in " file)))))

;; Plans the build of the project in a directory: its arguments are that
;; directory, the standard libraries' directory, the scratch directory
;; producers are printed into, `build` or `check`, and the roots' names.
;; Sends the first wave of phases and returns the plan.
(: plan! (-> Inputs Plan ! mut fs compiler-output))
(define (plan! inputs)
  (match (take-arguments!)
    ((Cons directory (Cons standard (Cons scratch (Cons mode names))))
     (let* ((file (string-append directory "/project.datum"))
            (targets (plan-targets directory standard (parse-project (read-file file) file))))
       (send-wave (plan-build targets (map (lambda (name) (root-phase targets file (string=? mode "check") name)) names)
                              inputs scratch))))
    (_ (panic "compiler plan: expected project and standard directories, scratch, mode and root names"))))

;; The plan again, now that `inputs` holds the outputs of the producers the
;; waiting phases waited for. Sends the next wave.
(: refine! (-> Plan Inputs Plan ! mut fs compiler-output))
(define (refine! plan inputs)
  (send-wave (refine-plan plan inputs)))

;; Sends the phases that can run now, in the order they run, then
;; `waiting` if any phase is left for a later wave, and returns the plan
;; that counts them handed out.
(: send-wave (-> Plan Plan ! compiler-output))
(define (send-wave plan)
  (let* ((wave (next-phases plan)) (next (Pair-second wave)))
    (for-each (lambda (entry) (send-phase next (Pair-first entry) (Pair-second entry))) (Pair-first wave))
    (when (phases-left? next) (output-waiting))
    next))

;; A phase's record: its node, the producer's key and printed source or the
;; target's name and entry, its library directories, counted, and then the
;; names of the targets whose files it embeds.
(: send-phase (-> Plan I64 Phase Unit ! compiler-output))
(define (send-phase plan node phase)
  (let ((embeds (embedded-names plan node)))
    (match phase
      ((ProducePhase producer)
       (send-strings (Cons (Producer-key producer) (Cons (Producer-source producer) (append (Producer-directories producer) embeds))))
       (output-produce node (length (Producer-directories producer))))
      ((BuildPhase target) (send-target target embeds) (output-build node (length (Target-directories target))))
      ((CheckPhase target) (send-target target embeds) (output-check node (length (Target-directories target)))))))

(: send-target (-> Target (List String) Unit ! compiler-output))
(define (send-target target embeds)
  (send-strings (Cons (Target-name target) (Cons (Target-entry target) (append (Target-directories target) embeds)))))

;; The targets whose files the phase at `node` embeds: the builds among
;; its needs, which are known by the time a wave hands it out. Each was
;; built in an earlier wave, or earlier in this one.
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

;; ---- Compiler entries ----

(: session! (-> Session ! mut))
(define (session!)
  (make-session (take-arguments!)))

(: static! (-> Inputs Unit ! mut fs))
(define (static! inputs)
  (match (take-arguments!)
    ((Cons source (Cons output (Cons scratch directories)))
     (write-file output (source->wat directories source (lambda (loading forms) (generated-syntax scratch directories loading forms)) inputs)))
    (_ (panic "compiler static: expected source, output, scratch and library directories"))))

(: check! (-> Inputs Unit ! mut fs))
(define (check! inputs)
  (match (take-arguments!)
    ((Cons source (Cons scratch directories))
     (check-source directories source (lambda (loading forms) (generated-syntax scratch directories loading forms)) inputs))
    (_ (panic "compiler check: expected source, scratch and library directories"))))

(: modules! (-> Session Inputs Session ! mut fs compiler-output))
(define (modules! previous inputs)
  (match (take-arguments!)
    ((Cons source (Cons scratch (Nil)))
     (let* ((directories (Session-directories previous))
            (built (build-session previous source (lambda (loading forms) (generated-syntax scratch directories loading forms)) inputs)))
       (for-each send-module (Pair-first built))
       (Pair-second built)))
    (_ (panic "compiler modules: expected source and scratch directory"))))

(: send-module (-> Built Unit ! compiler-output))
(define (send-module module)
  (send-strings (list (Built-name module) (Built-text module)))
  (output-module (Built-compiled? module)))

;; ---- Typed input protocol ----

(: reset! (-> Unit ! mut))
(define (reset!)
  (clear-compile-error!)
  (take-input-request!)
  (unit))

(: request! (-> Unit ! mut compiler-output))
(define (request!)
  (match (take-input-request!)
    ((Some (GenerateInput key)) (send-strings (list key)) (output-generate))
    ((Some (ArtifactInput name loc))
     (send-strings (list name (Loc-file loc)))
     (output-artifact (Loc-line loc) (Loc-column loc)))
    ((None) (unit))))

;; ---- Immutable build inputs ----

(: inputs (-> Inputs))
(define (inputs)
  no-inputs)

;; The caller owns a canonical ordered inventory of completed output files.
;; Read them once; only a successful call exposes the replacement inputs.
(: add-artifact! (-> Inputs Inputs ! mut fs))
(define (add-artifact! previous)
  (match (take-arguments!)
    ((Cons name files)
     (match (table-ref (Inputs-artifacts previous) name)
       ((Some _) (panic "compiler artifact: already provided"))
       ((None) (supply-artifact previous name (snapshot-files files)))))
    (_ (panic "compiler artifact: expected name and file pairs"))))

(: snapshot-files (-> (List String) (List (Pair String Bytes)) ! fs))
(define (snapshot-files fields)
  (match fields
    ((Nil) (Nil))
    ((Cons relative (Cons path rest))
     (let ((bytes (read-bytes path)))
       (Cons (Pair relative bytes) (snapshot-files rest))))
    (_ (panic "compiler artifact: expected relative and backing path pairs"))))

;; What the producer printed at `source` wrote to `output`, when its imports
;; resolve in the library directories after them. The producer is read back
;; from its printed source, so the entry holds the text a compile looks it
;; up by, and `key` must be the key it was printed under.
(: add-generated! (-> Inputs Inputs ! mut fs))
(define (add-generated! previous)
  (match (take-arguments!)
    ((Cons key (Cons source (Cons output directories)))
     (let ((text (printed-producer-text directories source)))
       (unless (string=? (producer-key text) key) (panic "compiler generated: the key does not name this producer"))
       (match (generated-output previous text)
         ((Some _) (panic "compiler generated: already provided"))
         ((None) (supply-generated previous text (read-bytes output))))))
    (_ (panic "compiler generated: expected key, source, output and library directories"))))

(expose diagnostic! "diagnostic")
(expose input-character! "input_character")
(expose input-end! "input_end")
(expose project! "project")
(expose session! "session")
(expose static! "static")
(expose check! "check")
(expose modules! "modules")
(expose reset! "reset")
(expose request! "request")
(expose inputs "inputs")
(expose add-artifact! "add_artifact")
(expose add-generated! "add_generated")
(expose plan! "plan")
(expose refine! "refine")
