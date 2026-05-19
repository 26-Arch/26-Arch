# Core State Boundaries

This note documents the refactor that moved long-lived architectural state out of
[`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L1) and into dedicated modules.
The goal is not only shorter files, but also safer future changes: later labs
should add features by extending one boundary instead of editing the entire core.

## Why Earlier Labs Were Easy To Regress

Before this refactor, three kinds of logic lived in the same always block:

- front-end request / redirect control
- pipeline register movement
- architectural state commit

That meant a new feature such as CSR writes or trap handling naturally touched
the same block that also controlled fetch buffering, hazard recovery, and write
back timing. Even when the new feature was correct in isolation, it could still
shift commit timing or visible state and break earlier labs.

## New Boundaries

- [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L1)
  Owns fetch control, hazard policy, and movement of `id_r/ex_r/mem_r/wb_r`.
  It should answer: "which instruction is in which stage next cycle?"

- [`core_commit.sv`](/g:/Github/26-Arch/vsrc/src/core/core_commit.sv#L1)
  Owns architectural commit side effects. It updates GPR state, counters, halt
  state, and the latched trap report. It should answer: "what becomes visible at
  commit?"

- [`core_csr.sv`](/g:/Github/26-Arch/vsrc/src/core/core_csr.sv#L1)
  Owns CSR storage and CSR preview values for difftest. It should answer:
  "what is the committed CSR state, and what CSR value is visible this cycle?"

## Practical Rule For Future Work

When adding a feature, start by asking which boundary it belongs to:

- If it changes fetch, flush, bubble, stall, or redirect policy, edit `core.sv`.
- If it changes committed architectural state, edit `core_commit.sv`.
- If it adds or changes CSR semantics, edit `core_csr.sv`.

If one feature seems to require broad edits in all three places, that is a sign
we should introduce one more module boundary before continuing.

## Next Good Extraction Targets

- trap / exception entry and return sequencing
- interrupt eligibility and prioritization
- a dedicated front-end module if branch prediction or deeper fetch buffering is added
