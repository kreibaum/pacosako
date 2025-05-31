/// Main typescript file that handles the ports and flags for elm.

/// Type Declaration to make the typescript compiler stop complaining about elm.
/// This could be more precise listing also the ports that we have for better
/// type checking.
declare var Elm: any;
declare var static_assets: any;
declare var my_user_name, my_user_avatar: string;
declare var my_user_id: number;

// Set up a new mutation observer, that will fire custom events for all
// svg elements when there is a click event or a motion event.
// The coordinates will be automatically transformed into SVG local
// coordinates. Code by Ben Hanna and Atle Wee Førre.
// https://discourse.elm-lang.org/t/custom-elements-extend-svg-real-coordinates-on-mouse-events/1762
// https://ellie-app.com/3bmhDwTcdTZa1

// This version has been modified to account for multiple nodes
// being added to the DOM at the same time, with the svg node not being
// added directly. The Elm side has also been modified, to deal with
// Float coordinates.

function getSvgCoord(event) {
    let svg = event.currentTarget;

    let point = svg.createSVGPoint();
    point.x = event.clientX;
    point.y = event.clientY;
    return point.matrixTransform(svg.getScreenCTM().inverse());
}

function mapMouseEvent(node, realName: string, customName: string) {
    node.addEventListener(realName, function (event) {
        if (event.button === 0) {
            var svgClickEvent = new CustomEvent(customName, {
                detail: getSvgCoord(event),
            });
            event.currentTarget.dispatchEvent(svgClickEvent);
        }
    });
}

function mapRightClick(node, customName: string) {
    node.addEventListener("contextmenu", function (event) {
        event.preventDefault();
        let svgClickEvent = new CustomEvent(customName, {
            detail: getSvgCoord(event),
        });
        event.currentTarget.dispatchEvent(svgClickEvent);
    });
}

// Given a node that was added to the ui, this figures out all the
// svg nodes that are contained in it.
function findAllSvgNodes(node) {
    // Special case, if the root node is a svg node already.
    if (node.tagName === "svg") {
        return new Array(node);
    } else {
        return node.getElementsByTagName
            ? Array.from(node.getElementsByTagName("svg"))
            : new Array();
    }
}

var observer = new MutationObserver(function (mutations) {
    mutations.forEach(function (mutation) {
        if (mutation.type === "childList") {
            // Find all svg tags, then add event mappers.
            Array.from(mutation.addedNodes)
                .flatMap(findAllSvgNodes)
                .filter(function (node) {
                    return node.tagName === "svg";
                })
                .forEach(function (node) {
                    mapMouseEvent(node, "mousedown", "svgdown");
                    mapMouseEvent(node, "mousemove", "svgmove");
                    mapMouseEvent(node, "mouseup", "svgup");
                    mapRightClick(node, "svgrightclick");
                });
        }
    });
});

observer.observe(document.body, {childList: true, subtree: true});


////////////////////////////////////////////////////////////////////////////////
// Set a session cookie ////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// Retrieve local storage
let localStorageData = JSON.parse(localStorage.getItem('localStorage'));

// Pass the window size to elm on init. This way we already know it on startup.
let windowSize = {"width": window.innerWidth, "height": window.innerHeight};
let elmFlags = {
    "windowSize": windowSize,
    "localStorage": localStorageData,
    "now": Date.now(),
    "myUserName": my_user_name,
    "myUserId": my_user_id,
    "myUserAvatar": my_user_avatar
};
var app = Elm.Main.init({
    node: document.getElementById("elm"),
    flags: elmFlags,
});

if (app.ports.writeToLocalStorage) {
    app.ports.writeToLocalStorage.subscribe(function (data) {
        localStorage.setItem('localStorage', JSON.stringify(data));
        console.log(`Wrote ${JSON.stringify(data)} into local storage`);
    });
}

