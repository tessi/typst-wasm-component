Mix.install([{:wasmex, "0.16.1"}])

ExUnit.start()

defmodule TypstComponentE2ETest do
  use ExUnit.Case

  alias Wasmex.Components
  alias Wasmex.Wasi.WasiP2Options

  @demo Path.expand("../demo", __DIR__)
  @bundled_component Path.expand("../files/typst_wasm_component.wasm", __DIR__)
  @package %{
    namespace: "preview",
    name: "invoice-maker",
    version: %{major: 1, minor: 1, patch: 0}
  }
  @document """
  #import "@preview/invoice-maker:1.1.0": invoice
  #assert(type(invoice) == function)
  #assert.eq(sys.inputs.amount, 3000000000)
  #assert.eq(sys.inputs.customer.name, "Ada")
  #set text(font: "Open Sans")
  = #sys.inputs.customer.name
  #image("signature.png", width: 20mm)
  """

  setup do
    %{component: start_component(:primary)}
  end

  defp start_component(id) do
    test_pid = self()
    path = System.get_env("TYPST_COMPONENT_WASM", @bundled_component)

    start_supervised!(
      Supervisor.child_spec(
        {Components,
         bytes: File.read!(path),
         wasi: %WasiP2Options{},
         imports: %{
           "resolve-file" =>
             {:fn,
              fn package, path ->
                send(test_pid, {:resolve_file, package, path})
                resolve_file(package, path)
              end}
         }},
        id: id
      )
    )
  end

  test "renders a PDF with JSON inputs, an uploaded font, an image, and a local package", %{
    component: component
  } do
    font = File.read!(Path.join(@demo, "OpenSans-Regular.ttf")) |> :binary.bin_to_list()
    handle = compile(component, @document, [font])
    data = JSON.encode!(%{amount: 3_000_000_000, customer: %{name: "Ada"}})

    assert {:ok, {:ok, bytes}} = call(component, "render-pdf", [handle, data])
    pdf = IO.iodata_to_binary(bytes)
    assert <<"%PDF-", _rest::binary>> = pdf
    assert String.ends_with?(String.trim_trailing(pdf, "\n"), "%%EOF")
    assert_received {:resolve_file, :none, "signature.png"}
    assert_received {:resolve_file, {:some, @package}, "typst.toml"}
    assert_received {:resolve_file, {:some, @package}, "lib.typ"}

    without_font = compile(component, @document)
    assert {:ok, {:ok, fallback_bytes}} = call(component, "render-pdf", [without_font, data])
    assert pdf_fonts(pdf) != pdf_fonts(IO.iodata_to_binary(fallback_bytes))
  end

  test "renders the same PDF with registered fonts and keeps existing handles after clearing", %{
    component: component
  } do
    font = File.read!(Path.join(@demo, "OpenSans-Regular.ttf")) |> :binary.bin_to_list()
    data = JSON.encode!(%{amount: 3_000_000_000, customer: %{name: "Ada"}})

    explicit = compile(component, @document, [font])
    assert {:ok, {:ok, expected}} = call(component, "render-pdf", [explicit, data])

    assert {:ok, {:ok, 1}} = call(component, "add-font", [font])

    assert {:ok, {:error, "Font file contains no usable faces"}} =
             call(component, "add-font", [[1, 2, 3]])

    shared = compile(component, @document)
    assert {:ok, {:ok, ^expected}} = call(component, "render-pdf", [shared, data])

    assert {:ok, []} = call(component, "clear-fonts", [])
    assert {:ok, {:ok, ^expected}} = call(component, "render-pdf", [shared, data])

    without_font = compile(component, @document)
    assert {:ok, {:ok, fallback}} = call(component, "render-pdf", [without_font, data])
    assert pdf_fonts(IO.iodata_to_binary(expected)) != pdf_fonts(IO.iodata_to_binary(fallback))
  end

  test "validates with instance-specific fonts and allows explicit per-call overrides", %{
    component: component
  } do
    open_sans = File.read!(Path.join(@demo, "OpenSans-Regular.ttf")) |> :binary.bin_to_list()
    fira_math = File.read!(Path.join(@demo, "FiraMath-Regular.otf")) |> :binary.bin_to_list()
    template = ~s[#set text(font: "Open Sans")\nHello]
    missing_font = "unknown font family: open sans"

    assert {:ok, {:ok, [%{severity: :warning, message: ^missing_font}]}} =
             validate(component, template)

    assert {:ok, {:ok, 1}} = call(component, "add-font", [open_sans])
    assert {:ok, {:ok, 1}} = call(component, "add-font", [fira_math])
    assert {:ok, {:ok, []}} = validate(component, template)
    assert {:ok, {:ok, []}} = validate(component, ~s[#set text(font: "Fira Math")\nHello])

    assert {:ok, {:ok, [%{severity: :warning, message: ^missing_font}]}} =
             call(component, "validate-template", [
               %{template: template, fonts: [fira_math]},
               "{}"
             ])

    second = start_component(:secondary)

    assert {:ok, {:ok, [%{severity: :warning, message: ^missing_font}]}} =
             validate(second, template)

    assert {:ok, {:ok, []}} = validate(component, template)
  end

  test "frees a template and leaves other handles usable", %{component: component} do
    first = compile(component, "#rect(width: 10mm, height: 10mm)")
    second = compile(component, "#circle(radius: 5mm)")

    assert first != second
    assert {:ok, true} = call(component, "free-template", [first])
    assert {:ok, false} = call(component, "free-template", [first])

    assert {:ok, {:error, "Invalid template handle"}} =
             call(component, "render-pdf", [first, "{}"])

    assert {:ok, {:ok, _pdf}} = call(component, "render-pdf", [second, "{}"])
  end

  test "rejects citations and bibliographies without disabling document references", %{
    component: component
  } do
    disabled = "citations and bibliographies are disabled in this component"

    for template <- ["#cite(<external-work>)", ~s[#bibliography("works.bib")]] do
      assert {:ok, {:ok, [%{severity: :error, message: ^disabled}]}} =
               validate(component, template)
    end

    refute_received {:resolve_file, :none, "works.bib"}

    font = File.read!(Path.join(@demo, "OpenSans-Regular.ttf")) |> :binary.bin_to_list()

    handle =
      compile(
        component,
        """
        #set text(font: "Open Sans")
        #set heading(numbering: "1.")
        = Project <project>
        See @project.
        """,
        [font]
      )

    assert {:ok, {:ok, ~c"%PDF-" ++ _}} = call(component, "render-pdf", [handle, "{}"])
  end

  test "returns errors for invalid JSON, invalid Typst, and missing files", %{
    component: component
  } do
    valid = compile(component, "#rect(width: 10mm, height: 10mm)")
    assert {:ok, {:error, message}} = call(component, "render-pdf", [valid, "{"])
    assert message =~ "line 1"

    assert {:ok, {:error, "data-json must be a JSON object"}} =
             call(component, "render-pdf", [valid, "[]"])

    invalid = compile(component, "#(1 + 2")
    assert {:ok, {:error, diagnostic}} = call(component, "render-pdf", [invalid, "{}"])
    assert diagnostic =~ ~r/error at .+:1:\d+/
    assert diagnostic =~ "unclosed delimiter"

    missing = compile(component, ~s[#image("missing.png")])
    assert {:ok, {:error, diagnostic}} = call(component, "render-pdf", [missing, "{}"])
    assert diagnostic =~ "missing.png"
    assert_received {:resolve_file, :none, "missing.png"}
    assert {:ok, {:ok, _pdf}} = call(component, "render-pdf", [valid, "{}"])
  end

  test "validates with the same inputs, fonts, project files, and packages as rendering", %{
    component: component
  } do
    font = File.read!(Path.join(@demo, "OpenSans-Regular.ttf")) |> :binary.bin_to_list()
    options = %{template: @document, fonts: [font]}
    data = JSON.encode!(%{amount: 3_000_000_000, customer: %{name: "Ada"}})

    assert {:ok, {:ok, []}} = call(component, "validate-template", [options, data])
    assert_received {:resolve_file, :none, "signature.png"}
    assert_received {:resolve_file, {:some, @package}, "typst.toml"}
    assert_received {:resolve_file, {:some, @package}, "lib.typ"}

    assert {:ok, {:ok, [%{severity: :error, message: message}]}} =
             call(component, "validate-template", [options, "{}"])

    assert message =~ ~s(dictionary does not contain key "amount")

    assert {:ok, {:error, "data-json must be a JSON object"}} =
             call(component, "validate-template", [options, "[]"])

    assert {:ok, {:error, message}} = call(component, "validate-template", [options, "{"])
    assert message =~ "line 1"
  end

  test "returns syntax and layout errors, warnings, and hints from included files", %{
    component: component
  } do
    assert {:ok,
            {:ok,
             [
               %{
                 severity: :error,
                 message: "unclosed delimiter",
                 location: {:some, %{file: "main.typ", line: 2, column: 2}},
                 hints: []
               }
             ]}} = validate(component, "Title\n#(1 + 2")

    assert {:ok, {:ok, [%{severity: :error, message: "assertion failed: layout failed"}]}} =
             validate(component, ~s/#context assert(false, message: "layout failed")/)

    assert {:ok, {:ok, [%{severity: :warning, message: "unknown font family: missingfont123"}]}} =
             validate(component, ~s/#set text(font: "MissingFont123")\nHello/)

    assert {:ok,
            {:ok,
             [
               %{
                 severity: :error,
                 message: "unknown variable: unknown-name",
                 location: {:some, %{file: "chapter.typ", line: 1, column: 2}},
                 hints: [hint]
               }
             ]}} = validate(component, ~s/#include "chapter.typ"/)

    assert hint =~ "unknown - name"
    assert_received {:resolve_file, :none, "chapter.typ"}
    refute_received {:resolve_file, :none, "chapter.typ"}

    assert {:ok, {:ok, [%{severity: :error}]}} = validate(component, ~s/#include "chapter.typ"/)
    assert_received {:resolve_file, :none, "chapter.typ"}
  end

  defp validate(component, template) do
    call(component, "validate-template", [%{template: template, fonts: []}, "{}"])
  end

  defp compile(component, template, fonts \\ []) do
    assert {:ok, {:ok, handle}} =
             call(component, "compile-template", [%{template: template, fonts: fonts}])

    handle
  end

  defp call(component, function, args),
    do: Components.call_function(component, function, args, 30_000)

  defp pdf_fonts(pdf) do
    Regex.scan(~r{/BaseFont\s*/(?:[A-Z]+\+)?([^\s/<>\[\]]+)}, pdf, capture: :all_but_first)
  end

  defp resolve_file(:none, "chapter.typ"), do: {:ok, ~c"#unknown-name"}
  defp resolve_file(:none, path), do: read_fixture(path)

  defp resolve_file({:some, @package}, path) do
    read_fixture(Path.join("preview/invoice-maker-1.1.0", path))
  end

  defp resolve_file({:some, _unknown_package}, path), do: not_found(path)

  defp read_fixture(path) do
    case File.read(Path.join(@demo, path)) do
      {:ok, bytes} -> {:ok, :binary.bin_to_list(bytes)}
      {:error, :enoent} -> not_found(path)
    end
  end

  defp not_found(path), do: {:error, {:"not-found", path}}
end
