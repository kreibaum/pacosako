// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;

let [wasm_js_hash_lib, wasm_hash_lib] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash_lib, wasm_hash_lib);

importScripts(`/cache/lib.min.js?hash=${wasm_js_hash_lib}`);
declare var wasm_bindgen: any;

const { rpc_call } = wasm_bindgen;


/** Helps with typescript type checking. */
declare function postMessage(params: string);

function handleLibMessage(data: any) {
    console.log(`We got some data: ${data}`);
    let response: string = rpc_call(data.data);
    postMessage(response);
}

wasm_bindgen(`/cache/lib.wasm?hash=${wasm_hash_lib}`).then(_ => {
    console.log('WASM loaded, worker ready.');
    onmessage = ev => handleLibMessage(ev)
    // Notify the main thread that we are ready.
    // This then tells the message queue to start processing messages.
    postMessage('ready');
});
