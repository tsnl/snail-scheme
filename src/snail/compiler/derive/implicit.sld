;; The names a derived instance is written with, as the implicit libraries
;; offer them: the classes Serialize and Deserialize and the functions
;; `encode`, `decode`, `encode-case-id`, `decode-case-id` and `case-id=?`
;; of (snail shell wire), and the primitives `unit` and `panic` of (snail
;; core primitive). A name is looked up in what the libraries export, a
;; later library's export hiding an earlier's, as in the scope the old
;; expander makes of their exports for the instances it derives. Those
;; libraries are source files someone may edit, so a name may be missing
;; or mean something else: each is found once, as what it means or as the
;; message the old expander gives where the instance uses it, which the
;; pass places.
(define-library (snail compiler derive implicit)
  (export
   WireNames
   wire-names)
  (import
   (snail core base)
   (only (snail compiler names globals) Global TopValue TopGlobal)
   (only (snail compiler expand offer) Offered Meaning Value TypeName ClassName))
  (begin

    ;; ---- Names ----

    (struct WireNames
      ((serialize (Result Global String))
       (deserialize (Result Global String))
       (encode (Result TopValue String))
       (decode (Result TopValue String))
       (encode-case-id (Result TopValue String))
       (decode-case-id (Result TopValue String))
       (case-id-equal (Result TopValue String))
       (unit (Result TopValue String))
       (panic (Result TopValue String))))

    ;; `offers` are the implicit libraries', in the order the old expander
    ;; loads them.
    (: wire-names (impl (Fn (List Offered) -> WireNames)))
    (define (wire-names offers)
      (WireNames (class-named offers "Serialize")
                 (class-named offers "Deserialize")
                 (value-named offers "encode")
                 (value-named offers "decode")
                 (value-named offers "encode-case-id")
                 (value-named offers "decode-case-id")
                 (value-named offers "case-id=?")
                 (value-named offers "unit")
                 (value-named offers "panic")))

    ;; ---- Meanings ----

    ;; What the last library to export `name` exports it as.
    (: offered (impl (Fn (List Offered) String -> (Option Meaning))))
    (define (offered offers name)
      (fold-left (lambda (found library)
                   (match (find (lambda (export) (string=? (::name export) name))
                                (::exports (::offer library)))
                     ((Some export) (Some (::meaning export)))
                     ((None) found)))
                 (None)
                 offers))

    ;; An instance's class, which its head names.
    (: class-named (impl (Fn (List Offered) String -> (Result Global String))))
    (define (class-named offers name)
      (match (offered offers name)
        ((Some (ClassName global)) (Ok global))
        (_ (Err "instance of something that is not a typeclass"))))

    ;; A function a body calls, or a struct, whose name is its
    ;; constructor. A deviation: a name that means syntax, a keyword or a
    ;; macro, which the old expander would expand in the call, is refused
    ;; as syntax used as a value.
    (: value-named (impl (Fn (List Offered) String -> (Result TopValue String))))
    (define (value-named offers name)
      (match (offered offers name)
        ((Some (Value value)) (Ok value))
        ((Some (TypeName global #t)) (Ok (TopGlobal global)))
        ((Some (TypeName _ #f)) (Err (string-append "a type is not a value: " name)))
        ((Some _) (Err (string-append "syntax used as a value: " name)))
        ((None) (Err (string-append "unbound identifier " name)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-implicit)
    (import
     (snail core table)
     (only (snail compiler expand offer) Offer Export TopScope Keyword)
     (snail stage0 testing))
    (begin
      (define (test-implicit)
        (let ((names (wire-names (list primitive wire))))
          (expect (::serialize names) (Ok (global wire-library "Serialize")))
          (expect (::encode names) (Ok (TopGlobal (global wire-library "encode"))))
          (expect (::unit names) (Ok (TopGlobal (global primitive-library "unit"))))
          (expect (::panic names) (Ok (TopGlobal (global wire-library "panic"))))
          (expect (::deserialize names) (Err "instance of something that is not a typeclass"))
          (expect (::decode names) (Err "unbound identifier decode"))
          (expect (::encode-case-id names) (Err "a type is not a value: encode-case-id"))
          (expect (::case-id-equal names) (Err "syntax used as a value: case-id=?")))
        (expect (::unit (wire-names (list))) (Err "unbound identifier unit")))

      (define primitive-library (list "prim"))

      (define wire-library (list "snail" "shell" "wire"))

      (define (global library name)
        (Global library name 0))

      (define (offer-of library exports)
        (Offered library (Offer exports (TopScope empty-table empty-table))))

      (define primitive
        (offer-of primitive-library
                  (list (Export "unit" (Value (TopGlobal (global primitive-library "unit"))))
                        (Export "panic" (Value (TopGlobal (global primitive-library "panic")))))))

      ;; A wire library that exports Deserialize as a function, a type as
      ;; `encode-case-id` and a keyword as `case-id=?`, and its own
      ;; `panic`, which hides the primitive.
      (define wire
        (offer-of wire-library
                  (list (Export "Serialize" (ClassName (global wire-library "Serialize")))
                        (Export "Deserialize" (Value (TopGlobal (global wire-library "d"))))
                        (Export "encode" (Value (TopGlobal (global wire-library "encode"))))
                        (Export "encode-case-id" (TypeName (global wire-library "E") #f))
                        (Export "case-id=?" (Keyword "if"))
                        (Export "panic" (Value (TopGlobal (global wire-library "panic")))))))))
   (else)))
