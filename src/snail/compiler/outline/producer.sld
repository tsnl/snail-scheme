;; Query: the producer program of a generated library. A
;; `generate-library` recipe does not hold its library's text: a program
;; made from it, its producer, computes the text when a build compiles and
;; runs it. The producer imports what the recipe imports, names the
;; recipe's file and writes what the recipe's expression returns, as the
;; old `producer` (src/snail/shell/compiler/expand.sld) writes it. Its key
;; names the file the build prints it to and the file its output is read
;; from, and the old compiler names the same files by the same keys, so
;; the text it hashes is the old `producer-text`, and the key the old
;; `producer-key`, character for character.
(define-library (snail compiler outline producer)
  (export
   ProducerProgram
   producer-program
   printed-producer)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read language)
   (snail compiler read written))
  (begin

    ;; ---- Producer programs ----

    ;; A producer program: its forms, its text, which is the forms one to
    ;; a line, and its key.
    (struct ProducerProgram
      ((forms (List Syntax))
       (text String)
       (key String)))

    ;; The producer of the recipe written at `loc` in the file `recipe`,
    ;; which imports `imports` and returns `expression`, whose imports are
    ;; found in `directories`.
    (: producer-program
       (impl (Fn (List String) String (List Syntax) Syntax Loc -> ProducerProgram)))
    (define (producer-program directories recipe imports expression loc)
      (let* ((forms (producer-forms recipe imports expression loc))
             (text (string-join (map syntax-text forms) "\n")))
        (ProducerProgram forms text (producer-key directories text))))

    ;; `(import IMPORT ... (only (snail shell syntax) write-generated-library))`,
    ;; `(recipe "FILE")` and `(write-generated-library (lambda () EXPRESSION))`,
    ;; which computes the expression in a task, so it may read what the
    ;; recipe links. Each form the recipe did not write is at the recipe's
    ;; `generate-library` form.
    (: producer-forms (impl (Fn String (List Syntax) Syntax Loc -> (List Syntax))))
    (define (producer-forms recipe imports expression loc)
      (let ((writer (Ident "write-generated-library" loc)))
        (list (Form (Cons (Ident "import" loc)
                          (append imports
                                  (list (Form (list (Ident "only" loc)
                                                    (Form (list (Ident "snail" loc)
                                                                (Ident "shell" loc)
                                                                (Ident "syntax" loc))
                                                          loc)
                                                    writer)
                                              loc))))
                    loc)
              (Form (list (Ident "recipe" loc) (Atom (Text recipe) loc)) loc)
              (Form (list writer (Form (list (Ident "lambda" loc) (Form (Nil) loc) expression) loc))
                    loc))))

    ;; ---- Keys ----

    ;; A build tells producers apart by the library directories their
    ;; imports are found in, each a string literal, then a newline and the
    ;; program's text: two targets of one build may find a recipe's imports
    ;; in different directories, and so in different libraries. The key is
    ;; that text's FNV-1a in decimal.
    (: producer-key (impl (Fn (List String) String -> String)))
    (define (producer-key directories text)
      (i64->string (fnv-1a (string-append (string-join (map text-literal directories) " ")
                                          "\n"
                                          text))))

    ;; ---- Printing ----

    ;; The producer as a build prints it, KEY.sld: the keys of the
    ;; libraries loading when it was reached, innermost first, as
    ;; `(generating "sample.knot" ...)`, so that a producer importing the
    ;; library it generates is an import cycle; then its text. The key
    ;; leaves the first line out, since what the producer writes does not
    ;; depend on the chain that reached it.
    (: printed-producer (impl (Fn (List String) ProducerProgram -> String)))
    (define (printed-producer loading program)
      (string-append "(generating"
                     (string-concatenate (map (lambda (key) (string-append " " (text-literal key)))
                                              loading))
                     ")\n"
                     (::text program)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-producer)
    (import
     (snail stage0 testing))
    (begin
      (define (test-producer)
        (test-forms)
        (test-keys)
        (test-printing))

      (define at (Loc "lib/sample/made.sld" 1 1))

      (define (at-column column)
        (Loc "lib/sample/made.sld" 2 column))

      ;; The recipe `(generate-library (sample made) (import (snail core
      ;; base) (only (x) y)) (make "a\"b"))`, whose expression is at column 9.
      (define imports
        (list (Form (list (Ident "snail" (at-column 3))
                          (Ident "core" (at-column 4))
                          (Ident "base" (at-column 5)))
                    (at-column 2))
              (Form (list (Ident "only" (at-column 7))
                          (Form (list (Ident "x" (at-column 8))) (at-column 7))
                          (Ident "y" (at-column 8)))
                    (at-column 6))))

      (define expression
        (Form (list (Ident "make" (at-column 10)) (Atom (Text "a\"b") (at-column 11)))
              (at-column 9)))

      (define program
        (producer-program (list "lib" "src") "lib/sample/made.sld" imports expression at))

      (define text
        (string-append
         "(import (snail core base) (only (x) y) (only (snail shell syntax) write-generated-library))\n"
         "(recipe \"lib/sample/made.sld\")\n"
         "(write-generated-library (lambda () (make \"a\\\"b\")))"))

      ;; The recipe's imports and expression are kept as written, where
      ;; they are written, and every other form is at the recipe.
      (define (test-forms)
        (let ((writer (Ident "write-generated-library" at)))
          (expect (::forms program)
                  (list (Form (append (list (Ident "import" at))
                                      imports
                                      (list (Form (list (Ident "only" at)
                                                        (Form (list (Ident "snail" at)
                                                                    (Ident "shell" at)
                                                                    (Ident "syntax" at))
                                                              at)
                                                        writer)
                                                  at)))
                              at)
                        (Form (list (Ident "recipe" at) (Atom (Text "lib/sample/made.sld") at)) at)
                        (Form (list writer
                                    (Form (list (Ident "lambda" at) (Form (list) at) expression)
                                          at))
                              at))))
        (expect (::text program) text))

      ;; The key hashes the directories, quoted, before the text, so other
      ;; directories make another key. The number is the old compiler's
      ;; key for the same producer.
      (define (test-keys)
        (expect (::key program) "1906311923")
        (expect (::key program)
                (i64->string (fnv-1a (string-append "\"lib\" \"src\"\n" text))))
        (expect (string=? (::key program)
                          (::key (producer-program (list "src")
                                                   "lib/sample/made.sld"
                                                   imports
                                                   expression
                                                   at)))
                #f))

      ;; The libraries loading come first, as string literals, innermost
      ;; first.
      (define (test-printing)
        (expect (printed-producer (list "sample.made" "a.b") program)
                (string-append "(generating \"sample.made\" \"a.b\")\n" text))
        (expect (printed-producer (list) program) (string-append "(generating)\n" text)))))
   (else)))
