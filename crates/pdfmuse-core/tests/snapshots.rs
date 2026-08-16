//! Golden-corpus snapshot tests (M1 exit gate).
//!
//! Parses each fixture in `tests/corpus/` and snapshots the full IR. Coordinates
//! are rounded to a fixed precision before snapshotting so the golden output is
//! stable across platforms (the same discipline the cross-binding parity gate
//! will enforce in M2, PER-51). Update snapshots deliberately with
//! `cargo insta review` / `INSTA_UPDATE=always`.

use std::path::PathBuf;

use serde_json::Value;

fn corpus(name: &str) -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/corpus").join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Round every non-integer JSON number to 2 decimals, in place.
fn round_floats(v: &mut Value) {
    match v {
        Value::Number(n) => {
            if n.as_i64().is_none() && n.as_u64().is_none() {
                if let Some(f) = n.as_f64() {
                    let r = (f * 100.0).round() / 100.0;
                    if let Some(num) = serde_json::Number::from_f64(r) {
                        *n = num;
                    }
                }
            }
        }
        Value::Array(a) => a.iter_mut().for_each(round_floats),
        Value::Object(o) => o.values_mut().for_each(round_floats),
        _ => {}
    }
}

fn snapshot_json(name: &str) -> String {
    let doc = pdfmuse_core::parse(&corpus(name), None).expect("parse fixture");
    let mut value: Value = serde_json::to_value(&doc).expect("to_value");
    round_floats(&mut value);
    serde_json::to_string_pretty(&value).expect("to_string")
}

fn snapshot_markdown(name: &str) -> String {
    let doc = pdfmuse_core::parse(&corpus(name), None).expect("parse fixture");
    pdfmuse_core::to_markdown(&doc)
}

fn snapshot_chunks(name: &str) -> String {
    let doc = pdfmuse_core::parse(&corpus(name), None).expect("parse fixture");
    let mut value = serde_json::to_value(pdfmuse_core::chunk(&doc)).expect("to_value");
    round_floats(&mut value);
    serde_json::to_string_pretty(&value).expect("to_string")
}

#[test]
fn snapshot_hello_single_column() {
    insta::assert_snapshot!("hello", snapshot_json("hello.pdf"));
}

#[test]
fn snapshot_table_ruled() {
    insta::assert_snapshot!("table", snapshot_json("table.pdf"));
}

#[test]
fn snapshot_cjk_type0() {
    insta::assert_snapshot!("cjk", snapshot_json("cjk.pdf"));
}

/// Regression: a `/ToUnicode` that maps the space glyph to U+0001 (a real defect
/// from design-tool PDF writers) must extract as a space, not as a control
/// character and not as nothing — dropping the glyph glues the words together.
/// Fixture built by `tools/make_tounicode_fixture.py`.
#[test]
fn snapshot_tounicode_control() {
    let md = snapshot_markdown("tounicode_control.pdf");
    assert_eq!(md.trim(), "AB CD", "control-mapped space must become a real space");
    assert!(
        !md.chars().any(|c| (c as u32) < 0x20 && c != '\n' && c != '\t'),
        "no C0 control characters may reach the output"
    );
    insta::assert_snapshot!("tounicode_control", snapshot_json("tounicode_control.pdf"));
}

// --- M3: DOCX + output layer ---

#[test]
fn snapshot_docx_ir() {
    insta::assert_snapshot!("docx", snapshot_json("sample.docx"));
}

#[test]
fn snapshot_docx_markdown() {
    insta::assert_snapshot!("docx_md", snapshot_markdown("sample.docx"));
}

#[test]
fn snapshot_docx_chunks() {
    // Chunk metadata: heading_path + page; the table is a single chunk.
    insta::assert_snapshot!("docx_chunks", snapshot_chunks("sample.docx"));
}

#[test]
fn snapshot_table_markdown() {
    insta::assert_snapshot!("table_md", snapshot_markdown("table.pdf"));
}
