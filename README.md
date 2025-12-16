# Typst Wasm Component

This is a Wasm Component of [typst](), the modern PDF creation toolset.
It includes an Elixir livebook for easy testing and example usage.

## Compilation

prepare by installing rust and the necessary targets:

´´´
rustup target add wasm32-wasip2
´´´

them compile the .wasm component with:

´´´
cargo build --target=wasm32-wasip2 --release
´´´

and find it under ´target/wasm32-wasip2/release/typst_wasm_component.wasm´.

## Usage

* open the livebook (assuming you have [installed livebook](https://livebook.dev))
* The "Define Typst Genserver" section implements an example Elixir GenServer that can use the typst wasm component and implement the elixir-side callbacks (e.g. to provide file system access)
* The "Define Typst Template and Data" livebook section defines two example document templates - choose the example you prefer. make sure the attached/references files of this livebook work (e.g. the font files). Note that in the following cell, we define custom variables as inputs to that template. If and how you use variables is up to you, they are not strictly necessary for this example, but serve as a nice example for production use cases. E.g. in production, we might want to have a fixed invoice template with all actual data being served as variables.
* The very last livebook cell renders a "Download PDF" button, which you can click to download your typst-rendered file.
