//! Provides various Paco Ŝako function for use in Python.
//! Note that while the Julia module focuses on supporting AI training and evaluation,
//! this Python module is designed to support for various statistical analysis tasks.
//!
//! The Python module is implemented using the PyO3 library.
//! https://pyo3.rs/
//!
//! (Re-)compile using
//! ```shell
//! maturin develop
//! ```

use pyo3::prelude::*;


/// Formats the sum of two numbers as string.
#[pyfunction]
fn sum_as_string(a: usize, b: usize) -> PyResult<String> {
    Ok((a + b).to_string())
}

/// A Python module implemented in Rust.
#[pymodule]
fn pypacosako(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(sum_as_string, m)?)?;
    Ok(())
}
