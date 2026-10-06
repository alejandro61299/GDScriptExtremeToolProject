# Changelog

## 0.2.0 — 2026-10-06

### Added

- **Actions on demand.** Press Alt+Enter (Option+Return on macOS) to open the actions at the caret, or use the new **Script Extreme Tools** submenu of the context menu. The script is analyzed only when that menu opens. The shortcut can be changed in Editor Settings > Shortcuts.
- **Generate Default Init Definition.** Creates `_init` with one parameter for each private variable of the class.
- **Generate Custom Init Definition...** Opens a dialog to choose the function name and the variables, with a preview of the signature and validation of the name.
- Setting `naming/alternative_init_function_name`.

### Changed

- "Generate Method Stub" is now "Generate Function Definition".
- Settings and member categories say "functions" instead of "methods": `format/blank_lines_around_functions_and_classes`, `public_functions`, `engine_functions` and so on. Values saved with the old names are ignored.
- Blank lines inside an inner class keep the indentation of the class, in generated code and in Format and Reorder.
- Format removes the blank lines right below the header of an inner class and after its last member, and no longer empties the indentation-only lines inside a function body.
- Generated functions take their blank lines from the format settings.

### Fixed

- A caret on an indented blank line now belongs to the class or function it is indented in.
- The names of global enums such as `Key` or `Error` are no longer offered as undefined identifiers.

## 0.1.0 — 2026-10-04

First release, internal. Code actions in the script editor's context menu: Generate Method Stub, Generate Local Variable, Generate Class Variable, Generate Connected Function, Reorder Class Members and Format Class Members, configured from Project Settings.
