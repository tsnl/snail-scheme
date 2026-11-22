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
                             (generate Generate)
                             (target (Option (List String)))
                             (known (List LinkedFile)))
      (→ Checked)
      (! mut)
      (let ((expanded (expand-program fs directories generate target known source)))
        (new Checked (expanded expanded) (typed (check-program (● expanded program))))))

    ;; The whole program as one module: its text, the libraries it holds,
    ;; in program order, and the files it links. A build links it with the
    ;; runtime into a module of its own.
    (record WholeProgram
      ((text String)
       (libraries (List String))
       (links (List LinkedFile))))

    (define (source->wat (fs Fs) (directories (List String))
                         (source String)
                         (generate Generate)
                         (target (Option (List String)))
                         (known (List LinkedFile)))
      (→ WholeProgram)
      (! mut)
      (checked->wat (source->checked fs directories source generate target known)))

    (define (checked->wat (checked Checked)) (→ WholeProgram) (! mut)
      (let ((expanded (● checked expanded)))
        (new WholeProgram
          (text (wat->string (emit-module (prepare-program (● checked typed)))))
          (libraries (map (lambda (library) (● library first)) (● (● expanded program) libraries)))
          (links (program-links expanded)))))

    ))
