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

(: describe-agent (dyn (Fn Agent -> String))
   (annotations (doc "Return the agent's display name.")
                (doc "This does not run an operation.")))
(define (describe-agent agent)
  (::name agent))
;; ANCHOR_END: annotations

(type AgentName String (annotations (doc "A human-readable name.")))
(enum Outcome
  (Ready ((agent Agent (annotations (doc "The initialized agent."))))
         (annotations (doc "Initialization succeeded.")))
  (Waiting (annotations (doc "No agent is ready yet.")))
  (annotations (doc "The initialization result.")))

(typeclass (Named T)
  (: name-of (dyn (Fn T -> String)) (annotations (doc "Return this value's name.")))
  (annotations (doc "Values with a human-readable name.")))
(instance (Named Agent)
  (define (name-of agent) (::name agent)))

(effect information
  ((fetch-name (dyn (Fn Unit -> String)) (annotations (doc "Read the current name.")))
   (ctl await-name (dyn (Fn Unit -> String)) (annotations (doc "Wait for a new name."))))
  (annotations (doc "The source of names.")))

(: constant I64 (annotations (doc "A documented constant.")))
(define constant 7)
(define-syntax documented-value
  (syntax-rules ()
    ((_ name value)
     (begin
       (: name I64 (annotations (doc "Emitted by a macro.")))
       (define name value)))))
(documented-value generated 9)

;; Macro arguments remain syntax until a macro emits a declaration slot.
(define-syntax ignore
  (syntax-rules () ((_ any) (unit))))
(ignore (annotations (unknown "Not compiler metadata.")))

(write-line (describe-agent (Agent "Ada" 0)))
(write-line (name-of (Ready-agent (Ready (Agent "Lin" 1)))))
(write-line (show (::steps (Agent-steps-set (Agent "Ada" 0) 3))))
(write-line (show (+ constant generated)))
