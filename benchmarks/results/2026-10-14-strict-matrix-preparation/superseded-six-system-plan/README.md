# Superseded before timing

These are the exact proposed six-system plan, runner, freezer, machine snapshot
and dry checks from preparation commit `7cf879e`. No campaign used this plan.

Parent review found that the native build further optimizes its Wasm input.
The selected production V8 module and the actual native-final module therefore
have different hashes. Their shared input did not establish an engine comparison
using identical final bytes. The replacement seven-system plan retains both V8
modules, freezes the final native build inputs and adds one full-count V8
correctness execution of that final module before timing. It uses one discarded
round plus seven balanced retained rounds, for 56 processes.
