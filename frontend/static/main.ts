/// Main typescript file that handles the ports and flags for elm.

/// Type Declaration to make the typescript compiler stop complaining about elm.
/// This could be more precise listing also the ports that we have for better
/// controll.
declare var Elm: any;

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
        var svgClickEvent = new CustomEvent(customName, {
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
                });
        }
    });
});

observer.observe(document.body, { childList: true, subtree: true });


// Retrive local storage
let localStorageData = JSON.parse(localStorage.getItem('localStorage'));

// Pass the window size to elm on init. This way we already know it on startup.
let windowSize = { "width": window.innerWidth, "height": window.innerHeight };
var app = Elm.Main.init({
    node: document.getElementById("elm"),
    flags: {
        "windowSize": windowSize,
        "localStorage": localStorageData,
        "now": Date.now()
    },
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

/** Canvas Donwload from https://codepen.io/joseluisq/pen/mnkLu */
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
 * Wrapper for the websocket that takes care of several additional aspects:
 * 
 * - Registering to the elm port
 * - Forwarding messages that were send before the websocket could be created
 * - Trying multiple ways to connect.
 * - Eventually, I'll want some reconnection behaviour in here as well.
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
        let websocket_url = `${protocol}://${hostname}/websocket`
        if (!hostname.includes("localhost")
            && !hostname.includes("127.0.0.1")
            && !hostname.includes("0.0.0.0")) {
            return this.try_connect(websocket_url)
        } else {
            return Promise.resolve(undefined)
        }
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
     * This fallback connection connects directly on the websocket port, as
     * given by the server on /api/websocket/port.
     * This will only work when connected via unsecure http.
     */
    private async fallback_connection(): Promise<WebSocket | undefined> {
        let websocket_port = await fetch("/api/websocket/port").then((r) =>
            r.text()
        );
        return this.try_connect(`ws://${window.location.hostname}:${websocket_port}`)
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
            console.warn("Using fallback websocket connection!")
            ws = await this.fallback_connection()
        }
        if (!ws) {
            console.error("No websocket connection established.")
        }
        console.log("Websocket: Connection established.")
        this.ws = ws
        this.onopen(null)
        this.ws.onclose = ev => this.connection_closed()
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
    private trySend(msg: any) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(msg));
        } else {
            this.queue.push(msg);
        }
    }

    private static readonly INITIAL_RECONNECT_DELAY: number = 200;
    private static readonly BACKOFF_FACTOR: number = 1.2;
    private reconnect_delay_ms: number = 200;

    /**
     * Notifies the elm app of the socket problem and tries to reconnect using
     * an exponential backoff strategy.
     */
    private connection_closed() {
        this.sendStatusToElm("Disconnected")

        console.log("Websocket connection was closed. Trying to reconnect.")
        this.reconnect_delay_ms = WebsocketWrapper.INITIAL_RECONNECT_DELAY;

        setTimeout(() => this.try_reconnect(), this.reconnect_delay_ms)
    }

    private async try_reconnect() {
        try {
            await this.connect();
        } catch (error) {
            this.reconnect_delay_ms *= WebsocketWrapper.BACKOFF_FACTOR;
            console.log(`reconnect failed, will retry in: ${Math.round(this.reconnect_delay_ms)}ms.`)
            setTimeout(() => this.try_reconnect(), this.reconnect_delay_ms)
            return;
        }
        this.sendStatusToElm("Connected")
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

new WebsocketWrapper();


// Playing sounds. Note that this can't play multiple sounds at once yet.
// If you trigger the placement sound again while it is still running,
// it will be skipped.
let piece_placement_sound = new Audio("/static/place_piece.mp3");

function play_sound() {
    piece_placement_sound.play();
}

if (app.ports.playSound) {
    app.ports.playSound.subscribe(() => play_sound());
}


////////////////////////////////////////////////////////////////////////////////
// Ports for the AI Web Worker /////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

let aiWorker = new Worker('/ai_worker.js');

function decide_move(data: any) {
    aiWorker.postMessage(data);
}

function commit_actions(message: MessageEvent<any>) {
    app.ports.subscribeMoveFromAi.send(message.data)
}

aiWorker.onmessage = commit_actions;

if (app.ports.requestMoveFromAi) {
    app.ports.requestMoveFromAi.subscribe(decide_move)
}