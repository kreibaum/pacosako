port module Ports exposing
    ( requestSvgNodeContent
    , responseSvgNodeContent
    , triggerPngDownload
    )

{-| Ports module dealing with exporting graphics.
-}

import Json.Encode exposing (Value)


{-| Takes the id of an svg node and returns the serialized xml. As a port function can not
directy return anything, this will return via responseSvgNodeContent.
-}
port requestSvgNodeContent : String -> Cmd msg


{-| Subscription half of requestSvgNodeContent.
-}
port responseSvgNodeContent : (String -> msg) -> Sub msg


port triggerPngDownload : Value -> Cmd msg