// The trampolineIn and trampolineOut are a way to send a global message.
// This is used to trigger a save of the local storage from any component.
// The Shared.Model itself is updated by the page's save method.
if (app.ports.trampolineOut && app.ports.trampolineIn) {
    app.ports.trampolineOut.subscribe(() => {
        app.ports.trampolineIn.send(null);
    });
}

app.ports.logToConsole.subscribe((message) => console.log(message));

// Ports to extract an svg node as xml from the dom.
app.ports.requestSvgNodeContent.subscribe(function (elementId) {
    let svgElement = document.getElementById(elementId);

    if (svgElement) {
        let svgURL = new XMLSerializer().serializeToString(svgElement);
        app.ports.responseSvgNodeContent.send(svgURL);
    }
});

// Ports to download an svg node as png from the dom.
app.ports.triggerPngDownload.subscribe(function (request) {
    console.log(JSON.stringify(request));
    let svgElement = document.getElementById(request.svgNode);

    if (svgElement) {
        // Change the size of the svg node to match the requested output size.
        // We create a copy because we don't want to change the original element.
        let svgClone = svgElement.cloneNode(true) as HTMLElement;
        // The attributes .width and .height on <svg> don't do what you would expect.
        svgClone.setAttribute("width", request.outputWidth);
        svgClone.setAttribute("height", request.outputHeight);

        // https://stackoverflow.com/a/33227005
        let svgURL = new XMLSerializer().serializeToString(svgClone);
        let canvas = document.getElementById("offscreen-canvas") as HTMLCanvasElement;
        canvas.width = request.outputWidth;
        canvas.height = request.outputHeight;
        let img = new Image();
        img.onload = function () {
            canvas.getContext("2d").drawImage(img, 0, 0);
            download(canvas, "pacoSako.png");
        };
        img.src =
            "data:image/svg+xml; charset=utf8, " + encodeURIComponent(svgURL);
    }
});

/** Canvas download from https://codepen.io/joseluisq/pen/mnkLu */
function download(canvas, filename) {
    /// create an "off-screen" anchor tag
    var lnk = document.createElement("a");

    /// the key here is to set the download attribute of the a tag
    lnk.download = filename;

    /// convert canvas content to data-uri for link. When download
    /// attribute is set the content pointed to by link will be
    /// pushed as "download" in HTML5 capable browsers
    lnk.href = canvas.toDataURL("image/png;base64");

    /// create a "fake" click-event to trigger the download
    if (document.createEvent) {
        let e = document.createEvent("MouseEvents");
        /// This is deprecated, there is probably a better way to do this now.
        /// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/initMouseEvent
        /// Hopefully, the other way also has a better format when run through
        /// the Prettier formatter.
        e.initMouseEvent(
            "click",
            true,
            true,
            window,
            0,
            0,
            0,
            0,
            0,
            false,
            false,
            false,
            false,
            0,
            null
        );

        lnk.dispatchEvent(e);
    } else if ((lnk as any).fireEvent) {
        (lnk as any).fireEvent("onclick");
    }
}

////////////////////////////////////////////////////////////////////////////////
// Clipboard Api ///////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////


if (app.ports.copy) {
    app.ports.copy.subscribe(text => {
        console.log(`Copying ${text} to clipboard.`);
        var dummy = document.createElement("input");
        dummy.style.display = 'block';
        document.body.appendChild(dummy);

        dummy.setAttribute("id", "dummy_id");
        (document.getElementById("dummy_id") as HTMLInputElement).value = text;
        dummy.select();
        document.execCommand("copy");
        document.body.removeChild(dummy);
    });
}

////////////////////////////////////////////////////////////////////////////////
// Websocket ///////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/**
 * The browser stores a uuid that is sent over the websocket to prevent other
 * people from moving your pieces.
 *
 * https://github.com/kreibaum/pacosako/issues/53
 */
function getUUID(): string {
    let uuid = localStorage.getItem('uuid');
    if (!uuid) {
        uuid = Date.now().toString(36) + Math.random().toString(36).substring(2);
        localStorage.setItem("uuid", uuid);
    }
    return uuid;
}

