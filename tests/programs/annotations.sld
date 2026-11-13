(import
 (snail core base)
 (snail core io))

;; ANCHOR: annotations
(struct Agent
  ((name String
         (annotations (doc "The agent's display name.")))
   (steps I64
          (annotations (doc "How many operations have completed."))))
  (annotations (doc "An agent's durable state.")))

(define describe-agent
  (→ (Fn Agent → String))
  (annotations (doc "Return the agent's display name.")
               (doc "This does not run an operation."))
  (lambda (agent) (● agent name)))

;; ANCHOR_END: annotations

(type AgentName String (annotations (doc "A human-readable name.")))

(enum Outcome
  (Ready ((agent Agent (annotations (doc "The initialized agent."))))
         (annotations (doc "Initialization succeeded.")))
  (Waiting (annotations (doc "No agent is ready yet.")))
  (annotations (doc "The initialization result.")))

(typeclass (Named T)
  (: name-of (Fn T → String) (annotations (doc "Return this value's name.")))
  (annotations (doc "Values with a human-readable name.")))

(instance (Named Agent)
  (define name-of (lambda (agent) (● agent name))))

(effect information
  ((fetch-name (Fn Unit → String) (annotations (doc "Read the current name.")))
   (ctl await-name (Fn Unit → String) (annotations (doc "Wait for a new name."))))
  (annotations (doc "The source of names.")))

(define constant (→ I64) (annotations (doc "A documented constant.")) 7)

(define-syntax documented-value
  (syntax-rules ()
    ((_ name value)
     (begin
       (define name (→ I64) (annotations (doc "Emitted by a macro.")) value)))))

(documented-value generated 9)

;; Macro arguments remain syntax until a macro emits a declaration slot.
(define-syntax ignore
  (syntax-rules () ((_ any) (unit))))

(define (main) (→ Unit) (! output-port)
  (ignore (annotations (unknown "Not compiler metadata.")))
  (write-line (describe-agent (Agent "Ada" 0)))
  (match (Ready (Agent "Lin" 1))
    ((Ready agent) (write-line (name-of agent)))
    (_ (panic "expected ready")))
  (write-line (show (● (Agent-steps-set (Agent "Ada" 0) 3) steps)))
  (write-line (show (+ constant generated)))
  (unit))
