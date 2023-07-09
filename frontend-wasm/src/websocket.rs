//! This module implements a WebSocket client and proxy that lives in the
//! web worker and communicates with the server as well as the main Elm application.

use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys;
use web_sys::{MessageEvent, WebSocket, WorkerGlobalScope};

#[wasm_bindgen]
pub fn start_websocket(uuid: &str) -> Result<(), JsValue> {
    println!("Starting websocket with uuid: {}", uuid);

    // TODO: Implement Gitpod verion of this.
    // TODO: Implement Hosted version of this.

    // Get the global scope
    let global_scope = js_sys::global().dyn_into::<WorkerGlobalScope>()?;

    // Get the location
    let location = global_scope.location();

    // Get the href property
    let href = location.href();

    // Print it out
    web_sys::console::log_1(&"Hello from Rust!".into());
    web_sys::console::log_1(&JsValue::from_str(&href));

    Ok(())
}
