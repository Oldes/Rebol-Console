[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://app.gitter.im/#/room/#Rebol3:gitter.im)

# Rebol Console

A custom interactive REPL for [Rebol3](https://github.com/Oldes/Rebol3), built entirely in userspace. Provides a comfortable command-line editing experience without any external dependencies.

## Requirements

Rebol 3.21.12 or later.

## Known Limitations / Todo

- Grapheme clusters (e.g. 🏳️‍🌈) are not yet treated as single units
- Multiline input is not yet supported
- Tab completion rebuilds the word list on every call
- Cyclic completion (SHIFT+TAB) not yet implemented

## License

MIT