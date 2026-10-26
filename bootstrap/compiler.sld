;; A resident compiler's native boundary. JavaScript retains Session values
;; as opaque Any references and receives only parsed records. Input providers
;; load artifact snapshots before expansion. Missing inputs are projected only
;; after the compiler unwinds, before native work starts.
(import
 (lofi base)
 (lofi io)
 (lofi project)
 (lofi compiler)
 (lofi compiler read)
 (lofi compiler inputs)
 (lofi compiler session))

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
  ((output-character (-> Char Unit))
   (output-end (-> Unit))
   (output-program (-> Unit))
   (output-browser (-> Unit))
   (output-run (-> Unit))
   (output-module (-> Bool Unit))
   (output-generate (-> Unit))
   (output-artifact (-> I64 I64 Unit)))
  (host "lofi.compiler"
        ((output-character "character")
         (output-end "end")
         (output-program "program")
         (output-browser "browser")
         (output-run "run")
         (output-module "module")
         (output-generate "generate")
         (output-artifact "artifact"))))

(: send-strings (-> (List String) Unit ! compiler-output))
(define (send-strings strings)
  (for-each (lambda (text) (for-each output-character (string->list text)) (output-end)) strings))

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

(: session! (-> Any ! mut))
(define (session!)
  (type-convert (make-session (take-arguments!)) Any))

(: static! (-> Unit ! mut fs))
(define (static!)
  (match (take-arguments!)
    ((Cons source (Cons output (Cons scratch directories)))
     (write-file output (compile->wat directories source (lambda (forms) (generated-syntax scratch forms)) (load-artifacts scratch))))
    (_ (panic "compiler static: expected source, output, scratch and library directories"))))

(: modules! (-> Any Any ! mut fs compiler-output))
(define (modules! previous)
  (match (take-arguments!)
    ((Cons source (Cons output (Cons scratch (Nil))))
     (let ((built (build-session (type-convert previous Session) source
                                 (lambda (forms) (generated-syntax scratch forms)) (load-artifacts scratch))))
       (for-each (lambda (module) (send-module output module)) (Pair-first built))
       (type-convert (Pair-second built) Any)))
    (_ (panic "compiler modules: expected source, output and scratch directories"))))

(: send-module (-> String Built Unit ! fs compiler-output))
(define (send-module output module)
  (let ((path (string-append output "/" (Built-name module) ".wat")))
    (write-file path (Built-text module))
    (send-strings (list (Built-name module) path))
    (output-module (Built-compiled? module))))

;; ---- Typed input protocol ----

(: reset! (-> Unit ! mut))
(define (reset!)
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

;; Native code supplies fields; Lofi owns the datum grammar and escaping.
;; The manifest belongs to a logical compilation, not the resident instance.
(: add-artifact! (-> Unit ! mut fs))
(define (add-artifact!)
  (match (take-arguments!)
    ((Cons path (Cons name files))
     (let ((replies (read-replies path)))
       (when (any? (lambda (reply) (string=? name (ArtifactReply-name reply))) replies)
         (panic "compiler artifact: already provided"))
       (write-file path (replies->string (Cons (ArtifactReply name (file-pairs files)) replies)))))
    (_ (panic "compiler artifact: expected manifest, name and file pairs"))))

(: file-pairs (-> (List String) (List (Pair String String))))
(define (file-pairs fields)
  (match fields
    ((Nil) (Nil))
    ((Cons relative (Cons path rest)) (Cons (Pair relative path) (file-pairs rest)))
    (_ (panic "compiler artifact: expected relative and backing path pairs"))))

(expose input-character! "input_character")
(expose input-end! "input_end")
(expose project! "project")
(expose session! "session")
(expose static! "static")
(expose modules! "modules")
(expose reset! "reset")
(expose request! "request")
(expose add-artifact! "add_artifact")
