# Applications

Each application is a script, `src/apps/NAME/main.scm`, that hands its
functions to an engine's loop ([application model](../../doc/book/snail-scheme/applications.md)).
Its libraries live beside it, named `(apps NAME ...)`, with its `public/`
files, including `index.html`; its tests are in `tests/NAME/`. From the
repository root, `./snail-scheme build --release --target browser
src/apps/NAME/main.scm` packages it with the shared browser host from
`host/browser` into `build/src/apps/NAME/main`. `make site` builds both
applications this way.

Any static HTTP server serves an application's output directory. Hearsay's art
comes from `generate-library` recipes; its producers run in every build.

| Application | Purpose |
| --- | --- |
| [Siegework](siegework/README.md) | A colony game: explore a seeded map, wire an energy network across it, and destroy three nests before their attacks destroy your hub. |
| [Hearsay](hearsay/README.md) | A design for a role-playing game that generates stories from what a city believes, with two prototypes. |
