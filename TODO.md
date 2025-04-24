# TODO

- replace js-yaml with a more reliable and modern alternative
- use class for global secretProps handling rather than passing them as attributes
- op session and chosen env variables' persistence (local vault)
- retain only several backup instances (like 5 by default?) of each file, no need to clutter fs too much
- validate profile presence before trying to access 1password vault
- decouple profile names from profile output file name specifier: do not depend on the name, use `files` object instead that would declare MULTILPLE files that profile covers (currently only one that is in the name!)
