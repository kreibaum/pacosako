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

// Pass the window size to elm on init. This way we already know it on startup.
let windowSize = { width: window.innerWidth, height: window.innerHeight };
var app = Elm.Main.init({
    node: document.getElementById("elm"),
    flags: windowSize,
});

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

// Connect to the websocket to syncronize state

function connectWebsocketToPort(ws) {
    // When a message arrives, this is forwarded to the elm application.
    ws.onmessage = function (event) {
        app.ports.websocketReceive.send(JSON.parse(event.data));
    };
    // Messages from elm are forwarded to the websocket.
    app.ports.websocketSend.subscribe((data) =>
        ws.send(JSON.stringify(data))
    );
}

async function askForWebsocket() {
    let websocket_port = await fetch("/api/websocket/port").then((r) =>
        r.text()
    );
    webSocket = new WebSocket(
        `ws://${window.location.hostname}:${websocket_port}`
    );
    connectWebsocketToPort(webSocket);
}

// When developing in gitpod, we need to connect to a different subdomain,
// see https://github.com/kreibaum/pacosako/issues/14
let re = new RegExp("8000-([a-z0-9-.]*\.gitpod\.io)");
let match = re.exec(window.location.hostname);
let webSocket;
if (match !== null) {
    webSocket = new WebSocket(`wss://3010-${match[1]}`);
    connectWebsocketToPort(webSocket);
} else {
    askForWebsocket();
}

// Playing sounds. Note that this can't play multiple sounds at once yet.
// If you trigger the placement sound again while it is still running,
// it will be skipped.
let piece_placement_sound = new Audio("./static/place_piece.mp3");

function play_sound() {
    piece_placement_sound.play();
}

if (app.ports.playSound) {
    app.ports.playSound.subscribe(() => play_sound());
}