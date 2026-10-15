# Reader timing launch dependency correction

The first reviewed campaign stopped before spawning any sample. The frozen
`matrix_port.py` process supervisor imports `data_ports.py`, which was absent
from its frozen directory. The old default check verified file identities but
did not import the supervisor. The complete failure, release, before/after host
snapshots and zero-sample campaign remain in `failed-launch/`.

This correction freezes the unchanged supervisor and its complete local import
closure (18 Python modules, 585,065 bytes), including deferred imports in
unrelated preparation functions. Only `matrix_port` and `data_ports` load for
supervision. Default verification checks their origins and the three callable
helper signatures before a sample can start. It does not change a guest,
input, workload clock, result predicate, sample order or exclusion. The original
[preparation plan](../2026-10-14-strict-reader-preparation/timing-plan.json) and
runner remain unchanged as the superseded launch attempt. The new plan retains
all 112 predetermined processes and starts in a new output directory only after
the parent's renewed quiet-window release.

The failed launch took no benchmark samples; the corrected complete campaign
is not a set of replacement samples. The original preparation archive remains
unchanged. This directory contains the small dependency and launch-record
supplement directly, with identities in the corrected plan.
