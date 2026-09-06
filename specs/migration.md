# Migration report — specs/project-model

Detected schema: **legacy-grouped16+facets** -> v2

- objects: 196
- legacy edges read: 361
- v2 edges written: 258  (103 collapsed as stored inverses or duplicates)
- legacy relationship keys: 7 -> 5
- status changes: 0
- type renames: 0
- dangling targets dropped: 0
- edges degraded to informed_by (precision lost, noted in body): 1
- qualifier notes preserved in bodies: 1

## Degraded edges

- `6f38-6a91-03a8-6697`: legacy `refines` -> `informed_by` (target `6f38-6a88-1836-b9b1`)

## Reconciliation

- objects before 196, after 196
  - conserved: every id present before is present after
- legacy edges 361 = written 258 + collapsed 103 + dangling 0
  - accounted: buckets sum to the legacy total
- all 258 written edges resolve to existing objects
- every legacy pair still has a relation in at least one direction
- all 196 bodies byte-identical (notes appended only)
- degraded edges recorded in bodies: 1

**Reconciliation: PASS**
