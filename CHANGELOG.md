# Changelog

## v0.1.0

- Updated the component to Typst 0.15.1 and the Elixir example to Wasmex 0.16.1.
- Added `free-template` and updated the Livebook to release replaced templates.
- Restored Typst cache eviction after rendering and improved error messages for invalid templates and JSON inputs.
- Preserved signed 64-bit integers when passing JSON inputs to Typst.
- Added end-to-end tests and GitHub Actions CI. Version tags publish the tested WASM binary and its SHA-256 checksum.
