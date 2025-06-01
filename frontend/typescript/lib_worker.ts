// Until modules become available in Web Workers, we need to use importScripts.

declare function importScripts(...urls: string[]): void;

declare function postMessage(params: any): void;

let [wasm_js_hash, wasm_hash] = location.hash.replace("#", "").split("|");

console.log('Initializing worker')
console.log('Hashes are: ', wasm_js_hash, wasm_hash);

importScripts(`/js/lib.min.js?hash=${wasm_js_hash}`);
declare var wasm_bindgen: any;

const {
    generateRandomPosition,
    analyzePosition,
    analyzeReplay,
    subscribeToMatch,
    determineLegalActions,
    determineAiMove,
    initOpeningBook
} = wasm_bindgen;

// Import onnxruntime-web for AI
importScripts('https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.3/dist/ort.min.js');
declare var ort: any;
// Make sure we load the wasm from the CDN.
// https://github.com/microsoft/onnxruntime/issues/16102#issuecomment-1563654211
ort.env.wasm.wasmPaths = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.3/dist/";

/** Helps with typescript type checking. */
declare function postMessage(params: string);

function handleMessage(message: any) {
    var data = message.data;
    console.log(`Worker handling message. Raw: ${message.data}, stringify: ${JSON.stringify(message.data)}`);

    // "generated" message broker
    if (data && data instanceof Object && data.type && data.data) {
        forwardToWasm(data.type, data.data);
    } else {
        console.log(`Unknown message type: ${JSON.stringify(data)}`);
    }
}

// TODO: This fake generated part needs to move to a separate file.
function forwardToWasm(messageType: any, data: any) {
    if (messageType === "determineLegalActions") {
        determineLegalActions(data);
    }
    if (messageType === "generateRandomPosition") {
        generateRandomPosition(data);
    }
    if (messageType === "analyzePosition") {
        analyzePosition(data);
    }
    if (messageType === "analyzeReplay") {
        analyzeReplay(data);
    }
    if (messageType === "subscribeToMatch") {
        subscribeToMatch(data);
    }
    if (messageType === "determineAiMove") {
        determineAiMove(data);
    }
    if (messageType === "initAi") {
        initAi(data);
    }
}

// Allows the rust code to forward arbitrary messages to the main thread.
// This can be called from the rust code.
function forwardToMq(messageType: string, data: string) {
    console.log(`Forwarding message to main thread: ${messageType} ${data}`);
    postMessage({type: messageType, data: data});
}

// Allows the rust code to know the current time.
// This is only relative to the start of the worker. Otherwise we exceed the
// 32 bit integer limit.
let current_timestamp_baseline = Date.now();

function current_timestamp_ms() {
    return Date.now() - current_timestamp_baseline;
}

// Allows rust to log to the console
function console_log(msg: string) {
    console.log(`wasm: ${msg}`)
}


/// Download Hedwig model for use in AI.
/// Define the database name, version, and the store name
/// This is important to only download Hedwig once. (Per version)
const DB_NAME = 'modelCacheDB';
const DB_VERSION = 1; // Every time this is increased, onupgradeneeded is called.
const STORE_NAME = 'models';

// This function opens (and initializes, if necessary) the IndexedDB
function openDatabase(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, DB_VERSION);

        // Called every time DB_VERSION is increased.
        // This is where you can modify the database schema.
        request.onupgradeneeded = function (event) {
            const db = request.result;
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME, {keyPath: 'url'});
            }
        };

        request.onsuccess = function () {
            resolve(request.result);
        };

        request.onerror = function () {
            reject(request.error);
        };
    });
}

// This function retrieves a file from the IndexedDB
function getCachedBlob(db: IDBDatabase, url: string): Promise<Blob | undefined> {
    return new Promise((resolve, reject) => {
        const transaction = db.transaction([STORE_NAME], 'readonly');
        const store = transaction.objectStore(STORE_NAME);
        const request = store.get(url);

        request.onsuccess = function () {
            if (request.result) {
                resolve(request.result.data);
            } else {
                resolve(undefined);
            }
        };

        request.onerror = function () {
            reject(request.error);
        };
    });
}

