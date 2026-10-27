;; Syntax a program builds for the compiler. A `generate-library` recipe
;; returns the `define-library` form of the library it generates as Syntax,
;; and its producer writes that form as bytes the compiler decodes, so no
;; text is printed or parsed in between and a byte vector travels as the
;; bytes it holds. Syntax here has no locations: the compiler places every
;; generated form at the recipe.
(define-library (snail-core syntax)
  (export
   Syntax
   ListSyntax
   SymbolSyntax
   IntegerSyntax
   FloatSyntax
   StringSyntax
   CharSyntax
   BooleanSyntax
   BytesSyntax
   form
   library-syntax
   syntax->bytes
   write-generated-library)
  (import
   (snail-core base)
   (snail-core io))
  (begin

    ;; ---- Syntax ----

    ;; A float keeps the text the reader would read, with a point or an
    ;; exponent, as the compiler's literals do.
    (enum Syntax
      (ListSyntax ((items (List Syntax))))
      (SymbolSyntax ((name String)))
      (IntegerSyntax ((value I64)))
      (FloatSyntax ((text String)))
      (StringSyntax ((value String)))
      (CharSyntax ((value Char)))
      (BooleanSyntax ((value Bool)))
      (BytesSyntax ((value Bytes))))

    ;; `(head item ...)`.
    (: form (-> String (List Syntax) Syntax))
    (define (form head items)
      (ListSyntax (Cons (SymbolSyntax head) items)))

    ;; The form a recipe returns: `(define-library (name ...) (export ...)
    ;; (import (library ...) ...) (begin definition ...))`.
    (: library-syntax (-> (List String) (List String) (List (List String)) (List Syntax) Syntax))
    (define (library-syntax name exports imports definitions)
      (let ((library-name (lambda (parts) (ListSyntax (map SymbolSyntax parts)))))
        (form "define-library"
              (list (library-name name) (form "export" (map SymbolSyntax exports)) (form "import" (map library-name imports))
                    (form "begin" definitions)))))

    ;; ---- Encoding ----

    ;; Each form is a tag byte and its contents:
    ;;
    ;;   0 list     a count, then that many forms
    ;;   1 symbol   a text
    ;;   2 number   a text the reader reads as an integer or a float
    ;;   3 string   a text
    ;;   4 char     a scalar's code
    ;;   5 #f, 6 #t
    ;;   7 bytes    a count, then that many bytes as they are
    ;;
    ;; A count or a code is unsigned, seven bits to a byte with the low bits
    ;; first, and the high bit set on every byte but the last. A text is a
    ;; count of scalars, then each scalar's code. src/snail-core/compiler/read.sld
    ;; decodes this.
    (: syntax->bytes (-> Syntax Bytes))
    (define (syntax->bytes syntax)
      (vector-concatenate (reverse (encode syntax (Nil)))))

    ;; The pieces of `syntax` before `pieces`, last first. A byte vector is
    ;; its own piece, so its bytes are copied only when the pieces join.
    (: encode (-> Syntax (List Bytes) (List Bytes)))
    (define (encode syntax pieces)
      (match syntax
        ((ListSyntax items) (fold-left (lambda (pieces item) (encode item pieces)) (Cons (counted 0 (length items)) pieces) items))
        ((SymbolSyntax name) (Cons (text-piece 1 name) pieces))
        ((IntegerSyntax value) (Cons (text-piece 2 (i64->string value)) pieces))
        ((FloatSyntax text) (Cons (text-piece 2 text) pieces))
        ((StringSyntax value) (Cons (text-piece 3 value) pieces))
        ((CharSyntax c) (Cons (counted 4 (char->integer c)) pieces))
        ((BooleanSyntax value) (Cons (list->vector (list (i32->u8 (if value 6 5)))) pieces))
        ((BytesSyntax bytes) (Cons bytes (Cons (counted 7 (vector-length bytes)) pieces)))))

    ;; A tag and one count.
    (: counted (-> I32 I64 Bytes))
    (define (counted tag count)
      (list->vector (Cons (i32->u8 tag) (count-bytes count))))

    ;; A tag and a text.
    (: text-piece (-> I32 String Bytes))
    (define (text-piece tag text)
      (list->vector (Cons (i32->u8 tag) (append (count-bytes (string-length text))
                                                (concatenate (map (lambda (c) (count-bytes (char->integer c))) (string->list text)))))))

    (: count-bytes (-> I64 (List U8)))
    (define (count-bytes count)
      (if (< count 128)
          (list (i32->u8 (i64->i32 count)))
          (Cons (i32->u8 (i64->i32 (+ 128 (remainder count 128)))) (count-bytes (quotient count 128)))))

    ;; ---- Producers ----

    ;; Writes the syntax a recipe returns to the file the driver names as
    ;; the producer's argument.
    (: write-generated-library (-> Syntax Unit ! fs))
    (define (write-generated-library syntax)
      (match (command-line)
        ((Cons _ (Cons path _)) (write-bytes path (syntax->bytes syntax)))
        (_ (panic "a producer writes its library to the path given as its argument"))))

    ))
