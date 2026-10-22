# Applications

Each application is a directory with a `main.sld` program, its own libraries
under `src/`, an `index.html`, files to publish under `public/`, and tests.
`scripts/build-app.scm` compiles `main.sld` and packages it with the shared
browser host from `src/app`; `make site` runs it for both applications,
into `build/siegework` and `build/hearsay`.

`./lofi serve apps/siegework` builds the same program one library at a
time into `build/serve/siegework`, serves it, and relinks each rebuilt
module into the open page, keeping its state. It cannot build Hearsay yet,
whose art comes from `generate-library` recipes.

| Application | Purpose |
| --- | --- |
| [Siegework](siegework/README.md) | A colony game: explore a seeded map, wire an energy network across it, and destroy three nests before their attacks destroy your hub. |
| [Hearsay](hearsay/README.md) | A design for a role-playing game that generates stories from what a city believes, with two prototypes. |
