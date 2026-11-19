# Changelog

## v0.3.0

- Added `add-font` and `clear-fonts` to reuse parsed fonts across templates within one instance. Compile and validation calls with an empty font list use the registered fonts.

## v0.2.0

- Reduced the release component's size and startup time with size-optimized compilation and post-link optimization. The optimized component disables citations and bibliographies and supports ordinary document references.
- Added `validate-template` to check Typst source with supplied fonts and JSON inputs, returning structured errors and warnings without allocating a template handle or exporting a PDF.
- Updated Rust dependencies, including `typst-as-lib` 0.18.0, `rand` 0.8.8, and `time` 0.3.55, plus the Livebook's Kino dependency and GitHub Actions.

## v0.1.0

- Updated the component to Typst 0.15.1 and the Elixir example to Wasmex 0.16.1.
- Added `free-template` and updated the Livebook to release replaced templates.
- Restored Typst cache eviction after rendering and improved error messages for invalid templates and JSON inputs.
- Preserved signed 64-bit integers when passing JSON inputs to Typst.
- Added end-to-end tests and GitHub Actions CI. Version tags publish the tested WASM binary and its SHA-256 checksum.