// This function caches a file into the IndexedDB
function cacheBlob(db: IDBDatabase, url: string, data: Blob): Promise<void> {
    return new Promise((resolve, reject) => {
        const transaction = db.transaction([STORE_NAME], 'readwrite');
        const store = transaction.objectStore(STORE_NAME);
        const request = store.put({url: url, data: data});

        request.onsuccess = function () {
            resolve();
        };

        request.onerror = function () {
            reject(request.error);
        };
    });
}

// For now, we just instantly start downloading the model and caching it.
const hedwigModelUrl = 'https://static.kreibaum.dev/hedwig-0.8-infer-int8.onnx';

// TODO: There should be a list of models in use an unused models should be deleted.
async function download_as_blob(url: string, progress_callback: any): Promise<Blob> {
    try {
        const db = await openDatabase();
        let blob = await getCachedBlob(db, url);

        if (!blob) {
            blob = await download_with_progress(url, progress_callback);
            await cacheBlob(db, url, blob);
            console.log(`File cached. Size: ${blob.size} bytes.`);
        } else {
            console.log(`File loaded from cache. Size: ${blob.size} bytes. (${url})`);
        }

        return blob;
    } catch (error) {
        console.error(`Error handling the file \${url}: `, error);
        throw error;
    }
}

async function download_with_progress(url: string, progress_callback: any): Promise<Blob> {
    console.log(`Downloading the file ${url}...`);
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to fetch ${url}: ${response.statusText}`);
    }

    let contentLength = response.headers.get('Content-Length');
    if (!contentLength) {
        console.log("No Content-Length header found. Progress will not be reported.");
        contentLength = "-1";
    }

    const total = parseInt(contentLength, 10);
    let loaded = 0;

    const reader = response.body.getReader();
    const chunks = [];
    while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        chunks.push(value);
        loaded += value.length;
        if (progress_callback) {
            progress_callback(loaded, total);
        }
    }

    const blob = new Blob(chunks);
    console.log(`File downloaded. Size: ${blob.size} bytes.`);
    return blob;
}

let session: any = undefined;

const hedwigInputShape = [1, 30, 8, 8];

async function initAi(_data: any) {
    if (session !== undefined) {
        // Hedwig is already initialized. Just return the status.
        // TODO: Differentiate between running / not running.
        forwardToMq("aiStateUpdated", JSON.stringify("AiReadyForRequest"))
        return;
    }

    console.log('Initializing AI with data');
    await downloadAndInitHedwig();


    forwardToMq("aiStateUpdated", JSON.stringify("WarmupEvaluation"))
    // Run a warmup evaluation to make sure the model is loaded.
    await evaluate_hedwig(new Float32Array(hedwigInputShape.reduce((x, y) => x * y)));

    forwardToMq("aiStateUpdated", JSON.stringify("AiReadyForRequest"))
}

async function downloadAndInitHedwig() {
    let hedwig: Blob = await download_as_blob(hedwigModelUrl,
        (loaded, total) => forwardToMq("aiStateUpdated", JSON.stringify({
            state: "ModelLoading",
            loaded: loaded,
            total: total
        })));
    const arrayBuffer = await hedwig.arrayBuffer();  // Convert the Blob to ArrayBuffer

    forwardToMq("aiStateUpdated", JSON.stringify("SessionLoading"))
    session = await ort.InferenceSession.create(arrayBuffer);  // Create the session with ArrayBuffer
}

/// This function is called from wasm to delegate to onnxruntime-web.
async function evaluate_hedwig(rawInputTensor: Float32Array): Promise<Float32Array> {
    if (!session) {
        await downloadAndInitHedwig();
    }

    const inputTensor = new ort.Tensor('float32', rawInputTensor, hedwigInputShape);
    const feeds = {};
    feeds[session.inputNames[0]] = inputTensor;

    const results = await session.run(feeds);
    return results[session.outputNames[0]].data;
}

// The opening book is small enough to be loaded without asking the user.
const openingBookUrl = 'https://static.kreibaum.dev/2024-05-31-book-hedwig0.8-1000.json';

async function downloadOpeningBook() {
    let openingBook: Blob = await download_as_blob(openingBookUrl, undefined);
    initOpeningBook(await openingBook.text());
}

wasm_bindgen(`/js/lib.wasm?hash=${wasm_hash}`).then(_ => {
    console.log('WASM loaded, worker ready.');
    // Notify the main thread that we are ready.
    // This then tells the message queue to start processing messages.
    postMessage('ready');
    onmessage = ev => handleMessage(ev)

    downloadOpeningBook()
});