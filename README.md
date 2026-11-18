# Typst Wasm Component

This is a Wasm Component of [typst](https://typst.app) (0.15), the modern PDF creation toolset.
It includes an Elixir livebook for easy testing and example usage.

## Releases

Download `typst_wasm_component.wasm` and its SHA-256 checksum from
[GitHub Releases](https://github.com/tessi/typst-wasm-component/releases).
To publish a release, push a version tag such as `v0.1.0` on the commit to release.
CI builds and tests the component from that commit, then publishes the tested
binary and its checksum.

## Compilation

prepare by installing rust and the necessary targets:

```
rustup target add wasm32-wasip2
```

them compile the .wasm component with:

```
cargo build --target=wasm32-wasip2 --release
```

and find it under `target/wasm32-wasip2/release/typst_wasm_component.wasm`.
No `cargo component` needed: the bindings are generated from `wit/world.wit` by `wit_bindgen::generate!` at build time.

## Interface

See `wit/world.wit`:

* `compile-template(options)` takes the template source and fonts and returns a handle.
* `render-pdf(handle, data-json)` renders the template with `data-json` available as `sys.inputs` and returns the PDF bytes.
  Errors are readable, e.g. `error at main.typ:3:9: unclosed delimiter`.
* `free-template(handle)` drops a compiled template. Call it when a template is replaced, e.g. in an editor that recompiles on every change.
* The host implements `resolve-file(package, path)` to serve images, other `.typ` files and `@preview` packages.

Tested with [wasmex](https://github.com/tessi/wasmex) 0.16.1: the release build takes about 1s to load and renders the demo invoice in 35-65ms.

## End-to-end tests

Run the ExUnit suite with Elixir 1.18 or newer and Hex installed:

```sh
elixir test/component_e2e.exs
```

The suite loads the bundled WASM through Wasmex 0.16.1 and checks PDF rendering,
JSON inputs, font and file resolution, template cleanup, and error responses.
To test a fresh build, set `TYPST_COMPONENT_WASM` to its path.

## Usage

* open the livebook (assuming you have [installed livebook](https://livebook.dev))
* The "Define Typst Genserver" section implements an example Elixir GenServer that can use the typst wasm component and implement the elixir-side callbacks (e.g. to provide file system access)
* The "Define Typst Template and Data" livebook section defines two example document templates - choose the example you prefer. make sure the attached/references files of this livebook work (e.g. the font files). Note that in the following cell, we define custom variables as inputs to that template. If and how you use variables is up to you, they are not strictly necessary for this example, but serve as a nice example for production use cases. E.g. in production, we might want to have a fixed invoice template with all actual data being served as variables.
* The very last livebook cell renders a "Download PDF" button, which you can click to download your typst-rendered file.
