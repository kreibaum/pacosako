/** 
 * Use this class as `let myWorker = new Worker('ai_worker.js');` you can then
 * load an AI into it and ask it to perform moves. You will also be able to kill
 * it again.
 */

/** Helps with typescript type checking. */
declare function postMessage(params: any);

onmessage = function (data: any) {
    console.log('The Ai was asked to perform a move.');
    let arbitraryAction = { "Lift": 15 };
    postMessage(arbitraryAction);
}