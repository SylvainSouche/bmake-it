---
schema_version: 2
id: 0f87-6aba-6cb7-af3b
alias: lasviewer-prereq-software-gap-obs
type: obs
status: recorded
origin: user, 2026-09-28: 'investigating a lasviewer project that was using glfw, gdal pdal and Dear ImGui and trying to use all that we added here for external dependancies, we ended up with the situation where some software can be added as fetched external modules either binary or source, but other couldn't and were just prerequisite that had to be installed before build. we have to add declaration and checks here'
created: 2026-09-28
generator: model.py/2.4.0
checksum: 1a4f775b56e5
---

# Building lasviewer (GLFW, GDAL, PDAL, Dear ImGui) against IMPORT=fetch:/fetch-bin:/FETCH_BUILD= found that not every external dependency can be acquired that way -- some are just system-level prerequisites (PROJ, GEOS, SQLite, curl, ...) that must already be installed, and a missing one currently surfaces as a cryptic failure deep inside a slow FETCH_BUILD=cmake configure instead of a clean upfront message

<!-- rationale, detail, alternatives considered -->
