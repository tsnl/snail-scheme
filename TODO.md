# TODO

- [x] CLI args parser
- [x] Parser and parser combinator
- [ ] Syntax
  - [x] Syntax
  - [ ] Syntax parser
    - [x] Parse most of Scheme
    - [x] Parse `#%-*` identifiers
  - [x] Datum pattern matcher
- [ ] HIR
  - [x] Untyped, fully expanded Scheme records in `hir.sld`
  - [x] Transient scope environments passed through `expand.sld` recursive descent
  - [ ] Phase-aware resolution to shared definition identities
  - [x] HIR construction using the datum pattern matcher
  - [x] Basic imports, exports, and lexical scoping
  - [ ] Connect expansion to the command-line launcher
- [ ] Macro expansion
  - [x] Initial `syntax-rules` pattern/template engine
  - [x] Connect datum matching to source locations and literal binding lookup
  - [ ] Retain repetition-site extents in transformer plans, including empty
    and variable-free repetitions
  - [ ] Design default errors for unbound `syntax-rules` literals and macros
    imported without their bound auxiliary keywords; relax these checks in
    strict R7RS mode
  - [x] Single-step macro expansion, `macroexpand-1`
  - [x] Expand supported core forms in context
    - [x] Handle `define-syntax`, `let-syntax`, and `letrec-syntax`
    - [x] Reserve direct definitions and discover body bindings before expression construction
  - [ ] Broader R7RS conformance, including interacting macro-generated binders
- [ ] Inference, synthesis, and lowering
  - ...
