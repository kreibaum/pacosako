// This file corresponds to Api.MessageGen.elm in the Elm code.
// It isn't automatically generated yet. For now I am looking at how I want
// to do this. Starting my manually writing the code.

function dockToPorts(elmApp: any, webWorker: Worker) {
    // Ports where Elm can send messages.
    // Essentially this needs to generate a message broker...

    // generateRandomPosition :: Elm ~> WebWorker
    // NOTE: Any data send to WebWorker is turned into a string with JSON.stringify
    // TODO: Instead of postMessage, we should queue up messages and send them
    // when the worker is ready. I think I have that somewhere...
    if (elmApp.ports.generateRandomPosition) {
        elmApp.ports.generateRandomPosition.subscribe(function (data) {
            const jsonData = JSON.stringify(data);
            console.log("Elm port 'generateRandomPosition' send ", jsonData);
            webWorker.postMessage({ type: "generateRandomPosition", data: jsonData });
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
function sendToElm(elmApp: any, type: string, data: string) {
    var port = elmApp.ports[type]
    if (port) {
        port.send(JSON.parse(data));
    } else {
        console.log(`No port with name ${type} found.\n` +
            `This may be because the port is not used in Elm and dead code elimination removed it.`);
    }
}