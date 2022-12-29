// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;

var ai_inference = function (x) {
    console.log('ai_inference called with: ', x);
    return x + 1;
}

let [wasm_js_hash, wasm_hash] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash, wasm_hash);

importScripts(`/cache/lib.min.js?hash=${wasm_js_hash}`);
declare var wasm_bindgen: any;

const { rpc_call, console_log_from_wasm } = wasm_bindgen;


/** Helps with typescript type checking. */
declare function postMessage(params: string);

function handleMessage(data: any) {
    console.log(`We got some data: ${data}`);
    let response: string = rpc_call(data.data);
    postMessage(response);
}

wasm_bindgen(`/cache/lib.wasm?hash=${wasm_hash}`).then(_ => {
    console.log('WASM loaded, worker ready.');
    console_log_from_wasm();
    // Notify the main thread that we are ready.
    // This then tells the message queue to start processing messages.
    postMessage('ready');
    onmessage = ev => handleMessage(ev)
});
