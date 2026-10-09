# TODO

- [x] CLI args parser
- [x] Parser and parser combinator
- [ ] Syntax
  - [x] Syntax
  - [ ] Syntax parser
    - [x] Parse most of Scheme
    - [x] Parse `#%-*` identifiers
  - [x] Syntax pattern matcher
- [ ] AST
  - [ ] Lexical scope context and phase-aware binding identities
  - [ ] AST build from syntax pattern matcher
  - [ ] Imports, exports, and lexical scoping
- [ ] Macro expansion
  - [ ] `syntax-rules` pattern/template engine
  - [ ] Design default errors for unbound `syntax-rules` literals and macros
    imported without their bound auxiliary keywords; relax these checks in
    strict R7RS mode
  - [ ] Macro expansion, `macro-expand-1`
  - [ ] Fully expand in context
    - [ ] Dispatch `#%-macro`, `#%-let-syntax`, and `#%-letrec-syntax`
    - [ ] Core binder regions and complete scope collection before body expansion
- [ ] Elaboration and type-checking
  - ...
