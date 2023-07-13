// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;
declare function postMessage(params: any): void;

let [wasm_js_hash, wasm_hash] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash, wasm_hash);

importScripts(`/cache/lib.min.js?hash=${wasm_js_hash}`);
declare var wasm_bindgen: any;

const { rpc_call, generateRandomPosition, analyzePosition } = wasm_bindgen;


/** Helps with typescript type checking. */
declare function postMessage(params: string);

function handleMessage(message: any) {
    var data = message.data;
    console.log(`Worker handling message. Raw: ${message.data}, stringify: ${JSON.stringify(message.data)}`);

    // "generated" message broker
    if (data && data instanceof Object && data.type && data.data) {
        forwardToWasm(data.type, data.data);
    } else {
        // Existing "legacy" everything is in a wrapper struct solution.
        let response: string = rpc_call(data);
        postMessage(response);
    }
}

// TODO: This fake generated part needs to move to a separate file.
function forwardToWasm(messageType: any, data: any) {
    if (messageType === "generateRandomPosition") {
        generateRandomPosition(data);
    }
    if (messageType === "analyzePosition") {
        analyzePosition(data);
    }
}

// Allows the rust code to forward arbitrary messages to the main thread.
// This can be called from the rust code.
function forwardToMq(messageType: string, data: string) {
    console.log(`Forwarding message to main thread: ${messageType} ${data}`);
    postMessage({ type: messageType, data: data });
}

wasm_bindgen(`/cache/lib.wasm?hash=${wasm_hash}`).then(_ => {
    console.log('WASM loaded, worker ready.');
    // Notify the main thread that we are ready.
    // This then tells the message queue to start processing messages.
    postMessage('ready');
    onmessage = ev => handleMessage(ev)
});
