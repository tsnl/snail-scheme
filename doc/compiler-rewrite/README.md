# Working notes for the compiler rewrite

This folder exists so that the state of the rewrite on the branch
`factor/compiler-passes` (draft PR #744) is on GitHub and not only in one
checkout. It goes away when the rewrite lands.

The specification is the book chapter
[`doc/book/snail-core/passes.md`](../book/snail-core/passes.md): the pass
table, the vocabulary, the layout, the import rule, the conventions, the
grammars and the list of known differences from the old compiler. What is
here is narrower: where the work stands, and the designs of the parts not
built yet.

- [`STATE.md`](STATE.md): where the work stands, what is verified, what
  comes next, and the owner's decisions that the designs below predate.
- [`typed/`](typed/): the design of the typed half, `infer` to `confine`,
  not started. `design.md`, `inventory.md` (every behavior of the old
  checker), and drafts of its first and last languages. The drafts end in
  `.txt` so that no tool reads them as source.
- [`milestone-a/`](milestone-a/): the design of the switch of the default
  compile path to the new front end. Its adapter and the integrator's
  producers are built; the switch itself, sessions, the build planner and
  the book are not.
- [`dispatch/`](dispatch/) and [`declare/`](declare/): the designs and
  inventories those passes were built from. Both are implemented; they
  are kept for the inventories, which say where the old compiler's order
  of checks is reproduced and why.

Each design was written before some later decisions. Where `STATE.md` and
a design disagree, `STATE.md` is right; where `passes.md` and either
disagree about what is implemented, `passes.md` and the code are right.
