# Typst Wasm Component

This is a Wasm Component of [typst](https://typst.app) (0.15), the modern PDF creation toolset.
It includes an Elixir livebook for easy testing and example usage.

## Releases

Download `typst_wasm_component.wasm` and its SHA-256 checksum from
[GitHub Releases](https://github.com/tessi/typst-wasm-component/releases).
To publish a release, push a version tag such as `v0.1.0` on the commit to release.
CI builds and tests the optimized component from that commit, then publishes
the tested WASM file and its checksum.

The release build supports document references such as `@section`. Citation
and bibliography calls return a Typst diagnostic explaining that they are
disabled.

## Compilation

Install the `wasm32-wasip2` Rust target, then run the release build with
Python 3, `patch`, and Node.js 24 available.

```sh
rustup target add wasm32-wasip2
python3 scripts/build-release.py
```

The script writes `target/release-bundle/typst_wasm_component.wasm`.
It applies the [citation patch](patches/typst-library-disable-citations.patch)
to a temporary copy of the locked Typst library, builds with Rust's size
profile, and optimizes the component with Jco and Binaryen. When upgrading
Typst, refresh the patch if the affected source has changed.

A plain Cargo build uses upstream Typst with citation support and writes the
component to `target/wasm32-wasip2/release/typst_wasm_component.wasm`.
The build generates bindings from `wit/world.wit` with `wit-bindgen`.

```sh
cargo build --locked --target wasm32-wasip2 --release
```

## Interface

See `wit/world.wit`:

* `compile-template(options)` takes the template source and fonts and returns a handle.
* `validate-template(options, data-json)` checks the source directly and returns structured diagnostics.
* `render-pdf(handle, data-json)` renders the template with `data-json` available as `sys.inputs` and returns the PDF bytes.
  Errors are readable, e.g. `error at main.typ:3:9: unclosed delimiter`.
* `free-template(handle)` drops a compiled template. Call it when a template is replaced, e.g. in an editor that recompiles on every change.
* The host implements `resolve-file(package, path)` to serve images, other `.typ` files and `@preview` packages.

Tested with [Wasmex](https://github.com/tessi/wasmex) 0.16.1.

## End-to-end tests

Run the ExUnit suite with Elixir 1.18 or newer and Hex installed:

```sh
elixir test/component_e2e.exs
```

The suite loads the bundled WASM through Wasmex 0.16.1 and checks PDF rendering,
JSON inputs, fonts, file resolution, template cleanup, and diagnostics. To test
a fresh release build, set `TYPST_COMPONENT_WASM` to its path.

## Usage

Run from the repository root with `elixir example.exs`:

```elixir
Mix.install([{:wasmex, "0.16.1"}])

alias Wasmex.Components

{:ok, pid} =
  Components.start_link(
    bytes: File.read!("files/typst_wasm_component.wasm"),
    wasi: struct(Wasmex.Wasi.WasiP2Options),
    imports: %{"resolve-file" => {:fn, fn _, path -> {:error, {:"not-found", path}} end}}
  )

font = File.read!("demo/OpenSans-Regular.ttf") |> :binary.bin_to_list()

{:ok, {:ok, handle}} =
  Components.call_function(pid, "compile-template", [
    %{template: "#set text(font: \"Open Sans\")\nHello, #sys.inputs.name!", fonts: [font]}
  ], 30_000)

{:ok, {:ok, pdf}} =
  Components.call_function(pid, "render-pdf", [handle, ~s({"name":"Ada"})], 30_000)

File.write!("hello.pdf", pdf)
{:ok, true} = Components.call_function(pid, "free-template", [handle])
```

### Validate a template

```elixir
{:ok, {:ok, diagnostics}} =
  Components.call_function(pid, "validate-template", [
    %{template: "Title\n#(1 + 2", fonts: [font]},
    "{}"
  ], 30_000)

valid? = Enum.all?(diagnostics, fn diagnostic ->
  Map.get(diagnostic, :severity, diagnostic["severity"]) != :error
end)
```

Validation runs Typst evaluation and layout with the supplied JSON object, fonts,
and file resolver. Use `"{}"` if the document has no inputs. A clean document
returns `[]` and warnings alone still allow compilation. Invalid JSON or setup
failures return an inner `{:error, reason}`. Validation skips PDF export.

Each diagnostic has a severity, a message, hints, and an optional location
with a file and 1-based line and column. Wasmex exposes locations as
`{:some, location}` or `:none`. Version 0.16.1 uses atom keys when the atoms
already exist in the VM and string keys otherwise. The example handles both.
