# Node diagrams

The `.dot` files are the editable sources for the SVGs used by the
[node explanation](../nodes.md) and [runtime contracts](../runtime-contracts.md).
The book embeds SVGs so reading diagrams requires no JavaScript or external
diagram service.

From the repository root, regenerate them with Graphviz:

```sh
for source in doc/book/diagrams/*.dot; do
    dot -Tsvg "$source" -o "${source%.dot}.svg"
done
scripts/book build
```
