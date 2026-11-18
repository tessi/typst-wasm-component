"""Build the WASI component shipped in GitHub Releases."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
TARGET = "wasm32-wasip2"
FILENAME = "typst_wasm_component.wasm"
PATCH = ROOT / "patches" / "typst-library-disable-citations.patch"


def build(output: Path) -> None:
    target_dir = ROOT / os.environ.get("CARGO_TARGET_DIR", "target/lean-release")
    metadata = json.loads(
        subprocess.check_output(
            ["cargo", "metadata", "--locked", "--format-version", "1", "--filter-platform", TARGET],
            cwd=ROOT,
        )
    )
    libraries = [
        package for package in metadata["packages"]
        if package["name"] == "typst-library"
    ]
    if len(libraries) != 1:
        raise SystemExit("Expected exactly one locked typst-library package.")
    library_source = Path(libraries[0]["manifest_path"]).parent

    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".typst-release-", dir=output.parent) as staging:
        library = Path(staging) / "typst-library"
        shutil.copytree(library_source, library)
        with PATCH.open("rb") as patch:
            subprocess.run(
                ["patch", "-p1", "-F", "0", "-f", "-d", str(library)],
                stdin=patch,
                check=True,
            )

        subprocess.run(
            [
                "cargo", "build", "--locked", "--release", "--target", TARGET,
                "--target-dir", str(target_dir), "--config", f"paths={json.dumps([str(library)])}",
            ],
            cwd=ROOT,
            check=True,
        )
        raw_artifact = target_dir / TARGET / "release" / FILENAME
        artifact = Path(staging) / FILENAME
        # Jco runs Binaryen on the core modules and preserves the component wiring.
        subprocess.run(
            [
                "npm", "exec", "--yes", "--ignore-scripts",
                "--package=@bytecodealliance/jco@1.42.0", "--package=binaryen@132.0.0", "--",
                "jco", "opt", str(raw_artifact), "-o", str(artifact), "--",
                "-Oz", "--enable-bulk-memory", "--enable-bulk-memory-opt",
                "--enable-multivalue", "--enable-mutable-globals", "--enable-reference-types",
                "--enable-sign-ext", "--enable-nontrapping-float-to-int",
            ],
            cwd=ROOT,
            check=True,
        )
        artifact.replace(output)

    print(f"{output} ({output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=ROOT / "target" / "release-bundle" / FILENAME
    )
    build(parser.parse_args().output.resolve())
