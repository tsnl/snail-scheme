;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.17 (lambda (xs.1 n.3) (if (null? xs.1) n.3 (loop.17 (cdr xs.1) (+ n.3 (ann 1 I64)))))) loop.17)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def Optional (datatype ( T) (absent) (present (value T optional-value))))

(def present? (All (T) (-> (Optional T) Bool))
  (lambda (value.14) (match value.14 ((absent) #f) ((present item) #t))))

(def TreePart (datatype ()
  (name-part (value RuleName part-name))
  (token-part (value EarleySymbol part-token))
  (child-part (value (List TreePart) part-child))))

(def part-kind
  (lambda (value.13)
    (match value.13 ((name-part name.1) (ann 0 I64)) ((token-part token.1) (ann 1 I64)) ((child-part child) (ann 2 I64)))))

(def EarleySymbol (datatype ()
  (s-symbol)
  (a-symbol)
  (x-symbol)
  (y-symbol)
  (e-symbol)
  (v-symbol)
  (plus-symbol)
  (equals-symbol)
  (unknown-symbol)))

(def symbol-code
  (lambda (value.12)
    (match value.12
      ((s-symbol) (ann 0 I64))
      ((a-symbol) (ann 1 I64))
      ((x-symbol) (ann 2 I64))
      ((y-symbol) (ann 3 I64))
      ((e-symbol) (ann 4 I64))
      ((v-symbol) (ann 5 I64))
      ((plus-symbol) (ann 6 I64))
      ((equals-symbol) (ann 7 I64))
      ((unknown-symbol) (ann 8 I64)))))

(def Definition (datatype ()
  (definition
    (head EarleySymbol definition-head)
    (rules (List (List EarleySymbol)) definition-rules))))

(def Token (datatype ( T) (token (info EarleySymbol token-info) (classes (List T) token-classes))))

(def RuleName (datatype ()
  (rule-name (symbol EarleySymbol rule-name-symbol) (number I64 rule-name-number))))

(def Configuration (datatype () (configuration (slots (Vector (Optional I64)) configuration-slots))))

(def State (datatype ()
  (state (head (Ref I64) state-head) (sets (Vector (Optional Configuration)) state-sets))))

(def ParserDescription (datatype ()
  (parser-description
    (lexer (-> (List EarleySymbol) (List (Token EarleySymbol))) parser-description-lexer)
    (nts (Vector EarleySymbol) parser-description-nts)
    (starters (Vector (List I64)) parser-description-starters)
    (enders (Vector (List I64)) parser-description-enders)
    (predictors (Vector (List I64)) parser-description-predictors)
    (steps (Vector I64) parser-description-steps)
    (names (Vector (Optional RuleName)) parser-description-names))))

(def Parse (datatype ()
  (parse-record
    (nts (Vector EarleySymbol) parse-record-nts)
    (starters (Vector (List I64)) parse-record-starters)
    (enders (Vector (List I64)) parse-record-enders)
    (predictors (Vector (List I64)) parse-record-predictors)
    (steps (Vector I64) parse-record-steps)
    (names (Vector (Optional RuleName)) parse-record-names)
    (toks (Vector (Token I64)) parse-record-toks)
    (states (Vector (Optional State)) parse-record-states)
    (parsed
      (->
        EarleySymbol
        I64
        I64
        (Vector EarleySymbol)
        (Vector (List I64))
        (Vector (Optional State))
        Bool)
      parse-record-parsed)
    (trees
      (->
        EarleySymbol
        I64
        I64
        (Vector EarleySymbol)
        (Vector (List I64))
        (Vector I64)
        (Vector (Optional RuleName))
        (Vector (Token I64))
        (Vector (Optional State))
        (Optional (List (List TreePart))))
      parse-record-trees)
    (count
      (->
        EarleySymbol
        I64
        I64
        (Vector EarleySymbol)
        (Vector (List I64))
        (Vector I64)
        (Vector (Token I64))
        (Vector (Optional State))
        (Optional I64))
      parse-record-count))))

(def configuration-ref
  (lambda (value.11 index.3) (vector-ref (configuration-slots value.11) index.3)))

(def configuration-number
  (lambda (value.10 index.2) (optional-value (configuration-ref value.10 index.2))))

(def configuration-set!
  (lambda (value.9 index.1 number)
    (vector-set! (configuration-slots value.9) index.1 (present number))))

(def state-ref (lambda (value.8 conf.22) (vector-ref (state-sets value.8) conf.22)))

(def state-set!
  (lambda (value.7 conf.21 set) (vector-set! (state-sets value.7) conf.21 (present set))))

(def state-at (lambda (states.17 index) (optional-value (vector-ref states.17 index))))

(def state-work (lambda (value.6) (ref-get (state-head value.6))))

(def state-work! (lambda (value.5 head.6) (ref-set! (state-head value.5) head.6)))

(def same-symbol? (lambda (first.1 second) (= (symbol-code first.1) (symbol-code second))))

(def symbol-member?
  (lambda (value.3 values.4)
    (if (not (null? values.4))
      ((lambda (value.4) (if value.4 value.4 (symbol-member? value.3 (cdr values.4))))
        (same-symbol? value.3 (car values.4)))
      #f)))

(def earley-list
     (syntax-rules ()
       ((_) (empty-list))
       ((_ first rest ...) (cons first (earley-list rest ...)))))

(def earley-append (All (T) (-> (List T) (List T) (List T)))
  (lambda (first last)
    (((lambda () (begin (def loop.16 (lambda (reversed result.2) (if (null? reversed) result.2 (loop.16 (cdr reversed) (cons (car reversed) result.2))))) loop.16)))
      (earley-reverse first)
      last)))

(def earley-reverse (All (T) (-> (List T) (List T)))
  (lambda (values.1)
    (((lambda () (begin (def loop.15 (lambda (values.2 result.1) (if (null? values.2) result.1 (loop.15 (cdr values.2) (cons (car values.2) result.1))))) loop.15)))
      values.1
      (empty-list ))))

(def earley-map (All (A B) (-> (-> A B) (List A) (List B)))
  (lambda (procedure values)
    (if (null? values)
      (empty-list )
      ((lambda (head.5) (cons head.5 (earley-map procedure (cdr values)))) (procedure (car values))))))

(def canonical-grammar
  (earley-list
    (definition
      (s-symbol)
      (earley-list (earley-list (a-symbol)) (earley-list (s-symbol) (s-symbol))))))

(def hide (lambda (count.2 x.2) (hide-i64 x.2)))

(def not-null? (lambda (value.2) (not (null? value.2))))

(def make-parser (-> (List Definition) (-> (List EarleySymbol) (List (Token EarleySymbol))) (-> (List EarleySymbol) Parse))
  (lambda (grammar lexer)
    (begin
      (def non-terminals
        (lambda (grammar.3)
          (begin
            (def add-nt
              (lambda (nt.12 nts.20) (if (symbol-member? nt.12 nts.20) nts.20 (cons nt.12 nts.20))))
            (((lambda () (begin (def def-loop.2 (lambda (defs.2 nts.17) (if (not-null? defs.2) ((lambda (def.2) ((lambda (head.4) ((lambda () (((lambda () (begin (def rule-loop.2 (lambda (rules.2 nts.18) (if (not-null? rules.2) ((lambda (rule.2) (((lambda () (begin (def loop.14 (lambda (l.13 nts.19) (if (not-null? l.13) ((lambda (nt.11) (loop.14 (cdr l.13) (add-nt nt.11 nts.19))) (car l.13)) (rule-loop.2 (cdr rules.2) nts.19)))) loop.14))) rule.2 nts.18)) (car rules.2)) (def-loop.2 (cdr defs.2) nts.18)))) rule-loop.2))) (definition-rules def.2) (add-nt head.4 nts.17))))) (definition-head def.2))) (car defs.2)) (list->vector (earley-reverse nts.17))))) def-loop.2)))
              grammar.3
              (empty-list )))))
      (def ind.1
        (lambda (nt.10 nts.16)
          (((lambda () (begin (def loop.13 (lambda (i.25) (if (>= i.25 (ann 0 I64)) (if (same-symbol? (vector-ref nts.16 i.25) nt.10) (present i.25) (loop.13 (- i.25 (ann 1 I64)))) (absent)))) loop.13)))
            (- (vector-length nts.16) (ann 1 I64)))))
      (def nb-configurations
        (lambda (grammar.2)
          (((lambda () (begin (def def-loop.1 (lambda (defs.1 nb-confs.4) (if (not-null? defs.1) ((lambda (def.1) (((lambda () (begin (def rule-loop.1 (lambda (rules.1 nb-confs.5) (if (not-null? rules.1) ((lambda (rule.1) (((lambda () (begin (def loop.12 (lambda (l.12 nb-confs.6) (if (not-null? l.12) (loop.12 (cdr l.12) (+ nb-confs.6 (ann 1 I64))) (rule-loop.1 (cdr rules.1) (+ nb-confs.6 (ann 1 I64)))))) loop.12))) rule.1 nb-confs.5)) (car rules.1)) (def-loop.1 (cdr defs.1) nb-confs.5)))) rule-loop.1))) (definition-rules def.1) nb-confs.4)) (car defs.1)) nb-confs.4))) def-loop.1)))
            grammar.2
            (ann 0 I64))))
      ((lambda (nts.3) ((lambda (nb-nts) ((lambda (nb-confs) ((lambda (starters) ((lambda (enders.3) ((lambda (predictors) ((lambda (steps.2) ((lambda (names.1) ((lambda () (begin (def setup-tables (lambda (grammar.1 nts.14 starters.5 enders.16 predictors.4 steps.13 names.5) (begin (def add-conf (lambda (conf.20 nt.9 nts.15 class) ((lambda (i.24) (vector-set! class i.24 (cons conf.20 (vector-ref class i.24)))) (optional-value (ind.1 nt.9 nts.15))))) ((lambda (nb-nts.10) (begin (((lambda () (begin (def nt-loop (lambda (i.23) (if (>= i.23 (ann 0 I64)) (begin (vector-set! steps.13 i.23 (- i.23 nb-nts.10)) (vector-set! names.5 i.23 (present (rule-name (vector-ref nts.14 i.23) (ann 0 I64)))) (vector-set! enders.16 i.23 (earley-list i.23)) (nt-loop (- i.23 (ann 1 I64))) (unit)) (unit)))) nt-loop))) (- nb-nts.10 (ann 1 I64))) (((lambda () (begin (def def-loop (lambda (defs conf.17) (if (not-null? defs) (begin ((lambda (lofi-migration-def-1) ((lambda (head.3) ((lambda () (((lambda () (begin (def rule-loop (lambda (rules conf.18 rule-num) (if (not-null? rules) ((lambda (rule) (begin (vector-set! names.5 conf.18 (present (rule-name head.3 rule-num))) (add-conf conf.18 head.3 nts.14 starters.5) (((lambda () (begin (def loop.11 (lambda (l.11 conf.19) (if (not-null? l.11) ((lambda (nt.8) (begin (vector-set! steps.13 conf.19 (optional-value (ind.1 nt.8 nts.14))) (add-conf conf.19 nt.8 nts.14 predictors.4) (loop.11 (cdr l.11) (+ conf.19 (ann 1 I64))))) (car l.11)) (begin (vector-set! steps.13 conf.19 (- (optional-value (ind.1 head.3 nts.14)) nb-nts.10)) (add-conf conf.19 head.3 nts.14 enders.16) (rule-loop (cdr rules) (+ conf.19 (ann 1 I64)) (+ rule-num (ann 1 I64))))))) loop.11))) rule conf.18))) (car rules)) (def-loop (cdr defs) conf.18)))) rule-loop))) (definition-rules lofi-migration-def-1) conf.17 (ann 1 I64))))) (definition-head lofi-migration-def-1))) (car defs)) (unit)) (unit)))) def-loop))) grammar.1 (vector-length nts.14)))) (vector-length nts.14))))) (setup-tables grammar nts.3 starters enders.3 predictors steps.2 names.1) ((lambda (parser-descr) (lambda (input.1) (begin (def ind (lambda (nt.7 nts.13) (((lambda () (begin (def loop.10 (lambda (i.22) (if (>= i.22 (ann 0 I64)) (if (same-symbol? (vector-ref nts.13 i.22) nt.7) (present i.22) (loop.10 (- i.22 (ann 1 I64)))) (absent)))) loop.10))) (- (vector-length nts.13) (ann 1 I64))))) (def comp-tok (lambda (tok.1 nts.12) (((lambda () (begin (def loop.9 (lambda (l1.2 l2.4) (if (not-null? l1.2) ((lambda (i.21) (if (present? i.21) (loop.9 (cdr l1.2) (cons (optional-value i.21) l2.4)) (loop.9 (cdr l1.2) l2.4))) (ind (car l1.2) nts.12)) (token (token-info tok.1) (earley-reverse l2.4))))) loop.9))) (token-classes tok.1) (empty-list )))) (def input->tokens (lambda (input.2 lexer.2 nts.11) (list->vector (earley-map (lambda (tok) (comp-tok tok nts.11)) (lexer.2 input.2))))) (def make-states (lambda (nb-toks.2 nb-confs.3) ((lambda (states.16) (((lambda () (begin (def loop.8 (lambda (i.20) (if (>= i.20 (ann 0 I64)) ((lambda (v) (begin (state-work! v (ann -1 I64)) (vector-set! states.16 i.20 (present v)) (loop.8 (- i.20 (ann 1 I64))))) (state (ref (ann -1 I64)) (make-vector nb-confs.3 (absent)))) states.16))) loop.8))) nb-toks.2)) (make-vector (+ nb-toks.2 (ann 1 I64)) (absent))))) (def conf-set-get (lambda (state.10 conf.16) (state-ref state.10 conf.16))) (def conf-set-get* (lambda (state.9 state-num.6 conf.15) ((lambda (conf-set.12) (if (present? conf-set.12) (optional-value conf-set.12) ((lambda (conf-set.11) (begin (configuration-set! conf-set.11 (ann 1 I64) (ann -3 I64)) (configuration-set! conf-set.11 (ann 2 I64) (ann -1 I64)) (configuration-set! conf-set.11 (ann 3 I64) (ann -1 I64)) (configuration-set! conf-set.11 (ann 4 I64) (ann -1 I64)) (state-set! state.9 conf.15 conf-set.11) conf-set.11)) (configuration (make-vector (+ state-num.6 (ann 6 I64)) (absent)))))) (conf-set-get state.9 conf.15)))) (def conf-set-merge-new! (lambda (conf-set.10) (begin (configuration-set! conf-set.10 (+ (configuration-number conf-set.10 (ann 1 I64)) (ann 5 I64)) (configuration-number conf-set.10 (ann 4 I64))) (configuration-set! conf-set.10 (ann 1 I64) (configuration-number conf-set.10 (ann 3 I64))) (configuration-set! conf-set.10 (ann 3 I64) (ann -1 I64)) (configuration-set! conf-set.10 (ann 4 I64) (ann -1 I64))))) (def conf-set-head (lambda (conf-set.9) (configuration-number conf-set.9 (ann 2 I64)))) (def conf-set-next (lambda (conf-set.8 i.19) (configuration-ref conf-set.8 (+ i.19 (ann 5 I64))))) (def conf-set-member? (lambda (state.8 conf.14 i.18) ((lambda (conf-set.7) (if (present? conf-set.7) (conf-set-next (optional-value conf-set.7) i.18) (absent))) (state-ref state.8 conf.14)))) (def conf-set-adjoin (lambda (state.7 conf-set.6 conf.13 i.17) ((lambda (tail) (begin (configuration-set! conf-set.6 (+ i.17 (ann 5 I64)) (ann -1 I64)) (configuration-set! conf-set.6 (+ tail (ann 5 I64)) i.17) (configuration-set! conf-set.6 (ann 3 I64) i.17) (if (< tail (ann 0 I64)) (begin (configuration-set! conf-set.6 (ann 0 I64) (state-work state.7)) (state-work! state.7 conf.13) (unit)) (unit)))) (configuration-number conf-set.6 (ann 3 I64))))) (def conf-set-adjoin* (lambda (states.15 state-num.5 l.10 i.16) ((lambda (state.6) (((lambda () (begin (def loop.7 (lambda (l1.1) (if (not-null? l1.1) (begin ((lambda (conf.12) ((lambda (conf-set.5) ((lambda () (if (not (present? (conf-set-next conf-set.5 i.16))) (begin (conf-set-adjoin state.6 conf-set.5 conf.12 i.16) (loop.7 (cdr l1.1))) (loop.7 (cdr l1.1)))))) (conf-set-get* state.6 state-num.5 conf.12))) (car l1.1)) (unit)) (unit)))) loop.7))) l.10)) (state-at states.15 state-num.5)))) (def conf-set-adjoin** (lambda (states.14 states*.3 state-num.4 conf.11 i.15) ((lambda (state.5) (if (present? (conf-set-member? state.5 conf.11 i.15)) ((lambda (state*.1) ((lambda (conf-set*) ((lambda () (begin (if (present? (conf-set-next conf-set* i.15)) (unit) (begin (conf-set-adjoin state*.1 conf-set* conf.11 i.15) (unit))) #t)))) (conf-set-get* state*.1 state-num.4 conf.11))) (state-at states*.3 state-num.4)) #f)) (state-at states.14 state-num.4)))) (def conf-set-union (lambda (state.4 conf-set.4 conf.10 other-set) (((lambda () (begin (def loop.6 (lambda (i.14) (if (>= i.14 (ann 0 I64)) (begin (if (not (present? (conf-set-next conf-set.4 i.14))) (begin (conf-set-adjoin state.4 conf-set.4 conf.10 i.14) (loop.6 (optional-value (conf-set-next other-set i.14)))) (loop.6 (optional-value (conf-set-next other-set i.14)))) (unit)) (unit)))) loop.6))) (conf-set-head other-set)))) (def forw (lambda (states.12 state-num.1 starters.3 enders.14 predictors.3 steps.12 nts.10) (begin (def predict (lambda (state.3 state-num.3 conf-set.3 conf.9 nt.6 starters.4 enders.15) (begin (((lambda () (begin (def loop1.6 (lambda (l.9) (if (not-null? l.9) (begin ((lambda (starter) ((lambda (starter-set) ((lambda () (if (not (present? (conf-set-next starter-set state-num.3))) (begin (conf-set-adjoin state.3 starter-set starter state-num.3) (loop1.6 (cdr l.9))) (loop1.6 (cdr l.9)))))) (conf-set-get* state.3 state-num.3 starter))) (car l.9)) (unit)) (unit)))) loop1.6))) (vector-ref starters.4 nt.6)) (((lambda () (begin (def loop2.6 (lambda (l.8) (if (not-null? l.8) (begin ((lambda (ender.3) (if (present? (conf-set-member? state.3 ender.3 state-num.3)) ((lambda (next.1) ((lambda (next-set.1) ((lambda () (begin (conf-set-union state.3 next-set.1 next.1 conf-set.3) (loop2.6 (cdr l.8)))))) (conf-set-get* state.3 state-num.3 next.1))) (+ conf.9 (ann 1 I64))) (loop2.6 (cdr l.8)))) (car l.8)) (unit)) (unit)))) loop2.6))) (vector-ref enders.15 nt.6))))) (def reduce (lambda (states.13 state.2 state-num.2 conf-set.2 head.2 preds.1) (((lambda () (begin (def loop1.5 (lambda (l.7) (if (not-null? l.7) (begin ((lambda (pred) (((lambda () (begin (def loop2.5 (lambda (i.13) (if (>= i.13 (ann 0 I64)) ((lambda (pred-set) (begin (if (present? pred-set) (begin ((lambda (next) ((lambda (next-set) ((lambda () (conf-set-union state.2 next-set next (optional-value pred-set))))) (conf-set-get* state.2 state-num.2 next))) (+ pred (ann 1 I64))) (unit)) (unit)) (loop2.5 (optional-value (conf-set-next conf-set.2 i.13))))) (conf-set-get (state-at states.13 i.13) pred)) (loop1.5 (cdr l.7))))) loop2.5))) head.2)) (car l.7)) (unit)) (unit)))) loop1.5))) preds.1))) ((lambda (state.1 nb-nts.9) (((lambda () (begin (def loop.5 (lambda () ((lambda (conf.8) (if (>= conf.8 (ann 0 I64)) (begin ((lambda (step) ((lambda (conf-set.1) ((lambda (head.1) ((lambda () (begin (state-work! state.1 (configuration-number conf-set.1 (ann 0 I64))) (conf-set-merge-new! conf-set.1) (if (>= step (ann 0 I64)) (predict state.1 state-num.1 conf-set.1 conf.8 step starters.3 enders.14) ((lambda (preds) (reduce states.12 state.1 state-num.1 conf-set.1 head.1 preds)) (vector-ref predictors.3 (+ step nb-nts.9)))) (loop.5))))) (configuration-number conf-set.1 (ann 4 I64)))) (optional-value (state-ref state.1 conf.8)))) (vector-ref steps.12 conf.8)) (unit)) (unit))) (state-work state.1)))) loop.5))))) (state-at states.12 state-num.1) (vector-length nts.10))))) (def forward (lambda (starters.2 enders.13 predictors.2 steps.11 nts.9 toks.10) ((lambda (nb-toks.1) ((lambda (nb-confs.2) ((lambda (states.11) ((lambda (goal-starters) ((lambda () (begin (conf-set-adjoin* states.11 (ann 0 I64) goal-starters (ann 0 I64)) (forw states.11 (ann 0 I64) starters.2 enders.13 predictors.2 steps.11 nts.9) (((lambda () (begin (def loop.4 (lambda (i.12) (if (< i.12 nb-toks.1) (begin ((lambda (tok-nts) (begin (conf-set-adjoin* states.11 (+ i.12 (ann 1 I64)) tok-nts i.12) (forw states.11 (+ i.12 (ann 1 I64)) starters.2 enders.13 predictors.2 steps.11 nts.9) (loop.4 (+ i.12 (ann 1 I64))))) (token-classes (vector-ref toks.10 i.12))) (unit)) (unit)))) loop.4))) (ann 0 I64)) states.11)))) (vector-ref starters.2 (ann 0 I64)))) (make-states nb-toks.1 nb-confs.2))) (vector-length steps.11))) (vector-length toks.10)))) (def produce (lambda (conf.7 i.11 j.8 enders.12 steps.10 toks.9 states.10 states*.2 nb-nts.8) ((lambda (prev.2) (if (if (>= conf.7 nb-nts.8) (>= (vector-ref steps.10 prev.2) (ann 0 I64)) #f) (begin (((lambda () (begin (def loop1.4 (lambda (l.6) (if (not-null? l.6) (begin ((lambda (ender.2) ((lambda (ender-set.2) ((lambda () (if (present? ender-set.2) (((lambda () (begin (def loop2.4 (lambda (k.2) (if (>= k.2 (ann 0 I64)) (begin (if (>= k.2 i.11) (if (conf-set-adjoin** states.10 states*.2 k.2 prev.2 i.11) (conf-set-adjoin** states.10 states*.2 j.8 ender.2 k.2) #f) #f) (loop2.4 (optional-value (conf-set-next (optional-value ender-set.2) k.2)))) (loop1.4 (cdr l.6))))) loop2.4))) (conf-set-head (optional-value ender-set.2))) (loop1.4 (cdr l.6)))))) (conf-set-get (state-at states.10 j.8) ender.2))) (car l.6)) (unit)) (unit)))) loop1.4))) (vector-ref enders.12 (vector-ref steps.10 prev.2))) (unit)) (unit))) (- conf.7 (ann 1 I64))))) (def back (lambda (states.9 states*.1 state-num enders.11 steps.9 nb-nts.7 toks.8) ((lambda (state*) (((lambda () (begin (def loop1.3 (lambda () ((lambda (conf.6) (if (>= conf.6 (ann 0 I64)) (begin ((lambda (conf-set) ((lambda (head) ((lambda () (begin (state-work! state* (configuration-number conf-set (ann 0 I64))) (conf-set-merge-new! conf-set) (((lambda () (begin (def loop2.3 (lambda (i.10) (if (>= i.10 (ann 0 I64)) (begin (produce conf.6 i.10 state-num enders.11 steps.9 toks.8 states.9 states*.1 nb-nts.7) (loop2.3 (optional-value (conf-set-next conf-set i.10)))) (loop1.3)))) loop2.3))) head))))) (configuration-number conf-set (ann 4 I64)))) (optional-value (state-ref state* conf.6))) (unit)) (unit))) (state-work state*)))) loop1.3))))) (state-at states*.1 state-num)))) (def backward (lambda (states.8 enders.10 steps.8 nts.8 toks.7) ((lambda (nb-toks) ((lambda (nb-confs.1) ((lambda (nb-nts.6) ((lambda (states*) ((lambda (goal-enders) ((lambda () (begin (((lambda () (begin (def loop1.2 (lambda (l.5) (if (not-null? l.5) (begin ((lambda (conf.5) (begin (conf-set-adjoin** states.8 states* nb-toks conf.5 (ann 0 I64)) (loop1.2 (cdr l.5)))) (car l.5)) (unit)) (unit)))) loop1.2))) goal-enders) (((lambda () (begin (def loop2.2 (lambda (i.9) (if (>= i.9 (ann 0 I64)) (begin (back states.8 states* i.9 enders.10 steps.8 nb-nts.6 toks.7) (loop2.2 (- i.9 (ann 1 I64))) (unit)) (unit)))) loop2.2))) nb-toks) states*)))) (vector-ref enders.10 (ann 0 I64)))) (make-states nb-toks nb-confs.1))) (vector-length nts.8))) (vector-length steps.8))) (vector-length toks.7)))) (def parsed?.1 (lambda (nt.5 i.8 j.7 nts.7 enders.9 states.7) ((lambda (nt*.2) (if (present? nt*.2) ((lambda (nb-nts.5) (((lambda () (begin (def loop.3 (lambda (l.4) (if (not-null? l.4) ((lambda (conf.4) (if (present? (conf-set-member? (state-at states.7 j.7) conf.4 i.8)) #t (loop.3 (cdr l.4)))) (car l.4)) #f))) loop.3))) (vector-ref enders.9 (optional-value nt*.2)))) (vector-length nts.7)) #f)) (ind nt.5 nts.7)))) (def deriv-trees (lambda (conf.3 i.7 j.6 enders.8 steps.7 names.4 toks.6 states.6 nb-nts.4) ((lambda (name) (if (present? name) (if (< conf.3 nb-nts.4) (earley-list (earley-list (name-part (optional-value name)) (token-part (token-info (vector-ref toks.6 i.7))))) (earley-list (earley-list (name-part (optional-value name))))) ((lambda (prev.1) (((lambda () (begin (def loop1.1 (lambda (l1 l2) (if (not-null? l1) ((lambda (ender.1) ((lambda (ender-set.1) ((lambda () (if (present? ender-set.1) (((lambda () (begin (def loop2.1 (lambda (k.1 l2.1) (if (>= k.1 (ann 0 I64)) (if (if (>= k.1 i.7) (present? (conf-set-member? (state-at states.6 k.1) prev.1 i.7)) #f) ((lambda (prev-trees ender-trees) (((lambda () (begin (def loop3 (lambda (l3 l2.2) (if (not-null? l3) ((lambda (ender-tree) (((lambda () (begin (def loop4 (lambda (l4 l2.3) (if (not-null? l4) (loop4 (cdr l4) (cons (earley-append (car l4) ender-tree) l2.3)) (loop3 (cdr l3) l2.3)))) loop4))) prev-trees l2.2)) (earley-list (child-part (car l3)))) (loop2.1 (optional-value (conf-set-next (optional-value ender-set.1) k.1)) l2.2)))) loop3))) ender-trees l2.1)) (deriv-trees prev.1 i.7 k.1 enders.8 steps.7 names.4 toks.6 states.6 nb-nts.4) (deriv-trees ender.1 k.1 j.6 enders.8 steps.7 names.4 toks.6 states.6 nb-nts.4)) (loop2.1 (optional-value (conf-set-next (optional-value ender-set.1) k.1)) l2.1)) (loop1.1 (cdr l1) l2.1)))) loop2.1))) (conf-set-head (optional-value ender-set.1)) l2) (loop1.1 (cdr l1) l2))))) (conf-set-get (state-at states.6 j.6) ender.1))) (car l1)) l2))) loop1.1))) (vector-ref enders.8 (vector-ref steps.7 prev.1)) (empty-list ))) (- conf.3 (ann 1 I64))))) (vector-ref names.4 conf.3)))) (def deriv-trees*.1 (lambda (nt.4 i.6 j.5 nts.6 enders.7 steps.6 names.3 toks.5 states.5) ((lambda (nt*.1) (if (present? nt*.1) ((lambda (nb-nts.3) (((lambda () (begin (def loop.2 (lambda (l.3 trees) (if (not-null? l.3) ((lambda (conf.2) (if (present? (conf-set-member? (state-at states.5 j.5) conf.2 i.6)) (loop.2 (cdr l.3) (earley-append (deriv-trees conf.2 i.6 j.5 enders.7 steps.6 names.3 toks.5 states.5 nb-nts.3) trees)) (loop.2 (cdr l.3) trees))) (car l.3)) (present trees)))) loop.2))) (vector-ref enders.7 (optional-value nt*.1)) (empty-list ))) (vector-length nts.6)) (absent))) (ind nt.4 nts.6)))) (def nb-deriv-trees (lambda (conf.1 i.5 j.4 enders.6 steps.5 toks.4 states.4 nb-nts.2) ((lambda (prev) (if ((lambda (value.1) (if value.1 value.1 (< (vector-ref steps.5 prev) (ann 0 I64)))) (< conf.1 nb-nts.2)) (ann 1 I64) (((lambda () (begin (def loop1 (lambda (l.2 n.1) (if (not-null? l.2) ((lambda (ender) ((lambda (ender-set) ((lambda () (if (present? ender-set) (((lambda () (begin (def loop2 (lambda (k n.2) (if (>= k (ann 0 I64)) (if (if (>= k i.5) (present? (conf-set-member? (state-at states.4 k) prev i.5)) #f) ((lambda (nb-prev-trees nb-ender-trees) (loop2 (optional-value (conf-set-next (optional-value ender-set) k)) (+ n.2 (* nb-prev-trees nb-ender-trees)))) (nb-deriv-trees prev i.5 k enders.6 steps.5 toks.4 states.4 nb-nts.2) (nb-deriv-trees ender k j.4 enders.6 steps.5 toks.4 states.4 nb-nts.2)) (loop2 (optional-value (conf-set-next (optional-value ender-set) k)) n.2)) (loop1 (cdr l.2) n.2)))) loop2))) (conf-set-head (optional-value ender-set)) n.1) (loop1 (cdr l.2) n.1))))) (conf-set-get (state-at states.4 j.4) ender))) (car l.2)) n.1))) loop1))) (vector-ref enders.6 (vector-ref steps.5 prev)) (ann 0 I64)))) (- conf.1 (ann 1 I64))))) (def nb-deriv-trees*.1 (lambda (nt.3 i.4 j.3 nts.5 enders.5 steps.4 toks.3 states.3) ((lambda (nt*) (if (present? nt*) ((lambda (nb-nts.1) (((lambda () (begin (def loop.1 (lambda (l.1 nb-trees) (if (not-null? l.1) ((lambda (conf) (if (present? (conf-set-member? (state-at states.3 j.3) conf i.4)) (loop.1 (cdr l.1) (+ (nb-deriv-trees conf i.4 j.3 enders.5 steps.4 toks.3 states.3 nb-nts.1) nb-trees)) (loop.1 (cdr l.1) nb-trees))) (car l.1)) (present nb-trees)))) loop.1))) (vector-ref enders.5 (optional-value nt*)) (ann 0 I64))) (vector-length nts.5)) (absent))) (ind nt.3 nts.5)))) ((lambda (lexer.1) ((lambda (nts.4) ((lambda (starters.1) ((lambda (enders.4) ((lambda (predictors.1) ((lambda (steps.3) ((lambda (names.2) ((lambda (toks.2) ((lambda () (parse-record nts.4 starters.1 enders.4 predictors.1 steps.3 names.2 toks.2 (backward (forward starters.1 enders.4 predictors.1 steps.3 nts.4 toks.2) enders.4 steps.3 nts.4 toks.2) parsed?.1 deriv-trees*.1 nb-deriv-trees*.1)))) (input->tokens input.1 lexer.1 nts.4))) (parser-description-names parser-descr))) (parser-description-steps parser-descr))) (parser-description-predictors parser-descr))) (parser-description-enders parser-descr))) (parser-description-starters parser-descr))) (parser-description-nts parser-descr))) (parser-description-lexer parser-descr))))) (parser-description lexer nts.3 starters enders.3 predictors steps.2 names.1)))))) (make-vector nb-confs (absent)))) (make-vector nb-confs (ann 0 I64)))) (make-vector nb-nts (empty-list )))) (make-vector nb-nts (empty-list )))) (make-vector nb-nts (empty-list )))) (+ (nb-configurations grammar) nb-nts))) (vector-length nts.3)))
        (non-terminals grammar)))))

(def parse->parsed? (-> Parse EarleySymbol I64 I64 Bool)
  (lambda (parse.2 nt.2 i.3 j.2)
    ((lambda (nts.2) ((lambda (enders.2) ((lambda (states.2) ((lambda (parsed?) ((lambda () (parsed? nt.2 i.3 j.2 nts.2 enders.2 states.2)))) (parse-record-parsed parse.2))) (parse-record-states parse.2))) (parse-record-enders parse.2)))
      (parse-record-nts parse.2))))

(def parse->trees (-> Parse EarleySymbol I64 I64 (Optional (List (List TreePart))))
  (lambda (parse.1 nt.1 i.2 j.1)
    ((lambda (nts.1) ((lambda (enders.1) ((lambda (steps.1) ((lambda (names) ((lambda (toks.1) ((lambda (states.1) ((lambda (deriv-trees*) ((lambda () (deriv-trees* nt.1 i.2 j.1 nts.1 enders.1 steps.1 names toks.1 states.1)))) (parse-record-trees parse.1))) (parse-record-states parse.1))) (parse-record-toks parse.1))) (parse-record-names parse.1))) (parse-record-steps parse.1))) (parse-record-enders parse.1)))
      (parse-record-nts parse.1))))

(def parse->nb-trees (-> Parse EarleySymbol I64 I64 (Optional I64))
  (lambda (parse nt i.1 j)
    ((lambda (nts) ((lambda (enders) ((lambda (steps) ((lambda (toks) ((lambda (states) ((lambda (nb-deriv-trees*) ((lambda () (nb-deriv-trees* nt i.1 j nts enders steps toks states)))) (parse-record-count parse))) (parse-record-states parse))) (parse-record-toks parse))) (parse-record-steps parse))) (parse-record-enders parse)))
      (parse-record-nts parse))))

(def test (-> (List EarleySymbol) I64)
  (lambda (input)
    ((lambda (p) ((lambda (x.1 n) (length (optional-value (parse->trees x.1 (s-symbol) (ann 0 I64) n)))) (p input) (length input)))
      (make-parser
        canonical-grammar
        (lambda (l) (earley-map (lambda (x) (token x (earley-list x))) l))))))

(def input0 (native-input-i64 (ann 0 I32)))

(def expected-kind (native-input-i64 (ann 1 I32)))

(def expected-value (native-input-i64 (ann 2 I32)))

(def hide-input (lambda (count.1 value) (if (barrier) value (unreachable))))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (present (test (hide-input count (vector->list (make-vector input0 (a-symbol))))))) (if (if (present? result) (if (= expected-kind (ann 1 I64)) (= (optional-value result) expected-value) #f) (= expected-kind (ann 0 I64))) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      (absent))))

(unit)
