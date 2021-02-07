port module Api.Ports exposing
    ( aiState
    , copy
    , logToConsole
    , playSound
    , requestMoveFromAi
    , requestSvgNodeContent
    , responseSvgNodeContent
    , subscribeMoveFromAi
    , triggerPngDownload
    , websocketReceive
    , websocketSend
    , websocketStatus
    )

{-| Ports allow communication between Elm and JavaScript.

It is a common practice to collect all the ports in a single file to keep an
overview of them. We use ports to perform some functions that are not possible
in pure Elm, because the platform support support is not there yet.

-}

import Json.Encode exposing (Value)


{-| Takes the id of an svg node and returns the serialized xml. As a port function can not
directy return anything, this will return via responseSvgNodeContent.
-}
port requestSvgNodeContent : String -> Cmd msg


{-| Subscription half of requestSvgNodeContent.
-}
port responseSvgNodeContent : (String -> msg) -> Sub msg


{-| Instructs the browser to convert the SVG to a PNG and to start a download.
-}
port triggerPngDownload : Value -> Cmd msg


{-| Port for console.log( .. )
-}
port logToConsole : String -> Cmd msg


{-| Port to send messages to the websocket.

Do no use this port directly, it is wrapped by the Websocket.elm module.

-}
port websocketSend : Value -> Cmd msg


{-| Port to get messages back from the websocket.

Do no use this port directly, it is wrapped by the Websocket.elm module.

-}
port websocketReceive : (Value -> msg) -> Sub msg


{-| Port to get information about the websocket status.
-}
port websocketStatus : (String -> msg) -> Sub msg


{-| Playing the "piece placed on chess board" sound file.
-}
port playSound : () -> Cmd msg


{-| Copy a text to the clipboard
-}
port copy : String -> Cmd msg



--------------------------------------------------------------------------------
-- AI Web Worker ports ---------------------------------------------------------
--------------------------------------------------------------------------------


{-| Information about the state of the AI.
-}
port aiState : (Value -> msg) -> Sub msg


{-| Restart the AI thread.
-}
port restartAiWorker : () -> Cmd msg


{-| Given the current game state, this requests a move from the AI.
-}
port requestMoveFromAi : Value -> Cmd msg


{-| After calling `requestMoveFromAi` this response should be received once.
-}
port subscribeMoveFromAi : (Value -> msg) -> Sub msg
