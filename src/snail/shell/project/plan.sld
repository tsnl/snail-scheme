;; A build's phases, in an order they can run in. A project build compiles
;; targets and runs the producers of generated libraries, and a phase may
;; need others first: a program that imports a generated library needs its
;; producer to have run, and one that embeds a target's files needs that
;; target built. The planner learns those needs before anything runs, from a
;; walk of each program's import closure and a discovery expansion of it,
;; orders the phases so that each follows what it needs, and rejects a
;; cycle. Generated syntax can add needs no plan could see, so a phase whose
;; closure reaches a producer that has not run waits, and the plan is refined
;; when that producer's output arrives. The caller resolves the project's
;; targets; nothing here reads a project.
(define-library (snail shell project plan)
  (export
   Target
   Producer
   Phase
   BuildPhase
   ProducePhase
   Needs
   Known
   Waiting
   Step
   Plan
   plan-build
   refine-plan
   next-phases
   phases-left?)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs)
         Inputs
         producer-text
         producer-key
         generated-output
         print-producer
         generating-stack
         read-source-file)
   (only (snail shell compiler core) strong-components)
   (only (snail shell compiler expand)
         ArtifactUse
         discover-artifacts
         program-imports
         Reached
         library-closure))
  (begin

    ;; ---- Phases ----

    ;; A project build target, as the caller resolved it: its name, whether
    ;; it is a browser build, its entry program's path, the directories its
    ;; libraries are found in, and where it is declared.
    (struct Target
      ((name String)
       (browser? Bool)
       (entry String)
       (directories (List String))
       (loc Loc)))

    ;; A producer to run: the program a `generate-library` recipe makes,
    ;; under the key the build's inputs keep its output by, printed at
    ;; `source`, with the directories its imports resolve in, the libraries
    ;; loading when it was reached, and where its output is placed.
    (struct Producer
      ((key String)
       (library (List String))
       (forms (List Syntax))
       (source String)
       (directories (List String))
       (loading (List String))
       (loc Loc)))

    ;; A phase builds a target, making its files, or runs a producer.
    (enum Phase
      (BuildPhase ((target Target)))
      (ProducePhase ((producer Producer))))

    ;; The nodes a step needs, in the order it first needs them. A step that
    ;; waits knows only the producers its closure reaches so far, and names
    ;; those whose output is missing; what else it needs shows once they
    ;; have run.
    (enum Needs
      (Known ((nodes (List I64))))
      (Waiting
       ((nodes (List I64))
        (producers (List I64)))))

    ;; One node of the plan: its phase, what it needs, and whether a wave
    ;; has handed it to the caller to run.
    (struct Step
      ((phase Phase)
       (needs Needs)
       (emitted Bool)))

    ;; The targets declared, in declaration order; the targets the caller
    ;; asked to build; where producers are printed; a step for each node;
    ;; and the nodes in an order in which each follows what it needs.
    (struct Plan
      ((targets (List Target))
       (roots (List Target))
       (scratch String)
       (steps (Vector Step))
       (order (List I64))))

    ;; A phase's identity: a target is built once, and a producer runs
    ;; once for its key.

    (define (phase-key (phase Phase)) (→ String)
      (match phase
        ((BuildPhase target) (string-append "build " (::name target)))
        ((ProducePhase producer) (string-append "produce " (::key producer)))))

    ;; ---- Planning ----

    ;; The plan for building `roots`, its nodes numbered in depth-first
    ;; pre-order from the roots in order. Each producer is printed into
    ;; `scratch` when it is planned, and compiled from there.

    (define (plan-build (targets (List Target))
                        (roots (List Target))
                        (inputs Inputs)
                        (scratch String))
      (→ Plan)
      (! fs compile)
      (refine-plan (Plan targets roots scratch (list->vector (Nil)) (Nil)) inputs))

    ;; The plan again, once `inputs` supplies more producers' outputs: each
    ;; step that waited learns what it needs now, which may add steps at the
    ;; next nodes, and the order and its cycles are found anew. A step whose
    ;; needs were known keeps them, since its closure waited for nothing.

    (define (refine-plan (plan Plan) (inputs Inputs)) (→ Plan) (! fs compile)
      (let* ((growth
              (fold-left (lambda (growth root) (::second (visit growth (BuildPhase root))))
                         (plan-growth plan inputs)
                         (::roots plan)))
             (steps (::steps growth)))
        (Plan-order-set (Plan-steps-set plan steps) (checked-order (::targets plan) steps))))

    ;; ---- Waves ----

    ;; The phases that can run now, each with its node: the steps of the
    ;; order not yet emitted, up to the first that waits. The plan returned
    ;; counts them emitted. A waiting step's producers come before it, so
    ;; once their outputs refine the plan, the next wave is not empty.

    (define (next-phases (plan Plan)) (→ (Pair (List (Pair I64 Phase)) Plan))
      (let* ((steps (::steps plan)) (ready (ready-nodes steps (::order plan))))
        (Pair (map (lambda (node) (Pair node (::phase (vector-ref steps node)))) ready)
              (Plan-steps-set plan
                              (fold-left (lambda (steps node)
                                           (vector-set steps
                                                       node
                                                       (Step-emitted-set (vector-ref steps node)
                                                                         #t)))
                                         steps ready)))))

    ;; Whether a later wave has phases to hand out, once the producers this
    ;; one ran have refined the plan.

    (define (phases-left? (plan Plan)) (→ Bool)
      (any? (lambda (step) (not (::emitted step))) (vector->list (::steps plan))))

    (define (ready-nodes (steps (Vector Step)) (order (List I64))) (→ (List I64))
      (match order
        ((Nil) (Nil))
        ((Cons node rest)
         (let ((step (vector-ref steps node)))
           (cond ((::emitted step) (ready-nodes steps rest))
                 ((known? (::needs step)) (Cons node (ready-nodes steps rest)))
                 (else (Nil)))))))

    (define (known? (needs Needs)) (→ Bool)
      (match needs
        ((Known _) #t)
        ((Waiting _ _) #f)))

    (define (needs-nodes (needs Needs)) (→ (List I64))
      (match needs
        ((Known nodes) nodes)
        ((Waiting nodes _) nodes)))

    ;; ---- Growing the graph ----

    ;; A plan's graph as it grows: what the build declared and supplied,
    ;; where producers are printed, each phase's node by its identity, a
    ;; step for each node, and the phases this growth has visited.
    (struct Growth
      ((targets (List Target))
       (inputs Inputs)
       (scratch String)
       (nodes (Table I64))
       (steps (Vector Step))
       (visited (Table Bool))))

    (define (plan-growth (plan Plan) (inputs Inputs)) (→ Growth)
      (let ((steps (::steps plan)))
        (Growth (::targets plan) inputs (::scratch plan)
                (fold-left (lambda (nodes node)
                             (table-set nodes
                                        (phase-key (::phase (vector-ref steps node)))
                                        node))
                           empty-table (iota (vector-length steps)))
                steps empty-table)))

    ;; Visits `phase` depth first and returns its node. A phase new to the
    ;; graph takes the next node, so nodes number in pre-order. A new phase,
    ;; or one that waited, learns what it needs now; one whose needs were
    ;; known keeps them, but they are visited, since one of them may wait.

    (define (visit (growth Growth) (phase Phase)) (→ (Pair I64 Growth)) (! fs compile)
      (let ((key (phase-key phase)))
        (match (table-ref (::nodes growth) key)
          ((Some node)
           (if (table-contains? (::visited growth) key)
               (Pair node growth)
               (revisit (mark-visited growth key) node)))
          ((None)
           (learn (add-phase (mark-visited growth key) key phase)
                  (vector-length (::steps growth)))))))

    (define (revisit (growth Growth) (node I64)) (→ (Pair I64 Growth)) (! fs compile)
      (match (::needs (step-at growth node))
        ((Known nodes)
         (Pair node
               (::second
                (visit-all growth (map (lambda (need) (::phase (step-at growth need))) nodes)))))
        ((Waiting _ _) (learn growth node))))

    ;; Finds what the phase at `node` needs, visits those phases, and
    ;; records their nodes as its needs.

    (define (learn (growth Growth) (node I64)) (→ (Pair I64 Growth)) (! fs compile)
      (let* ((demand (phase-demand growth (::phase (step-at growth node))))
             (visited (visit-all growth (::needs demand)))
             (growth (::second visited))
             (missing (map (lambda (phase) (node-of growth phase)) (::missing demand))))
        (Pair node
              (with-needs growth
                          node
                          (if (null? missing)
                              (Known (::first visited))
                              (Waiting (::first visited) missing))))))

    ;; Visits each phase in turn, and returns their nodes in the same order.

    (define (visit-all (growth Growth) (phases (List Phase)))
      (→ (Pair (List I64) Growth))
      (! fs compile)
      (let ((visited (fold-left (lambda (visited phase)
                                  (let ((result (visit (::second visited) phase)))
                                    (Pair (Cons (::first result) (::first visited))
                                          (::second result))))
                                (Pair (Nil) growth) phases)))
        (Pair (reverse (::first visited)) (::second visited))))

    ;; Adds a step for a phase new to the graph, at the next node. A
    ;; producer is printed where it will be compiled from.

    (define (add-phase (growth Growth) (key String) (phase Phase)) (→ Growth) (! fs)
      (match phase
        ((ProducePhase producer)
         (print-producer (::source producer)
                         (::loading producer)
                         (::forms producer)))
        (_ (unit)))
      (Growth-steps-set (Growth-nodes-set growth
                                          (table-set (::nodes growth)
                                                     key
                                                     (vector-length (::steps growth))))
                        (vector-append (::steps growth)
                                       (list->vector (list (Step phase (Known (Nil)) #f))))))

    (define (mark-visited (growth Growth) (key String)) (→ Growth)
      (Growth-visited-set growth (table-set (::visited growth) key #t)))

    (define (step-at (growth Growth) (node I64)) (→ Step)
      (vector-ref (::steps growth) node))

    (define (with-needs (growth Growth) (node I64) (needs Needs)) (→ Growth)
      (Growth-steps-set growth
                        (vector-set (::steps growth)
                                    node
                                    (Step-needs-set (step-at growth node) needs))))

    (define (node-of (growth Growth) (phase Phase)) (→ I64)
      (match (table-ref (::nodes growth) (phase-key phase))
        ((Some node) node)
        ((None) (panic "internal error: a needed phase was not visited"))))

    ;; ---- What a phase needs ----

    ;; What a phase needs, as phases in the order it first needs them, and
    ;; the producers among them whose output is missing.
    (struct Demand
      ((needs (List Phase))
       (missing (List Phase))))

    ;; The producers its program's closure reaches come first. Once they
    ;; have all run, a discovery expansion adds the targets whose files the
    ;; program embeds; until then, those are unknown.

    (define (phase-demand (growth Growth) (phase Phase)) (→ Demand) (! fs compile)
      (let* ((program (phase-program phase)) (producers (reached-producers growth program))
             (missing (filter (lambda (producer) (not (supplied? (::inputs growth) producer)))
                              producers)))
        (if (null? missing)
            (Demand (append (produce-phases producers) (embedded-targets growth program)) (Nil))
            (Demand (produce-phases producers) (produce-phases missing)))))

    (define (produce-phases (producers (List Producer))) (→ (List Phase))
      (map (lambda (producer) (ProducePhase producer)) producers))

    ;; The program a phase compiles: the path it is compiled from, the
    ;; directories its libraries are found in, the libraries loading as it
    ;; starts, and its import specs.
    (struct PhaseProgram
      ((path String)
       (directories (List String))
       (loading (List String))
       (imports (List Syntax))))

    (define (phase-program (phase Phase)) (→ PhaseProgram) (! fs compile)
      (match phase
        ((BuildPhase target) (entry-program target))
        ((ProducePhase producer)
         (PhaseProgram (::source producer)
                       (::directories producer)
                       (::loading producer)
                       (program-imports (::forms producer))))))

    ;; A target's entry, read as `expand-program` reads it.

    (define (entry-program (target Target)) (→ PhaseProgram) (! fs compile)
      (let* ((entry (::entry target))
             (source (generating-stack (read-source-file entry))))
        (PhaseProgram entry
                      (::directories target)
                      (::first source)
                      (program-imports (::second source)))))

    ;; The producers a program's closure reaches, once each, keyed as the
    ;; build's inputs key their outputs.

    (define (reached-producers (growth Growth) (program PhaseProgram))
      (→ (List Producer))
      (! fs compile)
      (let* ((directories (::directories program))
             (reached (library-closure directories
                                       (::inputs growth)
                                       (::loading program)
                                       (::imports program))))
        (delete-duplicates (lambda (a b) (string=? (::key a) (::key b)))
                           (map (lambda (reached)
                                  (reached-producer (::scratch growth) directories reached))
                                reached))))

    (define (reached-producer (scratch String) (directories (List String)) (reached Reached))
      (→ Producer)
      (let ((key (producer-key (producer-text directories (::forms reached)))))
        (Producer key
                  (::library reached)
                  (::forms reached)
                  (string-append scratch "/" key ".sld")
                  directories
                  (::loading reached) (::loc reached))))

    (define (supplied? (inputs Inputs) (producer Producer)) (→ Bool)
      (match (generated-output inputs
                               (producer-text (::directories producer)
                                              (::forms producer)))
        ((Some _) #t)
        ((None) #f)))

    ;; The targets whose files a program embeds, once each, in the order
    ;; discovery first meets them. The project builder resolves each root
    ;; against its declared targets before planning the build.

    (define (embedded-targets (growth Growth) (program PhaseProgram))
      (→ (List Phase))
      (! fs compile)
      (let ((uses (discover-artifacts (::directories program)
                                      (::inputs growth)
                                      (::path program))))
        (map (lambda (use) (BuildPhase (used-target (::targets growth) use)))
             (delete-duplicates
              (lambda (a b) (string=? (::name a) (::name b)))
              uses))))

    ;; A use names a declared browser build.

    (define (used-target (targets (List Target)) (use ArtifactUse)) (→ Target) (! compile)
      (let ((name (::name use)))
        (match (find (lambda (target) (string=? (::name target) name)) targets)
          ((Some target)
           (if (::browser? target)
               target
               (compile-error (::loc use)
                              (string-append "artifact target must be a browser build: " name))))
          ((None)
           (compile-error (::loc use)
                          (string-append "unknown project build target " name))))))

    ;; ---- Order and cycles ----

    ;; The nodes in an order in which each follows what it needs: the
    ;; strongly connected components, each after those it leads to. A
    ;; component of more than one node, or a node that needs itself, is a
    ;; cycle, which no order runs.

    (define (checked-order (targets (List Target)) (steps (Vector Step))) (→ (List I64)) (! compile)
      (let* ((edges (step-edges steps))
             (components (strong-components edges)))
        (for-each (lambda (component)
                    (when (cyclic? edges component) (cycle-error targets steps edges component)))
                  components)
        (concatenate components)))

    ;; Each step's edges, the nodes it needs. A pure helper, as `vector-map`'s
    ;; procedure must be.

    (define (step-edges (steps (Vector Step))) (→ (Vector (List I64)))
      (vector-map (lambda (step) (needs-nodes (::needs step))) steps))

    (define (cyclic? (edges (Vector (List I64))) (component (List I64))) (→ Bool)
      (match component
        ((Cons node (Nil)) (member? node (vector-ref edges node)))
        (_ #t)))

    ;; A cycle through a target names the targets around it, from the one
    ;; declared first, at its declaration, then the producers on the way. A
    ;; cycle of producers alone is an import cycle, reported as the expander
    ;; reports one, at the producer planned first.

    (define (cycle-error (targets (List Target))
                         (steps (Vector Step))
                         (edges (Vector (List I64)))
                         (component (List I64)))
      (→ A)
      (! compile)
      (∀ A)
      (match (first-declared targets steps component)
        ((Some start)
         (let ((path (cycle-path edges component start)))
           (compile-error (::loc (step-built (vector-ref steps start)))
                          (string-append "artifact dependency cycle: "
                                         (string-join (path-targets steps path) " -> ")
                                         (path-producers steps path)))))
        ((None)
         (let ((producer
                (step-producer (vector-ref steps (fold-left min (vector-length steps) component)))))
           (compile-error (::loc producer)
                          (string-append "library import cycle through "
                                         (string-join (::library producer) ".")))))))

    ;; The member of `component` that builds the target declared first, if
    ;; any member builds one.

    (define (first-declared (targets (List Target)) (steps (Vector Step)) (component (List I64)))
      (→ (Option I64))
      (match (find (lambda (target)
                     (any? (lambda (node) (builds? (vector-ref steps node) target)) component))
                   targets)
        ((Some target) (find (lambda (node) (builds? (vector-ref steps node) target)) component))
        ((None) (None))))

    (define (builds? (step Step) (target Target)) (→ Bool)
      (match (step-target step)
        ((Some built) (string=? (::name built) (::name target)))
        ((None) #f)))

    (define (step-target (step Step)) (→ (Option Target))
      (match (::phase step)
        ((BuildPhase target) (Some target))
        ((ProducePhase _) (None))))

    (define (step-built (step Step)) (→ Target)
      (match (::phase step)
        ((BuildPhase target) target)
        (_ (panic "internal error: not a build"))))

    (define (step-producer (step Step)) (→ Producer)
      (match (::phase step)
        ((ProducePhase producer) producer)
        (_ (panic "internal error: not a producer"))))

    ;; The way around the cycle from `start` back to it, through members of
    ;; `component`, following each node's needs in order.

    (define (cycle-path (edges (Vector (List I64))) (component (List I64)) (start I64))
      (→ (List I64))
      (match (path-back edges component start (list start))
        ((Some path) path)
        ((None) (panic "internal error: a cycle with no way back"))))

    ;; `path` holds the nodes so far, latest first.

    (define (path-back (edges (Vector (List I64)))
                       (component (List I64))
                       (start I64)
                       (path (List I64)))
      (→ (Option (List I64)))
      (let ((needs (match path
                     ((Cons node _) (vector-ref edges node))
                     ((Nil) (Nil)))))
        (if (member? start needs)
            (Some (reverse (Cons start path)))
            (fold-left (lambda (found next)
                         (match found
                           ((Some _) found)
                           ((None)
                            (if (and (member? next component) (not (member? next path)))
                                (path-back edges component start (Cons next path))
                                (None)))))
                       (None) needs))))

    (define (path-targets (steps (Vector Step)) (path (List I64))) (→ (List String))
      (concatenate (map (lambda (node)
                          (match (step-target (vector-ref steps node))
                            ((Some target) (list (::name target)))
                            ((None) (Nil))))
                        path)))

    ;; " through the producer of (generated assets)", naming each producer
    ;; on the path, or nothing.

    (define (path-producers (steps (Vector Step)) (path (List I64))) (→ String)
      (let ((producers (concatenate (map (lambda (node)
                                           (match (::phase (vector-ref steps node))
                                             ((ProducePhase producer)
                                              (list (string-append "the producer of ("
                                                                   (string-join
                                                                    (::library producer)
                                                                    " ")
                                                                   ")")))
                                             (_ (Nil))))
                                         path))))
        (if (null? producers) "" (string-append " through " (string-join producers ", ")))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-plan)
    (import
     (only (scheme base) error)
     (only (chibi filesystem) create-directory*)
     (only (chibi string) string-contains string-split)
     (snail stage0 testing)
     (only (snail shell compiler inputs) no-inputs supply-generated printed-producer-text))
    (begin

      ;; A server whose producer embeds client, and whose generated syntax
      ;; embeds admin, is planned in waves: client and the producer first,
      ;; then, once the producer's output refines the plan, admin and
      ;; server. Several roots share one graph, so a root the producer
      ;; embeds is built once. Cycles through targets and through producers
      ;; fail with the texts the native builder and the expander use. Sources are
      ;; written into `directory`; `library` holds the standard libraries.
      (define test-plan
        (lambda (directory library) (let ((targets (project-targets directory library))
                                          (scratch (string-append directory "/scratch")))
                                      (write-project directory)
                                      (create-directory* scratch)
                                      (test-waves targets scratch)
                                      (test-roots targets scratch)
                                      (test-cycles directory targets scratch))))

      (define test-waves
        (lambda (targets scratch) (let* ((server (list-ref targets 2))
                                         (cold (plan-build targets (list server) no-inputs scratch))
                                         (wave (next-phases cold))
                                         (producer (wave-producer (::first wave)))
                                         (output (generated-library-bytes assets-output))
                                         (warm (refine-plan (::second wave)
                                                            (supply-generated no-inputs
                                                                              (printed-producer-text
                                                                               (::directories
                                                                                server)
                                                                               (::source producer))
                                                                              output)))
                                         (next (next-phases warm)))
                                    (expect (step-names cold)
                                            (list "build server"
                                                  "produce generated.assets"
                                                  "build client"))
                                    (expect (::needs (vector-ref (::steps cold) 0))
                                            (Waiting (list 1) (list 1)))
                                    (expect (::order cold) (list 2 1 0))
                                    (expect (wave-names (::first wave))
                                            (list "build client" "produce generated.assets"))
                                    (expect (phases-left? (::second wave)) #t)
                                    (expect (first-line (read-file (::source producer)))
                                            "(generating \"generated.assets\")")
                                    (expect (step-names warm)
                                            (list "build server"
                                                  "produce generated.assets"
                                                  "build client"
                                                  "build admin"))
                                    (expect (::needs (vector-ref (::steps warm) 0))
                                            (Known (list 1 3 2)))
                                    (expect (::order warm) (list 2 1 3 0))
                                    (expect (wave-names (::first next))
                                            (list "build admin" "build server"))
                                    (expect (phases-left? (::second next)) #f)
                                    (expect (::first (next-phases (::second next))) (list)))))

      (define test-roots
        (lambda (targets scratch)
          (let ((plan (plan-build targets (take targets 3) no-inputs scratch)))
            (expect (step-names plan)
                    (list "build client" "build admin" "build server" "produce generated.assets"))
            (expect (wave-names (::first (next-phases plan)))
                    (list "build client" "build admin" "produce generated.assets")))))

      (define test-cycles
        (lambda (directory targets scratch)
          (let ((client (list (list-ref targets 0))) (server (list (list-ref targets 2))))
            (write-file (string-append directory "/client.sld") (embedding "client"))
            (expect (plan-error targets client scratch)
                    "project.datum:2:2: artifact dependency cycle: client -> client")
            (write-file (string-append directory "/client.sld") (embedding "admin"))
            (write-file (string-append directory "/admin.sld")
                        "(import (snail core base) (generated assets)) (unit)")
            (expect (plan-error targets client scratch)
                    "project.datum:2:2: artifact dependency cycle: client -> admin -> client through the producer of (generated assets)")
            (write-file (string-append directory "/server.sld") (embedding "missing"))
            (expect (located? (plan-error targets server scratch)
                              "server.sld:2:"
                              "unknown project build target missing")
                    #t)
            (write-file (string-append directory "/server.sld") (embedding "server"))
            (expect (located? (plan-error targets server scratch)
                              "server.sld:2:"
                              "artifact target must be a browser build: server")
                    #t)
            (expect (located? (plan-error targets (list (list-ref targets 3)) scratch)
                              "knot-helper.sld:1:"
                              "library import cycle through sample.knot")
                    #t))))

      (define plan-error
        (lambda (targets roots scratch)
          (or (compile-failure (lambda () (plan-build targets roots no-inputs scratch)))
              "planned")))

      (define first-line
        (lambda (text) (list-ref (string-split text #\newline) 0)))

      (define located?
        (lambda (message place text)
          (and (string-contains message place) (string-contains message text) #t)))

      (define embedding
        (lambda (name)
          (string-append "(import (snail core base) (snail shell artifact))\n(artifact-bundle \""
                         name
                         "\")\n")))

      (define step-names
        (lambda (plan)
          (map (lambda (step) (phase-name (::phase step))) (vector->list (::steps plan)))))

      (define wave-names
        (lambda (wave) (map (lambda (entry) (phase-name (::second entry))) wave)))

      (define phase-name
        (lambda (phase) (match phase
                          ((BuildPhase target) (string-append "build " (::name target)))
                          ((ProducePhase producer)
                           (string-append "produce " (string-join (::library producer) "."))))))

      (define wave-producer
        (lambda (wave)
          (match (find (lambda (entry) (match (::second entry) ((ProducePhase _) #t) (_ #f))) wave)
            ((Some (Pair _ (ProducePhase producer))) producer)
            (_ (error "no producer in the wave")))))

      (define project-targets
        (lambda (directory library)
          (let ((directories (list (string-append directory "/lib") library)))
            (map-indexed (lambda (index entry)
                           (Target (::first entry)
                                   (::second entry)
                                   (string-append directory "/" (::first entry) ".sld")
                                   directories
                                   (Loc "project.datum" (+ index 2) 2)))
                         (list (Pair "client" #t)
                               (Pair "admin" #t)
                               (Pair "server" #f)
                               (Pair "knot" #f))))))

      (define assets-output
        (string-append
         "(define-library (generated assets) (export admin-bundle) (import (snail core base) (snail shell artifact)) "
         "(begin (: admin-bundle ArtifactBundle) (define admin-bundle (artifact-bundle \"admin\"))))"))

      (define write-project
        (lambda (directory) (create-directory* (string-append directory "/lib/generated"))
                (create-directory* (string-append directory "/lib/sample"))
                (for-each (lambda (source)
                            (write-file (string-append directory "/" (::first source))
                                        (::second source)))
                          (list (Pair "client.sld" "(import (snail core base)) (unit)")
                                (Pair "admin.sld" "(import (snail core base)) (unit)")
                                (Pair "server.sld" server-source)
                                (Pair "knot.sld" "(import (sample knot)) (unit)")
                                (Pair "lib/generated/assets.sld" assets-recipe)
                                (Pair "lib/sample/knot.sld"
                                      "(generate-library (sample knot) (import (snail core base) (sample knot-helper)) (unit))")
                                (Pair "lib/sample/knot-helper.sld"
                                      "(define-library (sample knot-helper) (export) (import (sample knot)) (begin))")))))

      (define assets-recipe
        (string-append
         "(generate-library (generated assets) (import (snail core base) (snail shell artifact) (snail shell syntax))\n"
         "  (let ((client (artifact-bundle \"client\"))) (StringSyntax \"unused\")))\n"))

      (define server-source
        (string-append
         "(import (snail core base) (rename (snail shell artifact) (artifact-bundle bundle)) (generated assets))\n"
         "(define-syntax client-snapshot (syntax-rules () ((_) (bundle \"client\"))))\n"
         "(define-syntax unused (syntax-rules () ((_) (bundle \"does-not-exist\"))))\n"
         "(define snapshot (client-snapshot))\n"))))
   (else)))
