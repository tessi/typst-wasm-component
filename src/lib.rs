#[allow(warnings)]
mod bindings;

use std::borrow::Cow;
use std::sync::Mutex;
use std::sync::LazyLock;

use bindings::Guest;
use serde_json::Value as JsonValue;
use typst::{
    diag::{FileError, FileResult, PackageError},
    foundations::{Bytes, Dict, FromValue, IntoValue, Value},
    syntax::{FileId, Source, package::PackageVersion},
};
use typst_as_lib::{
    TypstEngine, TypstTemplateMainFile,
    cached_file_resolver::{CachedFileResolver, IntoCachedFileResolver},
    file_resolver::FileResolver,
};
use typst_pdf::PdfOptions;

struct Component;
static TEMPLATES: LazyLock<Mutex<Vec<TypstEngine<TypstTemplateMainFile>>>> = LazyLock::new(|| {
    Mutex::new(Vec::new())
});

fn json_to_typst(val: JsonValue) -> Value {
    match val {
        JsonValue::Null => Value::None,
        JsonValue::Bool(b) => b.into_value(),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                (i as i32).into_value()
            } else if let Some(f) = n.as_f64() {
                f.into_value()
            } else {
                Value::None
            }
        }
        JsonValue::String(s) => s.into_value(),
        JsonValue::Array(arr) => arr
            .into_iter()
            .map(json_to_typst)
            .collect::<Vec<_>>()
            .into_value(),
        JsonValue::Object(map) => {
            let dict = map.into_iter().map(|(k, v)| (k.into(), json_to_typst(v)));
            Dict::from_iter(dict).into_value()
        }
    }
}

fn bytes_to_source(id: FileId, bytes: &[u8]) -> FileResult<Source> {
    // https://github.com/tfachmann/typst-as-library/blob/dd9a93379b486dc0a2916b956360db84b496822e/src/lib.rs#L78
    let contents = std::str::from_utf8(bytes).map_err(|_| FileError::InvalidUtf8)?;
    let contents = contents.trim_start_matches('\u{feff}');
    Ok(Source::new(id, contents.to_owned()))
}

struct WasmFileResolver;

impl WasmFileResolver {
    fn resolve_bytes(&self, id: FileId) -> FileResult<Vec<u8>> {
        let package_spec: Option<bindings::PackageSpec> = if let Some(package) = id.package() {
            let typst::syntax::package::PackageSpec {
                namespace,
                name,
                version,
            } = package;

            Some(bindings::PackageSpec {
                namespace: format!("{}", namespace),
                name: format!("{}", name),
                version: bindings::PackageVersion {
                    major: version.major,
                    minor: version.minor,
                    patch: version.patch,
                },
            })
        } else {
            None
        };

        let vpath = id.vpath().as_rootless_path().to_string_lossy().into_owned();
        bindings::resolve_file(package_spec.as_ref(), &vpath).map_err(|e| match e {
            bindings::FileError::NotFound(s) => FileError::NotFound(s.into()),
            bindings::FileError::AccessDenied => FileError::AccessDenied,
            bindings::FileError::IsDirectory => FileError::IsDirectory,
            bindings::FileError::NotSource => FileError::NotSource,
            bindings::FileError::InvalidUtf8 => FileError::InvalidUtf8,
            bindings::FileError::PackageError(package_error) => {
                typst::diag::FileError::Package(match package_error {
                    bindings::PackageError::NotFound(package_spec) => {
                        PackageError::NotFound(typst::syntax::package::PackageSpec {
                            namespace: package_spec.namespace.into(),
                            name: package_spec.name.into(),
                            version: PackageVersion {
                                major: package_spec.version.major,
                                minor: package_spec.version.minor,
                                patch: package_spec.version.patch,
                            },
                        })
                    }
                    bindings::PackageError::VersionNotFound((spec, version)) => {
                        PackageError::VersionNotFound(
                            typst::syntax::package::PackageSpec {
                                namespace: spec.namespace.into(),
                                name: spec.name.into(),
                                version: PackageVersion {
                                    major: spec.version.major,
                                    minor: spec.version.minor,
                                    patch: spec.version.patch,
                                },
                            },
                            PackageVersion {
                                major: version.major,
                                minor: version.minor,
                                patch: version.patch,
                            },
                        )
                    }
                    bindings::PackageError::NetworkFailed(s) => {
                        PackageError::NetworkFailed(s.map(|s| s.into()))
                    }
                    bindings::PackageError::MalformedArchive(s) => {
                        PackageError::MalformedArchive(s.map(|s| s.into()))
                    }
                    bindings::PackageError::Other(s) => PackageError::Other(s.map(|s| s.into())),
                })
            }
            bindings::FileError::Other(s) => FileError::Other(s.map(|s| s.into())),
        })
    }
}

impl IntoCachedFileResolver for WasmFileResolver {
    fn into_cached(self) -> CachedFileResolver<Self> {
        CachedFileResolver::new(self)
            .with_in_memory_source_cache()
            .with_in_memory_binary_cache()
    }
}

impl FileResolver for WasmFileResolver {
    fn resolve_binary(&self, id: FileId) -> typst::diag::FileResult<Cow<Bytes>> {
        let b = self.resolve_bytes(id)?;
        Ok(Cow::Owned(Bytes::new(b)))
    }

    fn resolve_source(&self, id: FileId) -> typst::diag::FileResult<Cow<Source>> {
        let file = self.resolve_bytes(id)?;
        let source = bytes_to_source(id, &file)?;
        Ok(Cow::Owned(source))
    }
}

impl Guest for Component {
    fn compile_template(
        options: bindings::RenderOptions,
    ) -> Result<bindings::TemplateHandle, String> {
        let file_resolver = WasmFileResolver;

        let template = TypstEngine::builder()
            .main_file(options.template.as_str())
            .fonts(options.fonts)
            .add_file_resolver(file_resolver)
            .build();
        let mut vec = TEMPLATES.lock().map_err(|_| "Failed to lock template vector")?;
        vec.push(template);
        Ok((vec.len() - 1) as bindings::TemplateHandle)
    }

    fn render_pdf(
        template_handle: bindings::TemplateHandle,
        data: String,
    ) -> Result<Vec<u8>, String> {
        let vec = TEMPLATES
            .lock()
            .map_err(|_| "Failed to lock template mutex")?;
        let template = vec
            .get(template_handle as usize)
            .ok_or("Invalid template handle")?;

        // log::debug!("Template built");

        let json_value = serde_json::from_str(&data).map_err(|e| e.to_string())?;
        let input_data = json_to_typst(json_value);
        let dict = Dict::from_value(input_data).unwrap();

        // log::debug!("Data parsed");

        let doc = template
            .compile_with_input(dict)
            .output
            .map_err(|e| e.to_string())?;

        // log::debug!("Template compiled");

        let pdf = typst_pdf::pdf(&doc, &PdfOptions::default()).map_err(|e| format!("{:?}", e))?;

        // log::debug!("PDF compiled");

        Ok(pdf)
    }
}

bindings::export!(Component with_types_in bindings);
