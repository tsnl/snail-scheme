(import
  (only (chezscheme)
    current-time
    machine-type
    scheme-version-number
    time-nanosecond
    time-second)
  (except
    (rename (rnrs) (define-record-type r6rs:define-record-type))
    bitwise-and
    bitwise-not
    div
    mod
    partition)
  (rnrs mutable-pairs)
  (rnrs mutable-strings)
  (rnrs r5rs))

(define-syntax define-record-type
  ;; Simplistic R7RS to R6RS define-record-type transformation.
  (syntax-rules ()
    ((define-record-type name
      (make-name param ...)
      name?
      (field-name field-ref field-set!)
      ...)
     (r6rs:define-record-type (name make-name name?)
       (protocol
         (lambda (new)
           (lambda (param ...)
             (new param ...))))
       (fields
         (mutable field-name field-ref field-set!)
         ...)))))

(define (exact-integer? z)
  (and (exact? z) (integer? z)))

 (define read-line
   get-line)

(define (square x)
  (* x x))

(define write-string
  (case-lambda
    ((string)
      (put-string (current-output-port) string))
    ((string port)
      (put-string port string))
    ((string port start)
      (put-string port string start))
    ((string port start end)
      (put-string port string start (fx+ (fx- end start) 1)))))
;; R7RS benchmark timing for compiled Chez programs. The upstream Petite-Chez
;; prelude supplies language compatibility; the benchmark body is unchanged.
;; Use Chez's monotonic clock and integer nanoseconds, not two wall-clock reads.