/**
 * Wrapper for the websocket that takes care of several additional aspects:
 *
 * - Registering to the elm port
 * - Forwarding messages that were send before the websocket could be created
 * - Trying multiple ways to connect.
 * - Reconnection behavior with exponential back-off.
 */
class WebsocketWrapper {

    private ws: WebSocket | undefined = undefined;
    private queue: any[] = [];

    constructor() {
        this.connect();

        // Messages from elm are forwarded to the websocket.
        if (app.ports.websocketSend) {
            app.ports.websocketSend.subscribe((data) => this.trySend(data));
        }
    }

    /**
     * Tries to connect to a websocket and returns it after the connection has
     * been opened. Resolves to undefined otherwise.
     * @param websocket_url
     */
    private try_connect(websocket_url: string): Promise<WebSocket | undefined> {
        console.log(`Attempting connection to: ${websocket_url}.`)
        return new Promise((resolve, reject) => {
            let maybe_ws = new WebSocket(websocket_url);
            maybe_ws.onerror = ev => resolve(undefined)
            maybe_ws.onopen = ev => resolve(maybe_ws)
            maybe_ws.onmessage = this.onmessage
        })
    }

    /**
     * This tries to connect to wss://pacoplay.com/websocket or the http version
     * of it. This only works if the proxy is set up correctly.
     */
    private direct_connection(): Promise<WebSocket | undefined> {
        let protocol = window.location.protocol === "https:" ? "wss" : "ws"
        let hostname = window.location.hostname
        let port = window.location.port
        let port_str = port ? `:${port}` : ""

        let websocket_url = `${protocol}://${hostname}${port_str}/websocket?uuid=${getUUID()}`
        return this.try_connect(websocket_url)
    }

    /**
     * Check if we are running on gitpod and then tries to connect there.
     */
    private gitpod_connection(): Promise<WebSocket | undefined> {
        // Check if we are running inside gitpod
        let re = new RegExp("8000-([a-z0-9-.]*\.gitpod\.io)");
        let match = re.exec(window.location.hostname);
        if (match !== null) {
            return this.try_connect(`wss://3010-${match[1]}`)
        } else {
            return Promise.resolve(undefined)
        }
    }

    /**
     * Establish websocket connection.
     */
    private async connect() {
        console.log("Websocket: Connecting...")
        let ws = await this.gitpod_connection()
        if (!ws) {
            ws = await this.direct_connection()
        }
        if (!ws) {
            console.error("No websocket connection established.")
        }
        console.log("Websocket: Connection established.")
        this.sendStatusToElm("Connected")
        this.ws = ws
        this.onopen(null)
        this.ws.onclose = ev => this.connection_closed(ev)
    }

    private onopen(ev: Event) {
        console.log("Websocket connection established.");
        console.log(`There are ${this.queue.length} messages waiting to be send.`)
        let messages = this.queue;
        this.queue = [];
        messages.forEach(msg => {
            this.trySend(msg)
        });
    }

    private onmessage(ev: MessageEvent<any>) {
        if (app.ports.websocketReceive) {
            app.ports.websocketReceive.send(JSON.parse(ev.data));
        }
    }

