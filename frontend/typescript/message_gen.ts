// This file corresponds to Api.MessageGen.elm in the Elm code.
// It isn't automatically generated yet. For now I am looking at how I want
// to do this. Starting my manually writing the code.

function dockToPorts(elmApp: any) {
    // Ports where Elm can send messages.
    // Essentially this needs to generate a message broker...

    // generateRandomPosition :: Elm ~> WebWorker
    // NOTE: Any data send to WebWorker is turned into a string with JSON.stringify
    connectFromElmPortToWebWorker(elmApp, "determineLegalActions");
    connectFromElmPortToWebWorker(elmApp, "generateRandomPosition");
    connectFromElmPortToWebWorker(elmApp, "analyzePosition");
    connectFromElmPortToWebWorker(elmApp, "analyzeReplay");
    connectFromElmPortToWebWorker(elmApp, "determineAiMove");
    connectFromElmPortToWebWorker(elmApp, "initAi");

    connectFromElmPortToWebWorker(elmApp, "subscribeToMatch");
}

/**
 * Connects an outgoing Elm port to the WebWorker.
 * 
 * @param elmApp The Elm app.
 * @param portName The name of the port.
 */
function connectFromElmPortToWebWorker(elmApp, portName) {
    if (elmApp.ports[portName]) {
        elmApp.ports[portName].subscribe(function (data) {
            const jsonData = JSON.stringify(data);
            console.log(`Elm port '${portName}' send `, jsonData);
            sendToWebWorker({ type: portName, data: jsonData });
        });
    }
}

/**
 * This is a helper function to send messages to Elm.
 * 
 * If elm does not have a port with the given name, 
 * 
 * @param elmApp The Elm app.
 * @param type The port name.
 * @param data The data to send.
 */
function sendToElm(elmApp: any, type: string, data: string): boolean {
    var port = elmApp.ports[type]
    if (port) {
        port.send(JSON.parse(data));
        return true;
    } else {
        return false;
    }
}