(define (current-jiffy)
  (let ((now (current-time 'time-monotonic)))
    (+ (* (time-second now) 1000000000) (time-nanosecond now))))

(define (jiffies-per-second) 1000000000)

(define (current-second)
  (/ (current-jiffy) 1000000000.0))

(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (absent) #f)
(define (present value) (vector value))
(define (present? value) (if value #t #f))
(define (optional-value value) (vector-ref value 0))
(define (name-part value) (vector 0 value))
(define (token-part value) (vector 1 value))
(define (child-part value) (vector 2 value))
(define (part-kind value) (vector-ref value 0))
(define (part-name value) (vector-ref value 1))
(define (part-token value) (vector-ref value 1))
(define (part-child value) (vector-ref value 1))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define (unit) (if #f #f))
(define (unreachable) (error 'earley "invalid typed boundary"))
(define (s-symbol) 's)
(define (a-symbol) 'a)
(define (x-symbol) 'x)
(define (y-symbol) 'y)
(define (e-symbol) 'e)
(define (v-symbol) 'v)
(define (plus-symbol) '+)
(define (equals-symbol) '=)
(define (unknown-symbol) 'unknown)
(define (symbol-code value)
  (let loop ((symbols '(s a x y e v + = unknown)) (index 0))
    (if (eq? value (car symbols)) index (loop (cdr symbols) (+ index 1)))))
(define (definition head rules) (vector head rules))
(define (definition-head value) (vector-ref value 0))
(define (definition-rules value) (vector-ref value 1))
(define (token info classes) (vector info classes))
(define (token-info value) (vector-ref value 0))
(define (token-classes value) (vector-ref value 1))
(define (rule-name symbol number) (vector symbol number))
(define (rule-name-symbol value) (vector-ref value 0))
(define (rule-name-number value) (vector-ref value 1))
(define (configuration slots) (vector slots))
(define (configuration-slots value) (vector-ref value 0))
(define (state head sets) (vector head sets))
(define (state-head value) (vector-ref value 0))
(define (state-sets value) (vector-ref value 1))
(define (parser-description lexer nts starters enders predictors steps names) (vector lexer nts starters enders predictors steps names))
(define (parser-description-lexer value) (vector-ref value 0))
(define (parser-description-nts value) (vector-ref value 1))
(define (parser-description-starters value) (vector-ref value 2))
(define (parser-description-enders value) (vector-ref value 3))
(define (parser-description-predictors value) (vector-ref value 4))
(define (parser-description-steps value) (vector-ref value 5))
(define (parser-description-names value) (vector-ref value 6))
(define (parse-record nts starters enders predictors steps names toks states parsed trees count) (vector nts starters enders predictors steps names toks states parsed trees count))
(define (parse-record-nts value) (vector-ref value 0))
(define (parse-record-starters value) (vector-ref value 1))
(define (parse-record-enders value) (vector-ref value 2))
(define (parse-record-predictors value) (vector-ref value 3))
(define (parse-record-steps value) (vector-ref value 4))
(define (parse-record-names value) (vector-ref value 5))
(define (parse-record-toks value) (vector-ref value 6))
(define (parse-record-states value) (vector-ref value 7))
(define (parse-record-parsed value) (vector-ref value 8))
(define (parse-record-trees value) (vector-ref value 9))
(define (parse-record-count value) (vector-ref value 10))
;; Source #f is distinct from every index, including -1 and zero.
;; Configuration slots retain the original five-slot header and intrusive links:
;; 0 work-list link, 1/2 old tail/head, 3/4 new tail/head, 5+i origin link.
(define (configuration-ref value index) (vector-ref (configuration-slots value) index))
(define (configuration-number value index) (optional-value (configuration-ref value index)))
(define (configuration-set! value index number)
  (vector-set! (configuration-slots value) index (present number)))
(define (state-ref value conf) (vector-ref (state-sets value) conf))
(define (state-set! value conf set) (vector-set! (state-sets value) conf (present set)))
(define (state-at states index) (optional-value (vector-ref states index)))
(define (state-work value) (ref-get (state-head value)))
(define (state-work! value head) (ref-set! (state-head value) head))
(define (same-symbol? first second) (= (symbol-code first) (symbol-code second)))
(define (symbol-member? value values)
  (and (not (null? values))
       (or (same-symbol? value (car values)) (symbol-member? value (cdr values)))))
(: earley-list (All (T) (-> (Rest T) (List T))))
(define (earley-list . values) values)
(: earley-append (All (T) (-> (List T) (List T) (List T))))
(define (earley-append first last)
  ;; The final prefix has millions of trees. Explicit reversal bounds stack
  ;; use, adding one temporary list spine; the final suffix remains shared.
  (let loop ((reversed (earley-reverse first)) (result last))
    (if (null? reversed) result
        (loop (cdr reversed) (cons (car reversed) result)))))
(: earley-reverse (All (T) (-> (List T) (List T))))
(define (earley-reverse values)
  (let loop ((values values) (result '()))
    (if (null? values) result (loop (cdr values) (cons (car values) result)))))
(: earley-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (earley-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (earley-map procedure (cdr values))))))
;; This literal precedes the workload, just like the source quoted grammar.
(define canonical-grammar
  (earley-list (definition (s-symbol)
    (earley-list (earley-list (a-symbol)) (earley-list (s-symbol) (s-symbol))))))
(: make-parser (-> (List Definition)
  (-> (List EarleySymbol) (List (Token EarleySymbol))) (-> (List EarleySymbol) Parse)))
(: parse->parsed? (-> Parse EarleySymbol I64 I64 Bool))
(: parse->trees (-> Parse EarleySymbol I64 I64 (Optional (List (List TreePart)))))
(: parse->nb-trees (-> Parse EarleySymbol I64 I64 (Optional I64)))
(: test (-> (List EarleySymbol) I64))
(define (not-null? value) (not (null? value)))
;;; EARLEY -- Earley's parser, written by Marc Feeley.

;; (make-parser grammar lexer) is used to create a parser from the grammar
;; description `grammar' and the lexer function `lexer'.
;;
;; A grammar is a list of definitions.  Each definition defines a non-terminal
;; by a set of rules.  Thus a definition has the form: (nt rule1 rule2...).
;; A given non-terminal can only be defined once.  The first non-terminal
;; defined is the grammar's goal.  Each rule is a possibly empty list of
;; non-terminals.  Thus a rule has the form: (nt1 nt2...).  A non-terminal
;; can be any scheme value.  Note that all grammar symbols are treated as
;; non-terminals.  This is fine though because the lexer will be outputing
;; non-terminals.
;;
;; The lexer defines what a token is and the mapping between tokens and
;; the grammar's non-terminals.  It is a function of one argument, the input,
;; that returns the list of tokens corresponding to the input.  Each token is
;; represented by a list.  The first element is some `user-defined' information
;; associated with the token and the rest represents the token's class(es) (as a
;; list of non-terminals that this token corresponds to).
;;
;; The result of `make-parser' is a function that parses the single input it
;; is given into the grammar's goal.  The result is a `parse' which can be
;; manipulated with the procedures: `parse->parsed?', `parse->trees'
;; and `parse->nb-trees' (see below).
;;
;; Let's assume that we want a parser for the grammar
;;
;;  S -> x = E
;;  E -> E + E | V
;;  V -> V y |
;;
;; and that the input to the parser is a string of characters.  Also, assume we
;; would like to map the characters `x', `y', `+' and `=' into the corresponding
;; non-terminals in the grammar.  Such a parser could be created with
;;
;; (make-parser
;;   '(
;;      (s (x = e))
;;      (e (e + e) (v))
;;      (v (v y) ())
;;    )
;;   (lambda (str)
;;     (earley-map (lambda (char)
;;            (earley-list char;; user-info = the character itself
;;                  (case char
;;                    ((#\x) 'x)
;;                    ((#\y) 'y)
;;                    ((#\+) '+)
;;                    ((#\=) '=)
;;                    (else (fatal-error "lexer error")))))
;;          (string->list str)))
;; )
;;
;; An alternative definition (that does not check for lexical errors) is
;;
;; (make-parser
;;   '(
;;      (s (#\x #\= e))
;;      (e (e #\+ e) (v))
;;      (v (v #\y) ())
;;    )
;;   (lambda (str) (earley-map (lambda (char) (earley-list char char)) (string->list str)))
;; )
;;
;; To help with the rest of the discussion, here are a few definitions:
;;
;; An input pointer (for an input of `n' tokens) is a value between 0 and `n'.
;; It indicates a point between two input tokens (0 = beginning, `n' = end).
;; For example, if `n' = 4, there are 5 input pointers:
;;
;;   input                   token1     token2     token3     token4
;;   input pointers       0          1          2          3          4
;;
;; A configuration indicates the extent to which a given rule is parsed (this
;; is the common `dot notation').  For simplicity, a configuration is
;; represented as an integer, with successive configurations in the same
;; rule associated with successive integers.  It is assumed that the grammar
;; has been extended with rules to aid scanning.  These rules are of the
;; form `nt ->', and there is one such rule for every non-terminal.  Note
;; that these rules are special because they only apply when the corresponding
;; non-terminal is returned by the lexer.
;;
;; A configuration set is a configuration grouped with the set of input pointers
;; representing where the head non-terminal of the configuration was predicted.
;;
;; Here are the rules and configurations for the grammar given above:
;;
;;  S -> .         \
;;       0          |
;;  x -> .          |
;;       1          |
;;  = -> .          |
;;       2          |
;;  E -> .          |
;;       3           > special rules (for scanning)
;;  + -> .          |
;;       4          |
;;  V -> .          |
;;       5          |
;;  y -> .          |
;;       6         /
;;  S -> .  x  .  =  .  E  .
;;       7     8     9     10
;;  E -> .  E  .  +  .  E  .
;;       11    12    13    14
;;  E -> .  V  .
;;       15    16
;;  V -> .  V  .  y  .
;;       17    18    19
;;  V -> .
;;       20
;;
;; Starters of the non-terminal `nt' are configurations that are leftmost
;; in a non-special rule for `nt'.  Enders of the non-terminal `nt' are
;; configurations that are rightmost in any rule for `nt'.  Predictors of the
;; non-terminal `nt' are configurations that are directly to the left of `nt'
;; in any rule.
;;
;; For the grammar given above,
;;
;;   Starters of V   = (17 20)
;;   Enders of V     = (5 19 20)
;;   Predictors of V = (15 17)


(define (make-parser grammar lexer)

  (define (non-terminals grammar);; return vector of non-terminals in grammar

    (define (add-nt nt nts)
      (if (symbol-member? nt nts) nts (cons nt nts)));; use equal? for equality tests

    (let def-loop ((defs grammar) (nts '()))
      (if (not-null? defs)
          (let* ((def (car defs))
                 (head (definition-head def)))
            (let rule-loop ((rules (definition-rules def))
                            (nts (add-nt head nts)))
              (if (not-null? rules)
                  (let ((rule (car rules)))
                    (let loop ((l rule) (nts nts))
                      (if (not-null? l)
                          (let ((nt (car l)))
                            (loop (cdr l) (add-nt nt nts)))
                          (rule-loop (cdr rules) nts))))
                  (def-loop (cdr defs) nts))))
          (list->vector (earley-reverse nts)))));; goal non-terminal must be at index 0

  (define (ind nt nts);; return index of non-terminal `nt' in `nts'
    (let loop ((i (- (vector-length nts) 1)))
      (if (>= i 0)
          (if (same-symbol? (vector-ref nts i) nt) (present i) (loop (- i 1)))
          (absent))))

  (define (nb-configurations grammar);; return nb of configurations in grammar
    (let def-loop ((defs grammar) (nb-confs 0))
      (if (not-null? defs)
          (let ((def (car defs)))
            (let rule-loop ((rules (definition-rules def)) (nb-confs nb-confs))
              (if (not-null? rules)
                  (let ((rule (car rules)))
                    (let loop ((l rule) (nb-confs nb-confs))
                      (if (not-null? l)
                          (loop (cdr l) (+ nb-confs 1))
                          (rule-loop (cdr rules) (+ nb-confs 1)))))
                  (def-loop (cdr defs) nb-confs))))
          nb-confs)))

  ;; First, associate a numeric identifier to every non-terminal in the
  ;; grammar (with the goal non-terminal associated with 0).
  ;;
  ;; So, for the grammar given above we get:
  ;;
  ;; s -> 0   x -> 1   = -> 4   e ->3    + -> 4   v -> 5   y -> 6

  (let* ((nts (non-terminals grammar));; id map = list of non-terms
         (nb-nts (vector-length nts));; the number of non-terms
         (nb-confs (+ (nb-configurations grammar) nb-nts));; the nb of confs
         (starters (make-vector nb-nts '()));; starters for every non-term
         (enders (make-vector nb-nts '()));; enders for every non-term
         (predictors (make-vector nb-nts '()));; predictors for every non-term
         (steps (make-vector nb-confs 0));; what to do in a given conf
         (names (make-vector nb-confs (absent))));; name of rules

    (define (setup-tables grammar nts starters enders predictors steps names)

      (define (add-conf conf nt nts class)
        (let ((i (optional-value (ind nt nts))))
          (vector-set! class i (cons conf (vector-ref class i)))))

      (let ((nb-nts (vector-length nts)))

        (let nt-loop ((i (- nb-nts 1)))
          (when (>= i 0)
            (vector-set! steps i (- i nb-nts))
            (vector-set! names i (present (rule-name (vector-ref nts i) 0)))
            (vector-set! enders i (earley-list i))
            (nt-loop (- i 1))))

        (let def-loop ((defs grammar) (conf (vector-length nts)))
          (when (not-null? defs)
            (let* ((def (car defs))
                   (head (definition-head def)))
              (let rule-loop ((rules (definition-rules def)) (conf conf) (rule-num 1))
                (if (not-null? rules)
                    (let ((rule (car rules)))
                      (vector-set! names conf (present (rule-name head rule-num)))
                      (add-conf conf head nts starters)
                      (let loop ((l rule) (conf conf))
                        (if (not-null? l)
                            (let ((nt (car l)))
                              (vector-set! steps conf (optional-value (ind nt nts)))
                              (add-conf conf nt nts predictors)
                              (loop (cdr l) (+ conf 1)))
                            (begin
                              (vector-set! steps conf (- (optional-value (ind head nts)) nb-nts))
                              (add-conf conf head nts enders)
                              (rule-loop (cdr rules) (+ conf 1) (+ rule-num 1))))))
                    (def-loop (cdr defs) conf))))))))

    ;; Now, for each non-terminal, compute the starters, enders and predictors and
    ;; the names and steps tables.

    (setup-tables grammar nts starters enders predictors steps names)

    ;; Build the parser description

    (let ((parser-descr (parser-description lexer
                                nts
                                starters
                                enders
                                predictors
                                steps
                                names)))
      (lambda (input)

        (define (ind nt nts);; return index of non-terminal `nt' in `nts'
          (let loop ((i (- (vector-length nts) 1)))
            (if (>= i 0)
                (if (same-symbol? (vector-ref nts i) nt) (present i) (loop (- i 1)))
                (absent))))

        (define (comp-tok tok nts);; transform token to parsing format
          (let loop ((l1 (token-classes tok)) (l2 '()))
            (if (not-null? l1)
                (let ((i (ind (car l1) nts)))
                  (if (present? i)
                      (loop (cdr l1) (cons (optional-value i) l2))
                      (loop (cdr l1) l2)))
                (token (token-info tok) (earley-reverse l2)))))

        (define (input->tokens input lexer nts)
          (list->vector (earley-map (lambda (tok) (comp-tok tok nts)) (lexer input))))

        (define (make-states nb-toks nb-confs)
          (let ((states (make-vector (+ nb-toks 1) (absent))))
            (let loop ((i nb-toks))
              (if (>= i 0)
                  (let ((v (state (ref -1) (make-vector nb-confs (absent)))))
                    (state-work! v -1)
                    (vector-set! states i (present v))
                    (loop (- i 1)))
                  states))))

        (define (conf-set-get state conf)
          (state-ref state conf))

        (define (conf-set-get* state state-num conf)
          (let ((conf-set (conf-set-get state conf)))
            (if (present? conf-set)
                (optional-value conf-set)
                (let ((conf-set (configuration (make-vector (+ state-num 6) (absent)))))
                  (configuration-set! conf-set 1 -3);; old elems tail (points to head)
                  (configuration-set! conf-set 2 -1);; old elems head
                  (configuration-set! conf-set 3 -1);; new elems tail (points to head)
                  (configuration-set! conf-set 4 -1);; new elems head
                  (state-set! state conf conf-set)
                  conf-set))))

        (define (conf-set-merge-new! conf-set)
          (configuration-set! conf-set
                       (+ (configuration-number conf-set 1) 5)
                       (configuration-number conf-set 4))
          (configuration-set! conf-set 1 (configuration-number conf-set 3))
          (configuration-set! conf-set 3 -1)
          (configuration-set! conf-set 4 -1))

        (define (conf-set-head conf-set)
          (configuration-number conf-set 2))

        (define (conf-set-next conf-set i)
          (configuration-ref conf-set (+ i 5)))

        (define (conf-set-member? state conf i)
          (let ((conf-set (state-ref state conf)))
            (if (present? conf-set)
                (conf-set-next (optional-value conf-set) i)
                (absent))))

        (define (conf-set-adjoin state conf-set conf i)
          (let ((tail (configuration-number conf-set 3)));; put new element at tail
            (configuration-set! conf-set (+ i 5) -1)
            (configuration-set! conf-set (+ tail 5) i)
            (configuration-set! conf-set 3 i)
            (when (< tail 0)
              (configuration-set! conf-set 0 (state-work state))
              (state-work! state conf))))

        (define (conf-set-adjoin* states state-num l i)
          (let ((state (state-at states state-num)))
            (let loop ((l1 l))
              (when (not-null? l1)
                (let* ((conf (car l1))
                       (conf-set (conf-set-get* state state-num conf)))
                  (if (not (present? (conf-set-next conf-set i)))
                      (begin
                        (conf-set-adjoin state conf-set conf i)
                        (loop (cdr l1)))
                      (loop (cdr l1))))))))

        (define (conf-set-adjoin** states states* state-num conf i)
          (let ((state (state-at states state-num)))
            (if (present? (conf-set-member? state conf i))
                (let* ((state* (state-at states* state-num))
                       (conf-set* (conf-set-get* state* state-num conf)))
                  (unless (present? (conf-set-next conf-set* i))
                    (conf-set-adjoin state* conf-set* conf i))
                  #t)
                #f)))

        (define (conf-set-union state conf-set conf other-set)
          (let loop ((i (conf-set-head other-set)))
            (when (>= i 0)
              (if (not (present? (conf-set-next conf-set i)))
                  (begin
                    (conf-set-adjoin state conf-set conf i)
                    (loop (optional-value (conf-set-next other-set i))))
                  (loop (optional-value (conf-set-next other-set i)))))))

        (define (forw states state-num starters enders predictors steps nts)

          (define (predict state state-num conf-set conf nt starters enders)

            ;; add configurations which start the non-terminal `nt' to the
            ;; right of the dot

            (let loop1 ((l (vector-ref starters nt)))
              (when (not-null? l)
                (let* ((starter (car l))
                       (starter-set (conf-set-get* state state-num starter)))
                  (if (not (present? (conf-set-next starter-set state-num)))
                      (begin
                        (conf-set-adjoin state starter-set starter state-num)
                        (loop1 (cdr l)))
                      (loop1 (cdr l))))))

            ;; check for possible completion of the non-terminal `nt' to the
            ;; right of the dot

            (let loop2 ((l (vector-ref enders nt)))
              (when (not-null? l)
                (let ((ender (car l)))
                  (if (present? (conf-set-member? state ender state-num))
                      (let* ((next (+ conf 1))
                             (next-set (conf-set-get* state state-num next)))
                        (conf-set-union state next-set next conf-set)
                        (loop2 (cdr l)))
                      (loop2 (cdr l)))))))

          (define (reduce states state state-num conf-set head preds)

            ;; a non-terminal is now completed so check for reductions that
            ;; are now possible at the configurations `preds'

            (let loop1 ((l preds))
              (when (not-null? l)
                (let ((pred (car l)))
                  (let loop2 ((i head))
                    (if (>= i 0)
                        (let ((pred-set (conf-set-get (state-at states i) pred)))
                          (when (present? pred-set)
                            (let* ((next (+ pred 1))
                                   (next-set (conf-set-get* state state-num next)))
                              (conf-set-union state next-set next (optional-value pred-set))))
                          (loop2 (optional-value (conf-set-next conf-set i))))
                        (loop1 (cdr l))))))))

          (let ((state (state-at states state-num))
                (nb-nts (vector-length nts)))
            (let loop ()
              (let ((conf (state-work state)))
                (when (>= conf 0)
                  (let* ((step (vector-ref steps conf))
                         (conf-set (optional-value (state-ref state conf)))
                         (head (configuration-number conf-set 4)))
                    (state-work! state (configuration-number conf-set 0))
                    (conf-set-merge-new! conf-set)
                    (if (>= step 0)
                        (predict state state-num conf-set conf step starters enders)
                        (let ((preds (vector-ref predictors (+ step nb-nts))))
                          (reduce states state state-num conf-set head preds)))
                    (loop)))))))

        (define (forward starters enders predictors steps nts toks)
          (let* ((nb-toks (vector-length toks))
                 (nb-confs (vector-length steps))
                 (states (make-states nb-toks nb-confs))
                 (goal-starters (vector-ref starters 0)))
            (conf-set-adjoin* states 0 goal-starters 0);; predict goal
            (forw states 0 starters enders predictors steps nts)
            (let loop ((i 0))
              (when (< i nb-toks)
                (let ((tok-nts (token-classes (vector-ref toks i))))
                  (conf-set-adjoin* states (+ i 1) tok-nts i);; scan token
                  (forw states (+ i 1) starters enders predictors steps nts)
                  (loop (+ i 1)))))
            states))

        (define (produce conf i j enders steps toks states states* nb-nts)
          (let ((prev (- conf 1)))
            (when (and (>= conf nb-nts) (>= (vector-ref steps prev) 0))
              (let loop1 ((l (vector-ref enders (vector-ref steps prev))))
                (when (not-null? l)
                  (let* ((ender (car l))
                         (ender-set (conf-set-get (state-at states j)
                                                  ender)))
                    (if (present? ender-set)
                        (let loop2 ((k (conf-set-head (optional-value ender-set))))
                          (if (>= k 0)
                              (begin
                                (and (>= k i)
                                     (conf-set-adjoin** states states* k prev i)
                                     (conf-set-adjoin** states states* j ender k))
                                (loop2 (optional-value (conf-set-next (optional-value ender-set) k))))
                              (loop1 (cdr l))))
                        (loop1 (cdr l)))))))))

        (define (back states states* state-num enders steps nb-nts toks)
          (let ((state* (state-at states* state-num)))
            (let loop1 ()
              (let ((conf (state-work state*)))
                (when (>= conf 0)
                  (let* ((conf-set (optional-value (state-ref state* conf)))
                         (head (configuration-number conf-set 4)))
                    (state-work! state* (configuration-number conf-set 0))
                    (conf-set-merge-new! conf-set)
                    (let loop2 ((i head))
                      (if (>= i 0)
                          (begin
                            (produce conf i state-num enders steps
                                     toks states states* nb-nts)
                            (loop2 (optional-value (conf-set-next conf-set i))))
                          (loop1)))))))))

        (define (backward states enders steps nts toks)
          (let* ((nb-toks (vector-length toks))
                 (nb-confs (vector-length steps))
                 (nb-nts (vector-length nts))
                 (states* (make-states nb-toks nb-confs))
                 (goal-enders (vector-ref enders 0)))
            (let loop1 ((l goal-enders))
              (when (not-null? l)
                (let ((conf (car l)))
                  (conf-set-adjoin** states states* nb-toks conf 0)
                  (loop1 (cdr l)))))
            (let loop2 ((i nb-toks))
              (when (>= i 0)
                (back states states* i enders steps nb-nts toks)
                (loop2 (- i 1))))
            states*))

        (define (parsed? nt i j nts enders states)
          (let ((nt* (ind nt nts)))
            (if (present? nt*)
                (let ((nb-nts (vector-length nts)))
                  (let loop ((l (vector-ref enders (optional-value nt*))))
                    (if (not-null? l)
                        (let ((conf (car l)))
                          (if (present? (conf-set-member? (state-at states j) conf i))
                              #t
                              (loop (cdr l))))
                        #f)))
                #f)))

        (define (deriv-trees conf i j enders steps names toks states nb-nts)
          (let ((name (vector-ref names conf)))

            (if (present? name);; `conf' is at the start of a rule (either special or not)
                (if (< conf nb-nts)
                    (earley-list (earley-list (name-part (optional-value name)) (token-part (token-info (vector-ref toks i)))))
                    (earley-list (earley-list (name-part (optional-value name)))))

                (let ((prev (- conf 1)))
                  (let loop1 ((l1 (vector-ref enders (vector-ref steps prev)))
                              (l2 '()))
                    (if (not-null? l1)
                        (let* ((ender (car l1))
                               (ender-set (conf-set-get (state-at states j)
                                                        ender)))
                          (if (present? ender-set)
                              (let loop2 ((k (conf-set-head (optional-value ender-set))) (l2 l2))
                                (if (>= k 0)
                                    (if (and (>= k i)
                                             (present? (conf-set-member? (state-at states k)
                                                               prev i)))
                                        (let ((prev-trees
                                               (deriv-trees prev i k enders steps names
                                                            toks states nb-nts))
                                              (ender-trees
                                               (deriv-trees ender k j enders steps names
                                                            toks states nb-nts)))
                                          (let loop3 ((l3 ender-trees) (l2 l2))
                                            (if (not-null? l3)
                                                (let ((ender-tree (earley-list (child-part (car l3)))))
                                                  (let loop4 ((l4 prev-trees) (l2 l2))
                                                    (if (not-null? l4)
                                                        (loop4 (cdr l4)
                                                               (cons (earley-append (car l4)
                                                                             ender-tree)
                                                                     l2))
                                                        (loop3 (cdr l3) l2))))
                                                (loop2 (optional-value (conf-set-next (optional-value ender-set) k)) l2))))
                                        (loop2 (optional-value (conf-set-next (optional-value ender-set) k)) l2))
                                    (loop1 (cdr l1) l2)))
                              (loop1 (cdr l1) l2)))
                        l2))))))

        (define (deriv-trees* nt i j nts enders steps names toks states)
          (let ((nt* (ind nt nts)))
            (if (present? nt*)
                (let ((nb-nts (vector-length nts)))
                  (let loop ((l (vector-ref enders (optional-value nt*))) (trees '()))
                    (if (not-null? l)
                        (let ((conf (car l)))
                          (if (present? (conf-set-member? (state-at states j) conf i))
                              (loop (cdr l)
                                    (earley-append (deriv-trees conf i j enders steps names
                                                         toks states nb-nts)
                                            trees))
                              (loop (cdr l) trees)))
                        (present trees))))
                (absent))))

        (define (nb-deriv-trees conf i j enders steps toks states nb-nts)
          (let ((prev (- conf 1)))
            (if (or (< conf nb-nts) (< (vector-ref steps prev) 0))
                1
                (let loop1 ((l (vector-ref enders (vector-ref steps prev)))
                            (n 0))
                  (if (not-null? l)
                      (let* ((ender (car l))
                             (ender-set (conf-set-get (state-at states j)
                                                      ender)))
                        (if (present? ender-set)
                            (let loop2 ((k (conf-set-head (optional-value ender-set))) (n n))
                              (if (>= k 0)
                                  (if (and (>= k i)
                                           (present? (conf-set-member? (state-at states k)
                                                             prev i)))
                                      (let ((nb-prev-trees
                                             (nb-deriv-trees prev i k enders steps
                                                             toks states nb-nts))
                                            (nb-ender-trees
                                             (nb-deriv-trees ender k j enders steps
                                                             toks states nb-nts)))
                                        (loop2 (optional-value (conf-set-next (optional-value ender-set) k))
                                               (+ n (* nb-prev-trees nb-ender-trees))))
                                      (loop2 (optional-value (conf-set-next (optional-value ender-set) k)) n))
                                  (loop1 (cdr l) n)))
                            (loop1 (cdr l) n)))
                      n)))))

        (define (nb-deriv-trees* nt i j nts enders steps toks states)
          (let ((nt* (ind nt nts)))
            (if (present? nt*)
                (let ((nb-nts (vector-length nts)))
                  (let loop ((l (vector-ref enders (optional-value nt*))) (nb-trees 0))
                    (if (not-null? l)
                        (let ((conf (car l)))
                          (if (present? (conf-set-member? (state-at states j) conf i))
                              (loop (cdr l)
                                    (+ (nb-deriv-trees conf i j enders steps
                                                       toks states nb-nts)
                                       nb-trees))
                              (loop (cdr l) nb-trees)))
                        (present nb-trees))))
                (absent))))

        (let* ((lexer      (parser-description-lexer parser-descr))
               (nts        (parser-description-nts parser-descr))
               (starters   (parser-description-starters parser-descr))
               (enders     (parser-description-enders parser-descr))
               (predictors (parser-description-predictors parser-descr))
               (steps      (parser-description-steps parser-descr))
               (names      (parser-description-names parser-descr))
               (toks       (input->tokens input lexer nts)))

          (parse-record nts
                  starters
                  enders
                  predictors
                  steps
                  names
                  toks
                  (backward (forward starters enders predictors steps nts toks)
                            enders steps nts toks)
                  parsed?
                  deriv-trees*
                  nb-deriv-trees*))))))

(define (parse->parsed? parse nt i j)
  (let* ((nts     (parse-record-nts parse))
         (enders  (parse-record-enders parse))
         (states  (parse-record-states parse))
         (parsed? (parse-record-parsed parse)))
    (parsed? nt i j nts enders states)))

(define (parse->trees parse nt i j)
  (let* ((nts          (parse-record-nts parse))
         (enders       (parse-record-enders parse))
         (steps        (parse-record-steps parse))
         (names        (parse-record-names parse))
         (toks         (parse-record-toks parse))
         (states       (parse-record-states parse))
         (deriv-trees* (parse-record-trees parse)))
    (deriv-trees* nt i j nts enders steps names toks states)))

(define (parse->nb-trees parse nt i j)
  (let* ((nts             (parse-record-nts parse))
         (enders          (parse-record-enders parse))
         (steps           (parse-record-steps parse))
         (toks            (parse-record-toks parse))
         (states          (parse-record-states parse))
         (nb-deriv-trees* (parse-record-count parse)))
    (nb-deriv-trees* nt i j nts enders steps toks states)))

(define (test input)
  (let ((p (make-parser canonical-grammar
                        (lambda (l) (earley-map (lambda (x) (token x (earley-list x))) l)))))
    (let ((x (p input))
          (n (length input)))
      (length (optional-value (parse->trees x (s-symbol) 0 n))))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "earley"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (test (hide count (vector->list (make-vector input1 'a)))))
     (lambda (result) (equal? result output)))))

(define (this-scheme-implementation-name) "chez")

;;; The following code is appended to all benchmarks.

;;; Given an integer and an object, returns the object
;;; without making it too easy for compilers to tell
;;; the object will be returned.

(define (hide r x)
  (call-with-values
   (lambda ()
     (values (vector values (lambda (x) x))
             (if (< r 100) 0 1)))
   (lambda (v i)
     ((vector-ref v i) x))))

;;; Given the name of a benchmark,
;;; the number of times it should be executed,
;;; a thunk that runs the benchmark once,
;;; and a unary predicate that is true of the
;;; correct results the thunk may return,
;;; runs the benchmark for the number of specified iterations.

(define (run-r7rs-benchmark name count thunk ok?)

  ;; Rounds to thousandths.
  (define (rounded x)
    (/ (round (* 1000 x)) 1000))

  (display "Running ")
  (display name)
  (newline)
  (flush-output-port (current-output-port))
  (let* ((j/s (jiffies-per-second))
         (t0 (current-second))
         (j0 (current-jiffy)))
    (let loop ((i 0)
               (result #f))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? result)
             (let* ((t1 (current-second))
                    (j1 (current-jiffy))
                    (jifs (- j1 j0))
                    (secs (inexact (/ jifs j/s)))
                    (secs2 (rounded (- t1 t0))))
               (display "Elapsed time: ")
               (write secs)
               (display " seconds (")
               (write secs2)
               (display ") for ")
               (display name)
               (newline)
               (display "+!CSVLINE!+")
               (display (this-scheme-implementation-name))
               (display ",")
               (display name)
               (display ",")
               (display secs)
               (newline)
               (flush-output-port (current-output-port)))
             0)
            (else
             (display "ERROR: returned incorrect result: ")
             (write result)
             (newline)
             (display "+!CSVLINE!+")
             (display (this-scheme-implementation-name))
             (display ",")
             (display name)
             (display ",")
             (display "INCORRECT")
             (newline)
             (flush-output-port (current-output-port))
             0)))))

(run-benchmark)