    /**
     * If the websocket is open, send the message. Otherwise put it in the queue.
     */
    public trySend(msg: any) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(msg));
        } else {
            this.queue.push(msg);
        }
    }

    private static readonly INITIAL_RECONNECT_DELAY: number = 200;
    private static readonly BACK_OFF_FACTOR: number = 1.2;
    private reconnect_delay_ms: number = 200;

    /**
     * Notifies the elm app of the socket problem and tries to reconnect using
     * an exponential back-off strategy.
     */
    private connection_closed(ev: CloseEvent) {
        if (ev.wasClean) {
            console.log("Websocket connection was closed cleanly.")
            return;
        }

        this.sendStatusToElm("Disconnected")

        console.log("Websocket connection was closed. Trying to reconnect.")
        this.reconnect_delay_ms = WebsocketWrapper.INITIAL_RECONNECT_DELAY;

        setTimeout(() => this.try_reconnect(), this.reconnect_delay_ms)
    }

    private async try_reconnect() {
        try {
            await this.connect();
        } catch (error) {
            this.reconnect_delay_ms *= WebsocketWrapper.BACK_OFF_FACTOR;
            console.log(`reconnect failed, will retry in: ${Math.round(this.reconnect_delay_ms)}ms.`)
            setTimeout(() => this.try_reconnect(), this.reconnect_delay_ms)
            return;
        }
    }

    /**
     * Informs the elm app about the current status of the websocket.
     * @param status a string code for the status.
     */
    private sendStatusToElm(status: "Connected" | "Disconnected") {
        if (app.ports.websocketStatus) {
            app.ports.websocketStatus.send(status);
        }
    }
}

var webSocket = new WebsocketWrapper();


// Playing sounds. Note that this can't play multiple sounds at once yet.
// If you trigger the placement sound again while it is still running,
// it will be skipped.
let piece_placement_sound = new Audio(static_assets.placePiece);

function play_sound() {
    piece_placement_sound.play();
}

if (app.ports.playSound) {
    app.ports.playSound.subscribe(() => play_sound());
}

////////////////////////////////////////////////////////////////////////////////
// Ports for scroll detection //////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

let scrollTicking = false;
window.addEventListener('scroll', function (e) {

    if (!scrollTicking) {
        window.requestAnimationFrame(function () {
            if (app.ports.scrollTrigger) {
                app.ports.scrollTrigger.send(null);
            }
            scrollTicking = false;
        });

        scrollTicking = true;
    }
});

if (app.ports.scrollTrigger) {
    // Wait 10 ms before calling app.ports.scrollTrigger.send(null);
    setTimeout(() => {
            app.ports.scrollTrigger.send(null);
        }
        , 10);
}


////////////////////////////////////////////////////////////////////////////////
// Ports for the library Web Worker ////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// The library web worker provides the wasm library without blocking the main
// thread. Since every port in elm is already async, we don't loose synchronicity.

// This worker is created asynchronously, so we can't send messages to it
// immediately. Instead we queue them up and send them once the worker is ready.

declare var lib_worker_hash: string

var libWorker = new Worker(`/js/lib_worker.min.js?hash=${lib_worker_hash}#${wasm_js_hash}|${wasm_hash}`);

let libWorkerMessageQueue = []
let libWorkerIsReady = false

libWorker.onmessage = function (m) {
    // The first message we get from the worker is a "ready" signal.
    // We can then send all the messages that were queued up.
    // This message is not send to Elm.
    if (!libWorkerIsReady) {
        libWorkerIsReady = true
        libWorkerMessageQueue.forEach(msg => libWorker.postMessage(msg))
        libWorkerMessageQueue = []
        return
    }

    // Log messages from the worker.
    console.log("libWorker: " + JSON.stringify(m.data));

    if (m.data && m.data.type && m.data.data) {
        var consumedByElm = sendToElm(app, m.data.type, m.data.data)
        if (!consumedByElm) {
            // Right now the only other recipient for messages except for elm
            // is the websocket, so we send it there.
            webSocket.trySend(m.data)
        }
    } else {
        console.error("libWorker: Received invalid message from worker.")
    }
}


function libWorkerSend(msg: any) {
    const stringifiedMsg = JSON.stringify(msg);
    sendToWebWorker(stringifiedMsg);
}

function sendToWebWorker(stringifiedMsg: any) {
    if (libWorkerIsReady) {
        libWorker.postMessage(stringifiedMsg);
    } else {
        console.log("Message received before libWorker was ready. Queuing message.");
        libWorkerMessageQueue.push(stringifiedMsg);
    }
}

// Connect up the generated ports.
dockToPorts(app);
