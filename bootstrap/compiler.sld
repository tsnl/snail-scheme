;; A resident compiler's native boundary. JavaScript retains Session values
;; and immutable artifact inputs as opaque typed references. It receives only
;; parsed records. Missing inputs are projected only
;; after the compiler unwinds, before native work starts.
(import
 (lofi base)
 (lofi io)
 (lofi table)
 (lofi project)
 (lofi compiler)
 (lofi compiler read)
 (lofi compiler inputs)
 (lofi compiler session)
 (only (lofi compiler expand) ArtifactInputs))

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
   (output-diagnostic (-> I64 I64 Unit)))
  (host "lofi.compiler"
        ((output-text "text")
         (output-program "program")
         (output-browser "browser")
         (output-run "run")
         (output-module "module")
         (output-generate "generate")
         (output-artifact "artifact")
         (output-diagnostic "diagnostic"))))

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

;; ---- Compiler entries ----

(: session! (-> Session ! mut))
(define (session!)
  (make-session (take-arguments!)))

(: static! (-> ArtifactInputs Unit ! mut fs))
(define (static! inputs)
  (match (take-arguments!)
    ((Cons source (Cons output (Cons scratch directories)))
     (write-file output (compile->wat directories source (lambda (forms) (generated-syntax scratch forms)) inputs)))
    (_ (panic "compiler static: expected source, output, scratch and library directories"))))

(: check! (-> ArtifactInputs Unit ! mut fs))
(define (check! inputs)
  (match (take-arguments!)
    ((Cons source (Cons scratch directories))
     (check-source directories source (lambda (forms) (generated-syntax scratch forms)) inputs))
    (_ (panic "compiler check: expected source, scratch and library directories"))))

(: modules! (-> Session ArtifactInputs Session ! mut fs compiler-output))
(define (modules! previous inputs)
  (match (take-arguments!)
    ((Cons source (Cons scratch (Nil)))
     (let ((built (build-session previous source (lambda (forms) (generated-syntax scratch forms)) inputs)))
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

;; ---- Immutable artifact inputs ----

(: inputs (-> ArtifactInputs))
(define (inputs)
  no-artifacts)

;; The caller owns a canonical ordered inventory of completed output files.
;; Read them once; only a successful call exposes the replacement table.
(: add-artifact! (-> ArtifactInputs ArtifactInputs ! mut fs))
(define (add-artifact! previous)
  (match (take-arguments!)
    ((Cons name files)
     (match (table-ref previous name)
       ((Some _) (panic "compiler artifact: already provided"))
       ((None) (table-set previous name (snapshot-files files)))))
    (_ (panic "compiler artifact: expected name and file pairs"))))

(: snapshot-files (-> (List String) (List (Pair String Bytes)) ! fs))
(define (snapshot-files fields)
  (match fields
    ((Nil) (Nil))
    ((Cons relative (Cons path rest))
     (let ((bytes (read-bytes path)))
       (Cons (Pair relative bytes) (snapshot-files rest))))
    (_ (panic "compiler artifact: expected relative and backing path pairs"))))

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
