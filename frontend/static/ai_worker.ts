// Implements the Web Worker for the AI.
// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;

// Import the ONNX runtime.
// ONNX interaction is adapted from
// https://github.com/microsoft/onnxruntime-inference-examples/blob/main/js/quick-start_onnxruntime-web-script-tag/index.html
importScripts('https://cdn.jsdelivr.net/npm/onnxruntime-web@1.13.1/dist/ort.min.js');
declare var ort: any;
console.log('onnxruntime-web loaded');

// The ONNX model session as a global variable.
// Since the worker is encapsulated, we don't have to be particularly clean.
let ort_session: any = null;

async function load_model() {
    // Load the ONNX model.
    ort_session = await ort.InferenceSession.create('/cache/models/ludwig-1.onnx', { executionProviders: ["webgl"] });
    console.log('ONNX model loaded');
}

// The inference function. Needs to be async, because the inference is done on
// the GPU. WebGL is async.
async function ai_inference(input: Float32Array): Promise<Float32Array> {
    console.log('AI model called for inference.');

    // Assert that the model is loaded.
    if (ort_session == null) {
        throw new Error('ONNX model is not loaded.');
    }

    // Assert that the size is correct.
    if (input.length != 30 * 8 * 8) {
        throw new Error('Input size is incorrect.');
    }

    // Create the input tensor.
    const dataTensor = new ort.Tensor('float32', input, [1, 30, 8, 8]);
    const feeds = { INPUT: dataTensor };
    const results = await ort_session.run(feeds);

    console.log("Results: ", results);

    // Return the result.
    return results.OUTPUT.data;
}

let [wasm_js_hash_ai, wasm_hash_ai] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash_ai, wasm_hash_ai);

importScripts(`/cache/lib.min.js?hash=${wasm_js_hash_ai}`);
declare var wasm_bindgen: any;

const { request_ai_action, console_log_from_wasm } = wasm_bindgen;


/** Helps with typescript type checking. */
declare function postMessage(params: string);

async function handleAiMessage(data: any) {
    console.log(`We got an AI request: ${data}`);
    let response: string = await request_ai_action(data.data);
    postMessage(response);
}

// call two async functions in parallel and wait for both to finish
Promise.all([
    wasm_bindgen(`/cache/lib.wasm?hash=${wasm_hash_ai}`),
    load_model()]).then(_ => {
        console.log('WASM loaded, AI worker ready.');
        console_log_from_wasm();
        onmessage = ev => handleAiMessage(ev)
        // Notify the main thread that we are ready.
        // This then tells the message queue to start processing messages.
        postMessage('ready');
    });
