# Khronos glTF samples

`(khronos samples)` links the files of two Khronos repositories, which
`scripts/fetch-khronos-samples` fetches; neither is checked in, and
`models/` and `environments/` here are links into the clones it makes under
`build/`. None of these files are covered by the repository's Apache
license.

| Folder | Source | License |
| --- | --- | --- |
| `models/` | [glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), each model's `glTF/` variant | Each model's own, in `Models/MODEL/LICENSE.md` and `README.md` there (mostly CC-BY 4.0 or CC0) |
| `environments/` | [glTF-Sample-Environments](https://github.com/KhronosGroup/glTF-Sample-Environments), the `.hdr` panoramas | Each panorama's source, linked from that repository's README |

A program that imports `(khronos samples)` ships every file in its store,
and a page fetches a file only when the program reads it. Whoever
distributes such a build must credit the models and panoramas as their
licenses require.
