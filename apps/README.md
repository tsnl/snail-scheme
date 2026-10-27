# Applications

Each application is a project with an inert `project.datum`, a `main.sld`
program, its own libraries under `src/`, files including `index.html` under
`public/`, and tests. `snail build --release apps/NAME site` selects the `site`
target and packages it with the shared browser host from `host/browser` into
`apps/NAME/build/site`. `make site` builds both applications this way.

`./scripts/snail-tool serve apps/siegework` builds the same program one library at a
time into `build/serve/siegework`, serves it, and relinks each rebuilt
module into the open page, keeping its state. Hearsay, whose art comes from
`generate-library` recipes, serves the same way; its producers run in every
build.

| Application | Purpose |
| --- | --- |
| [Siegework](siegework/README.md) | A colony game: explore a seeded map, wire an energy network across it, and destroy three nests before their attacks destroy your hub. |
| [Hearsay](hearsay/README.md) | A design for a role-playing game that generates stories from what a city believes, with two prototypes. |
