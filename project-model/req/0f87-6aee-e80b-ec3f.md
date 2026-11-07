---
schema_version: 2
id: 0f87-6aee-e80b-ec3f
alias: path-characters-supported-req
type: req
status: confirmed
origin: user, 2026-11-07: what is tested to work is valid and must be supported and tested; what does not work on a platform is tested upfront, refused and explained, except cases evidently expected to work. Answers: a character that works somewhere must work everywhere; must-work set = space, parentheses, apostrophe, ampersand, hash (not comma)
created: 2026-11-07
rel_decided_by: [0f87-6aee-e80b-9d27]
generator: model.py/2.4.0
checksum: edb83d31c7e9
---

# A character that works on any tested platform is supported and tested on every platform

Supported in workspace, framework, module and parent-directory names: letters, digits and . _ - + @ % ~ ^ [ ] = and non-ASCII letters (= works under some bmake versions and must be made to work under all), and the evident set space ( ) ' & # (fixed; refused as 'not supported yet' until then). In the mk directory name also # ! : , = * ? { }. Braces are supported in workspace, framework and parent names. Case 116 builds and cleans each of them in each placement on every platform; a platform where one fails is an open gap in the case, not an accepted difference.
