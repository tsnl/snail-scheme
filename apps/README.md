# Applications

Applications are named browser targets in the repository's root
`project.datum`. Each application directory has a `main.sld` program, its own
libraries under `src/`, files including `index.html` under `public/`, and tests.
From the repository root, `./snail build --release . NAME` selects an application
and packages it with the shared browser host from `host/browser` into
`build/NAME`. `make site` builds both applications this way.

`./snail dev .` opens the whole repository in the browser editor, builds both
applications one library at a time into `build`, and serves them at
<http://127.0.0.1:8001/siegework/> and <http://127.0.0.1:8001/hearsay/>. It relinks
each rebuilt module into the open page, keeping its state. Hearsay's art comes
from `generate-library` recipes; its producers run in every build.

| Application | Purpose |
| --- | --- |
| [Siegework](siegework/README.md) | A colony game: explore a seeded map, wire an energy network across it, and destroy three nests before their attacks destroy your hub. |
| [Hearsay](hearsay/README.md) | A design for a role-playing game that generates stories from what a city believes, with two prototypes. |
