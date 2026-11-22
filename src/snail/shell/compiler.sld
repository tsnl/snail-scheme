;; The compiler's passes in order, from a program's source path to
;; WebAssembly text. Every invocation reads, checks and emits the whole
;; program afresh. The typed driver serves
;; both compiler entries: Chez runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail shell compiler)
  (export
   WholeProgram
   source->wat
   checked->wat
   Checked
   source->checked
   LinkedFile)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler prepare)
   (snail shell compiler wasm))
  (begin

    ;; A program read, expanded and checked, before anything is emitted: what
    ;; a build emits, and what an editor asks of the program's names (snail
    ;; shell lsp).
    (record Checked
      ((expanded ExpandedProgram)
       (typed Typed)))

    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes. `known` are linked files whose digests an
    ;; earlier build took, trusted while each keeps its size and
    ;; modification time.

    (define (source->checked (fs Fs) (directories (List String))
                             (source String)
                             (generate (Fn (List String) (List Syntax) → Bytes ! mut compile))
                             (target (Option (List String)))
                             (known (List LinkedFile)))
      (→ Checked)
      (! mut compile)
      (let* ((expanded (expand-program fs directories generate target known source))
             (typed (check-program (● expanded program))))
        (write-file fs (string-append "build/capdump/" (dump-file-name source) ".txt")
                    (dump-capabilities typed))
        (new Checked (expanded expanded) (typed typed))))

    ;; ---- TEMPORARY: capability dump ----

    (define (dump-file-name (source String)) (→ String)
      (list->string (map (lambda (c) (if (char=? c #\/) #\_ c)) (string->list source))))

    (define (row-labels (type Type)) (→ (List String))
      (match type
        ((TFun _ _ (TRow labels _)) labels)
        (_ (Nil))))

    (define (value-labels (typed Typed) (name String)) (→ (List String))
      (match (program-value (● typed program) name)
        ((Some (Defined (Some scheme) _)) (row-labels (● scheme type)))
        ((Some (Defined (None) _))
         (match (table-ref (● typed schemes) name)
           ((Some scheme) (row-labels (● scheme type)))
           ((None) (Nil))))
        ((Some (Operation _ scheme)) (row-labels (● scheme type)))
        ((Some (Method _ scheme)) (row-labels (● scheme type)))
        (_ (Nil))))

    (define (dump-line (kind String) (loc Loc) (name String) (labels (List String))) (→ String)
      (string-append kind "\t" (● loc file) "\t" (i64->string (● loc line)) "\t"
                     (i64->string (● loc column)) "\t" name "\t" (string-join labels " ") "\n"))

    (define (unwrap-ann (expr Expr)) (→ Expr)
      (match (● expr term)
        ((Ann inner _) (unwrap-ann inner))
        (_ expr)))

    (define (dump-expr (typed Typed) (expr Expr) (out (List String))) (→ (List String))
      (match (● expr term)
        ((App callee args)
         (let* ((target (unwrap-ann callee))
                (out (match (● target term)
                       ((Var name _ _)
                        (let ((labels (value-labels typed name)))
                          (if (null? labels) out
                              (Cons (dump-line "C" (● expr loc) name labels) out))))
                       (_ (dump-expr typed callee out)))))
           (fold-left (lambda (out arg) (dump-expr typed arg out)) out args)))
        ((Var name _ _)
         (let ((labels (value-labels typed name)))
           (if (null? labels) out (Cons (dump-line "V" (● expr loc) name labels) out))))
        ((Handle effect _ _)
         (fold-left (lambda (out child) (dump-expr typed child out))
                    (Cons (dump-line "H" (● expr loc) effect (Nil)) out)
                    (expr-children expr)))
        (_ (fold-left (lambda (out child) (dump-expr typed child out)) out (expr-children expr)))))

    (define (dump-capabilities (typed Typed)) (→ String)
      (string-concatenate
       (reverse
        (fold-left (lambda (out item)
                     (match item
                       ((Define name value)
                        (dump-expr typed value
                                   (Cons (dump-line "D" (● value loc) name (value-labels typed name))
                                         out)))
                       (_ out)))
                   (Nil)
                   (● typed items)))))

    ;; The whole program as one module: its text, the libraries it holds,
    ;; in program order, and the files it links. A build links it with the
    ;; runtime into a module of its own.
    (record WholeProgram
      ((text String)
       (libraries (List String))
       (links (List LinkedFile))))

    (define (source->wat (fs Fs) (directories (List String))
                         (source String)
                         (generate (Fn (List String) (List Syntax) → Bytes ! mut compile))
                         (target (Option (List String)))
                         (known (List LinkedFile)))
      (→ WholeProgram)
      (! mut compile)
      (checked->wat (source->checked fs directories source generate target known)))

    (define (checked->wat (checked Checked)) (→ WholeProgram) (! mut compile)
      (let ((expanded (● checked expanded)))
        (new WholeProgram
          (text (wat->string (emit-module (prepare-program (● checked typed)))))
          (libraries (map (lambda (library) (● library first)) (● (● expanded program) libraries)))
          (links (program-links expanded)))))

    ))
