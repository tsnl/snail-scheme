;; Typed applications are ordinary libraries. A declaration generates lexical
;; command constructors and private reducers, never a user-maintained enum.
(define-library (application reducer)
  (export application Application application-initial application-schema dispatch dispatch-wire
          Request request-slot request-a request-b Transition transition transition-state
          transition-effects no-effects Destination destination Effect enqueue notice effect-owner effect-slot
          effect-a effect-b effect-text effect-send? effect-notice? effect-kind match-owner client-owner)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) datatype match ann -> I32 library-begin)
   (only (lofi base) unreachable)
   (rename (only (lofi core) def) (def define-typed)))
  (begin

    ;; ---- Values crossing one committed transition ----

    (define Request
      (datatype (Owner State)
        (request
         (slot I32 request-slot)
         (a I32 request-a)
         (b I32 request-b))))
    (define Effect
      (datatype ()
        (send
         (owner I32 effect-owner)
         (slot I32 effect-slot)
         (a I32 effect-a)
         (b I32 effect-b))
        (notice
         (text String effect-text))))
    (define Transition
      (datatype (State)
        (transition
         (state State transition-state)
         (effects (List Effect) transition-effects))))
    (define Application
      (datatype (Owner State)
        (application-value
         (schema I32 application-schema)
         (initial (-> State) application-initial)
         (handlers (List (-> State I32 I32 (Transition State))) application-handlers))))
    (define Destination
      (datatype (Owner State)
        (destination
         (owner I32 destination-owner)
         (app (Application Owner State) destination-app))))
    (define match-owner 1)
    (define client-owner 2)
    (define (no-effects state) (transition state (empty-list)))
    (define (effect-send? effect)
      (match effect ((send owner slot a b) #t) ((notice text) #f)))
    (define (effect-notice? effect) (not (effect-send? effect)))
    ;; Numeric kinds belong to the private scalar bridge, not application tests.
    (define (effect-kind effect)
      (if (effect-send? effect) 1 2))
    (define (dispatch-wire app state slot a b) (dispatch app state (request slot a b)))
    (define-typed enqueue
      (All (Owner State) (-> (Destination Owner State) (Request Owner State) Effect))
      (lambda (target command)
        (send (destination-owner target) (request-slot command) (request-a command) (request-b command))))
    (define (select-handler handlers slot)
      (if (or (< slot 0) (null? handlers)) (unreachable)
          (if (= slot 0) (car handlers) (select-handler (cdr handlers) (- slot 1)))))
    (define-typed dispatch
      (All (Owner State) (-> (Application Owner State) State (Request Owner State) (Transition State)))
      (lambda (app state command)
        ((select-handler (application-handlers app) (request-slot command))
         state (request-a command) (request-b command))))

    ;; ---- Declaration expansion: all handlers share State ----

    ;; Initial payload vocabulary is zero, one or two I32 arguments. Wire slots
    ;; are generated here; the build pairs them with stable versioned identities.
    ;; Caller annotations check payloads; reducer annotations check state/result.
    (define-syntax command-constructor
      (syntax-rules ()
        ((_ Owner State slot ()) (ann (lambda () (request slot 0 0)) (-> (Request Owner State))))
        ((_ Owner State slot ((a A))) (ann (lambda (a) (request slot a 0)) (-> A (Request Owner State))))
        ((_ Owner State slot ((a A) (b B)))
         (ann (lambda (a b) (request slot a b)) (-> A B (Request Owner State))))))
    (define-syntax private-handler
      (syntax-rules ()
        ((_ State (state) body ...)
         (ann (lambda (state unused-a unused-b) body ...)
              (-> State I32 I32 (Transition State))))
        ((_ State (state (a A)) body ...)
         (ann (lambda (state a unused-b)
                ((ann (lambda (state a) body ...) (-> State A (Transition State))) state a))
              (-> State I32 I32 (Transition State))))
        ((_ State (state (a A) (b B)) body ...)
         (ann (lambda (state a b)
                ((ann (lambda (state a b) body ...) (-> State A B (Transition State))) state a b))
              (-> State I32 I32 (Transition State))))))
    (define-syntax application-handlers-declare
      (syntax-rules ()
        ((_ name Owner State schema initial slot (handlers ...))
         (define name (ann (application-value schema (lambda () initial) (list handlers ...))
                           (Application Owner State))))
        ((_ name Owner State schema initial slot (handlers ...)
            (command (state (arg Type) ...) body ...) rest ...)
         (library-begin
          (define command (command-constructor Owner State slot ((arg Type) ...)))
          (application-handlers-declare name Owner State schema initial (+ slot 1)
                                        (handlers ... (private-handler State (state (arg Type) ...) body ...)) rest ...)))))
    (define-syntax application
      (syntax-rules (state)
        ((_ name (state State schema) initial handlers ...)
         (library-begin
          (define owner-tag (datatype ()
                              (owner-token)))
          (application-handlers-declare name owner-tag State schema initial 0 () handlers ...)))))))
