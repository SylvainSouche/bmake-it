---
schema_version: 2
id: 0f87-6ac0-d5dd-ded3
alias: platform-list-validity-req
type: req
status: confirmed
origin: user, 2026-10-03, design discussion (PLATFORMS=)
created: 2026-10-03
rel_decided_by: [0f87-6ac0-d592-a5b7]
rel_refines: [0f87-6ac0-d593-108a]
generator: model.py/2.4.0
checksum: d933bf6e9742
---

# In one PLATFORMS=/TOOLCHAINS= list, positive entries ('only these') and negative entries ('not these') are mutually exclusive, except that a negative entry may appear alongside positive ones when it is a SUBSET of some positive entry: 'linux -linux_arm64' is valid (linux_arm64 is one architecture of linux). A negative entry that is outside every positive entry ('macos -linux': redundant), equal to one ('linux -linux': empties the set) or wider than one ('linux_arm64 -linux') is a declaration error, always an error and never a skip, naming the offending entry. A platform entry os_arch is a subset of os; toolchains have no such hierarchy, so a TOOLCHAINS= list never mixes positive and negative entries. The '!' loud modifier does not affect validity

<!-- rationale, detail, alternatives considered -->
