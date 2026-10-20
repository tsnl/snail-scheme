(define-library (macro declarations)
  (export define-counter call-through-binding application)
  (import
   (lofi core)
   (only (lofi base) i32-add vector))
  (begin
    (def private-increment (-> I32 I32) (lambda (value) (i32-add value 1)))
    (define-syntax define-counter
         (syntax-rules ()
           ((_ State make-state state-value advance commands)
            (begin
             (define-syntax private-step
                  (syntax-rules ()
                    ((_ state) (make-state (private-increment (state-value state))))))
             (def State (datatype ()
                          (make-state
                           (value I32 state-value))))
             (def advance (-> State State) (lambda (state) (private-step state)))
             (def commands (Vector (-> State State))
                  (vector (ann advance (-> State State))))))))
    (define-syntax call-through-binding
         (syntax-rules ()
           ((_ name)
            (begin
             (def name (-> I32 I32) (lambda (value) value))
             (name 42)))))
    (define-syntax application
         (syntax-rules ()
           ((_ registry State handler ...)
            (begin
             (def registry (Vector (-> State State))
                  (vector (ann handler (-> State State)) ...))))))))
