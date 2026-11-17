;; Shaders as S-expressions, printed to WGSL text one form to one
;; construct. A `generate-library` recipe reads each shader file when its
;; library is built and defines its text, so a program ships WGSL and a
;; mistake in a shader's form fails the build at its line:
;;
;;   (generate-library (apps quad shaders)
;;     (import (snail core base) (snail shell graphics wgsl))
;;     (shader-library (list "apps" "quad" "shaders")
;;                     (list (new Pair (first "quad") (second (link-file "quad.wgsl.scm"))))))
;;
;; Struct declarations of a record deriving Pod come from its Shape at run
;; time, prepended with `declarations`, so a shader names those structs
;; without declaring them.
;;
;; The notation:
;;
;; | Form | WGSL |
;; | --- | --- |
;; | `(struct S (x f32) ((@location 0) uv vec2f))` | `struct S { x: f32, @location(0) uv: vec2f, }` |
;; | `(var (@group 0) (@binding 0) (scene Scene))` | `@group(0) @binding(0) var scene: Scene;` |
;; | `((var uniform) (camera Camera))` | `var<uniform> camera: Camera;` |
;; | `(let x e)`, `(let (x f32) e)`, `(const …)`, `(override …)` | `let x = e;`, `let x: f32 = e;` |
;; | `(alias A T)`, `(enable f16)` | `alias A = T;`, `enable f16;` |
;; | `(fn (@vertex) main (((@builtin vertex_index) i u32)) (-> (@builtin position) vec4f) s …)` | `@vertex fn main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f { s … }` |
;; | `(return e)`, `(discard)`, `(break)`, `(continue)` | `return e;` … |
;; | `(= p e)`, `(+= p e)`, `(-= p e)`, `(*= p e)`, `(/= p e)` | `p = e;` … |
;; | `(if (c s …) (c s …) (else s …))` | `if c { … } else if c { … } else { … }` |
;; | `(for (init c update) s …)`, `(while c s …)`, `(loop s …)`, `(begin s …)` | `for (init; c; update) { … }` … |
;; | `(+ a b c)`, `(- a)`, `(and a b)`, `(or a b)`, `(not a)` | `(a + b + c)`, `(-a)`, `(a && b)`, `(a \|\| b)`, `(!a)` |
;; | `(bit-and a b)`, `(bit-or a b)`, `(bit-xor a b)`, `(bit-not a)` | `(a & b)`, `(a \| b)`, `(a ^ b)`, `(~a)` |
;; | `(address-of p)`, `(deref p)` | `(&p)`, `(*p)` |
;; | `(get e x)`, `(get e x y)`, `(at e i)` | `e.x`, `e.x.y`, `e[i]` |
;; | `(f a b)`, `((vec4 f32) a)`, `((bitcast u32) x)` | `f(a, b)`, `vec4<f32>(a)`, `bitcast<u32>(x)` |
;; | `(array f32 4)` as a type | `array<f32, 4>` |
;;
;; Comparisons and shifts are the binary operators `==`, `!=`, `<`, `<=`,
;; `>`, `>=`, `<<` and `>>`, written as forms like `+`.
(define-library (snail shell graphics wgsl)
  (export
   wgsl-text
   shader-library)
  (import
   (snail core base)
   (only (snail shell utf8) utf8->string)
   (only (snail shell task) tasks)
   (snail shell resource)
   (snail shell syntax)
   (rename (only (snail shell compiler read)
                 Syntax
                 Atom
                 Ident
                 Form
                 Loc
                 DInt
                 DFloat
                 DBool
                 syntax-loc
                 compile
                 compile-error
                 compiling
                 Failed
                 diagnostics->string
                 read-text)
           (Syntax Source-syntax)))
  (begin

    ;; ---- Libraries ----

    ;; The library `name`, defining each shader's text by its name: the
    ;; shader is read from its linked file now.

    (define (shader-library (name (List String)) (shaders (List (Pair String Resource))))
      (→ Syntax)
      (! resource tasks)
      (library-syntax name
                      (map (lambda (shader) (● shader first)) shaders)
                      (list (list "snail" "core" "base"))
                      (map (lambda (shader)
                             (form "define"
                                   (list (SymbolSyntax (● shader first))
                                         (form "→" (list (SymbolSyntax "String")))
                                         (chunked (shader-text (● shader first)
                                                               (read-resource (● shader second)))))))
                           shaders)))

    ;; A long text as literals of at most 8000 characters joined at run
    ;; time, since a string literal is one `array.new_fixed`, which V8
    ;; limits to 10000 elements.
    (define (chunked (text String)) (→ Syntax)
      (if (<= (string-length text) 8000)
          (StringSyntax text)
          (form "string-append"
                (map (lambda (start)
                       (StringSyntax (substring text (* start 8000) (min (string-length text) (* (+ start 1) 8000)))))
                     (iota (quotient (+ (string-length text) 7999) 8000))))))

    (define (shader-text (name String) (bytes Bytes)) (→ String)
      (match (compiling (lambda () (wgsl-text (read-text (utf8-text name bytes) name))))
        ((Ok text) text)
        ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))
        ((Err _) (panic (string-append "wgsl: shader " name " asked for a library")))))

    (define (utf8-text (name String) (bytes Bytes)) (→ String)
      (match (utf8->string bytes)
        ((Ok text) text)
        ((Err _) (panic (string-append "wgsl: shader " name " is not UTF-8")))))

    ;; The WGSL of a shader's forms, a declaration each.

    (define (wgsl-text (forms (List Source-syntax))) (→ String) (! compile)
      (string-join (map declaration forms) "\n"))

    ;; ---- Declarations ----

    (define (declaration (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Form (Cons (Ident "struct" _ _) (Cons name fields)) _)
         (string-concatenate
          (concatenate (list (list "struct " (identifier name) " {\n")
                             (map (lambda (field) (string-append "  " (binding field) ",\n"))
                                  fields)
                             (list "}\n")))))
        ((Form (Cons (Ident "fn" _ _) rest) loc) (function rest loc))
        ((Form (Cons (Ident "alias" _ _) (Cons name (Cons type (Nil)))) _)
         (string-append "alias " (identifier name) " = " (type-text type) ";\n"))
        ((Form (Cons (Ident "enable" _ _) (Cons name (Nil))) _)
         (string-append "enable " (identifier name) ";\n"))
        (_ (string-append (variable form "expected a declaration") ";\n"))))

    ;; `name (params) -> result { body }`, after its attributes.

    (define (function (items (List Source-syntax)) (loc Loc)) (→ String) (! compile)
      (let ((split (attributes items)))
        (match (● split second)
          ((Cons name (Cons (Form params _) rest))
           (let ((result (match rest
                           ((Cons (Form (Cons (Ident "->" _ _) result) _) body)
                            (new Pair
                              (first (string-append " -> " (attributed result loc)))
                              (second body)))
                           (body (new Pair (first "") (second body))))))
             (string-append (● split first)
                            "fn "
                            (identifier name)
                            "("
                            (string-join (map binding params) ", ")
                            ")"
                            (● result first)
                            " "
                            (block (● result second) "")
                            "\n")))
          (_ (compile-error loc
                            "expected (fn attribute ... name (parameter ...) [(-> type)] statement ...)")))))

    ;; Leading `(@name argument ...)` forms, printed, and the items after
    ;; them.

    (define (attributes (items (List Source-syntax)))
      (→ (Pair String (List Source-syntax)))
      (! compile)
      (match items
        ((Cons (Form (Cons (Ident name _ _) arguments) _) rest)
         (if (and (> (string-length name) 1) (char=? (string-ref name 0) #\@))
             (let ((more (attributes rest)))
               (new Pair (first (string-append (attribute name arguments) " " (● more first)))
                    (second (● more second))))
             (new Pair (first "") (second items))))
        (_ (new Pair (first "") (second items)))))

    (define (attribute (name String) (arguments (List Source-syntax))) (→ String) (! compile)
      (if (null? arguments)
          name
          (string-append name "(" (string-join (map expression arguments) ", ") ")")))

    ;; `attribute ... name type`, a field or parameter.

    (define (binding (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Form items loc)
         (let ((split (attributes items)))
           (match (● split second)
             ((Cons name (Cons type (Nil)))
              (string-append (● split first) (identifier name) ": " (type-text type)))
             (_ (compile-error loc "expected (attribute ... name type)")))))
        (_ (compile-error (syntax-loc form) "expected (attribute ... name type)"))))

    ;; `attribute ... type`, a result.

    (define (attributed (items (List Source-syntax)) (loc Loc)) (→ String) (! compile)
      (let ((split (attributes items)))
        (match (● split second)
          ((Cons type (Nil)) (string-append (● split first) (type-text type)))
          (_ (compile-error loc "expected (-> attribute ... type)")))))

    ;; `var`, `let`, `const` or `override`, or `(var space ...)`, then
    ;; attributes, a name or `(name type)`, and an initial value.

    (define (variable (form Source-syntax) (expected String)) (→ String) (! compile)
      (match form
        ((Form (Cons head items) loc)
         (let ((keyword (variable-keyword head expected)) (split (attributes items)))
           (match (● split second)
             ((Cons naming (Nil)) (string-append (● split first) keyword " " (typed naming)))
             ((Cons naming (Cons value (Nil)))
              (string-append (● split first) keyword " " (typed naming) " = " (expression value)))
             (_ (compile-error loc "expected a name or (name type), then a value")))))
        (_ (compile-error (syntax-loc form) expected))))

    (define (variable-keyword (head Source-syntax) (expected String)) (→ String) (! compile)
      (match head
        ((Ident name _ loc)
         (if (member? name (list "var" "let" "const" "override"))
             name
             (compile-error loc expected)))
        ((Form (Cons (Ident "var" _ _) space) _)
         (string-append "var<" (string-join (map identifier space) ", ") ">"))
        (_ (compile-error (syntax-loc head) expected))))

    (define (typed (naming Source-syntax)) (→ String) (! compile)
      (match naming
        ((Form (Cons name (Cons type (Nil))) _)
         (string-append (identifier name) ": " (type-text type)))
        (_ (identifier naming))))

    ;; ---- Statements ----

    ;; `{`, each statement on its own line one level in, and `}` at
    ;; `indent`.

    (define (block (statements (List Source-syntax)) (indent String)) (→ String) (! compile)
      (let ((inner (string-append indent "  ")))
        (string-concatenate
         (concatenate (list (list "{\n")
                            (map (lambda (statement)
                                   (string-append inner (statement-text statement inner) "\n"))
                                 statements)
                            (list indent "}"))))))

    (define (statement-text (form Source-syntax) (indent String)) (→ String) (! compile)
      (match form
        ((Form (Cons (Ident "return" _ _) (Nil)) _) "return;")
        ((Form (Cons (Ident "return" _ _) (Cons value (Nil))) _)
         (string-append "return " (expression value) ";"))
        ((Form (Cons (Ident "discard" _ _) (Nil)) _) "discard;")
        ((Form (Cons (Ident "break" _ _) (Nil)) _) "break;")
        ((Form (Cons (Ident "continue" _ _) (Nil)) _) "continue;")
        ((Form (Cons (Ident "if" _ _) clauses) loc) (conditional clauses indent loc))
        ((Form
          (Cons (Ident "for" _ _) (Cons (Form (Cons start (Cons test (Cons step (Nil)))) _) body))
          _)
         (string-append "for ("
                        (simple start)
                        "; "
                        (expression test)
                        "; "
                        (simple step)
                        ") "
                        (block body indent)))
        ((Form (Cons (Ident "while" _ _) (Cons test body)) _)
         (string-append "while " (expression test) " " (block body indent)))
        ((Form (Cons (Ident "loop" _ _) body) _) (string-append "loop " (block body indent)))
        ((Form (Cons (Ident "begin" _ _) body) _) (block body indent))
        (_ (string-append (simple form) ";"))))

    ;; A statement that can sit in a `for` header: a declaration, an
    ;; assignment or a call.

    (define (simple (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Form (Cons (Ident name _ _) (Cons place (Cons value (Nil)))) _)
         (if (member? name (list "=" "+=" "-=" "*=" "/=" "%="))
             (string-append (expression place) " " name " " (expression value))
             (simple-declaration form)))
        (_ (simple-declaration form))))

    (define (simple-declaration (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Form (Cons (Ident name _ _) _) _)
         (if (member? name (list "var" "let" "const"))
             (variable form "expected a statement")
             (expression form)))
        (_ (expression form))))

    ;; `if c { … } else if c { … } else { … }`.

    (define (conditional (clauses (List Source-syntax)) (indent String) (loc Loc))
      (→ String)
      (! compile)
      (match clauses
        ((Nil) (compile-error loc "expected (if (test statement ...) ... [(else statement ...)])"))
        ((Cons (Form (Cons (Ident "else" _ _) body) _) (Nil)) (block body indent))
        ((Cons (Form (Cons test body) _) (Nil))
         (string-append "if " (expression test) " " (block body indent)))
        ((Cons (Form (Cons test body) _) rest)
         (string-append "if "
                        (expression test)
                        " "
                        (block body indent)
                        " else "
                        (conditional rest indent loc)))
        ((Cons clause _) (compile-error (syntax-loc clause) "expected (test statement ...)"))))

    ;; ---- Expressions ----

    (define (expression (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Atom (DInt value) _) (i64->string value))
        ((Atom (DFloat text) _) text)
        ((Atom (DBool value) _) (if value "true" "false"))
        ((Atom _ loc) (compile-error loc "WGSL has no such literal"))
        ((Ident name _ _) name)
        ((Form (Cons (Ident "get" _ _) (Cons value (Cons name names))) _)
         (string-join (Cons (expression value) (map identifier (Cons name names))) "."))
        ((Form (Cons (Ident "at" _ _) (Cons value (Cons index (Nil)))) _)
         (string-append (expression value) "[" (expression index) "]"))
        ((Form (Cons (Ident name _ _) (Cons operand (Nil))) _)
         (match (unary name)
           ((Some operator) (string-append "(" operator (expression operand) ")"))
           ((None) (call name (list operand)))))
        ((Form (Cons (Ident name _ _) operands) _)
         (match (binary name)
           ((Some operator)
            (string-append "("
                           (string-join (map expression operands) (string-append " " operator " "))
                           ")"))
           ((None) (call name operands))))
        ((Form (Cons (Form template _) arguments) _)
         (call (type-text (Form template (syntax-loc form))) arguments))
        (_ (compile-error (syntax-loc form) "expected an expression"))))

    (define (call (callee String) (arguments (List Source-syntax))) (→ String) (! compile)
      (string-append callee "(" (string-join (map expression arguments) ", ") ")"))

    (define (unary (name String)) (→ (Option String))
      (cond ((string=? name "-") (Some "-"))
            ((string=? name "not") (Some "!"))
            ((string=? name "bit-not") (Some "~"))
            ((string=? name "address-of") (Some "&"))
            ((string=? name "deref") (Some "*"))
            (else (None))))

    (define (binary (name String)) (→ (Option String))
      (cond
       ((member? name (list "+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">=" "<<" ">>")) (Some name))
       ((string=? name "and") (Some "&&"))
       ((string=? name "or") (Some "||"))
       ((string=? name "bit-and") (Some "&"))
       ((string=? name "bit-or") (Some "|"))
       ((string=? name "bit-xor") (Some "^"))
       (else (None))))

    ;; ---- Types ----

    ;; A name, or `(T argument ...)` for `T<argument, ...>`.

    (define (type-text (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Ident name _ _) name)
        ((Atom (DInt value) _) (i64->string value))
        ((Form (Cons head arguments) _)
         (string-append (identifier head) "<" (string-join (map type-text arguments) ", ") ">"))
        (_ (compile-error (syntax-loc form) "expected a type"))))

    (define (identifier (form Source-syntax)) (→ String) (! compile)
      (match form
        ((Ident name _ _) name)
        (_ (compile-error (syntax-loc form) "expected a name"))))

    ))
