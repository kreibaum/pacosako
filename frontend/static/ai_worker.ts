// Implements the Web Worker for the AI.
// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;

var ai_inference = function (x) {
    console.log('ai_inference called with: ', x);
    return x + 1;
}

let [wasm_js_hash_ai, wasm_hash_ai] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash_ai, wasm_hash_ai);

importScripts(`/cache/lib.min.js?hash=${wasm_js_hash_ai}`);
declare var wasm_bindgen: any;

const { request_ai_action, console_log_from_wasm } = wasm_bindgen;


/** Helps with typescript type checking. */
declare function postMessage(params: string);

function handleAiMessage(data: any) {
    console.log(`We got an AI request: ${data}`);
    let response: string = request_ai_action(data.data);
    postMessage(response);
}

wasm_bindgen(`/cache/lib.wasm?hash=${wasm_hash_ai}`).then(_ => {
    console.log('WASM loaded, AI worker ready.');
    console_log_from_wasm();
    onmessage = ev => handleAiMessage(ev)
    // Notify the main thread that we are ready.
    // This then tells the message queue to start processing messages.
    postMessage('ready');
});
