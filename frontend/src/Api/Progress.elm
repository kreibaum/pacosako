port module Api.Progress exposing (..)

import Json.Decode as Decode exposing (Decoder, Value, field, int, string)


type alias Progress =
    { topic : String
    , current : Int
    , total : Int
    }


decodeProgress : Decoder Progress
decodeProgress =
    Decode.map3 Progress
        (field "topic" string)
        (field "current" int)
        (field "total" int)


port progressPort : (Value -> msg) -> Sub msg


progess : (Progress -> msg) -> msg -> Sub msg
progess toMsg error =
    progressPort (decodeProgressIntoMsg toMsg error)


decodeProgressIntoMsg : (Progress -> msg) -> msg -> Value -> msg
decodeProgressIntoMsg toMsg error value =
    Decode.decodeValue decodeProgress value
        |> Result.map toMsg
        |> Result.withDefault error
