module Websocket exposing
    ( ClientMessage(..)
    , ServerMessage(..)
    , ShareStatus(..)
    , SyncronizedBoard
    , getGameKey
    , listen
    , send
    , share
    )

{-|


# Websocket api

To syncronize state quickly between multiple browsers, we have a websocket
connection open.

Note that this module does not take complete care of serialization and
deserialization, as it has no knowledge of the types which would be required for
this.

-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Ports


{-| Elm version of websocket::ClientMessage

All allowed messages that may be send by the client to the server.

-}
type ClientMessage
    = Subscribe String
    | ClientNextStep { index : Int, step : Value }


encodeClientMessage : ClientMessage -> Value
encodeClientMessage clientMessage =
    case clientMessage of
        Subscribe gameKey ->
            Encode.object
                [ ( "Subscribe"
                  , Encode.object
                        [ ( "game_key", Encode.string gameKey ) ]
                  )
                ]

        ClientNextStep data ->
            Encode.object
                [ ( "NextStep"
                  , Encode.object
                        [ ( "index", Encode.int data.index )
                        , ( "step", data.step )
                        ]
                  )
                ]


{-| Elm version of websocket::ServerMessage

All allowed messages that may be send by the server to the client.

-}
type ServerMessage
    = TechnicalError String
    | FullState SyncronizedBoard
    | ServerNextStep { index : Int, step : Value }


type alias SyncronizedBoard =
    { key : String
    , steps : List Value
    }


decodeSyncronizedBoard : Decoder SyncronizedBoard
decodeSyncronizedBoard =
    Decode.map2 SyncronizedBoard
        (Decode.field "key" Decode.string)
        (Decode.field "steps" (Decode.list Decode.value))


decodeServerMessage : Decoder ServerMessage
decodeServerMessage =
    Decode.oneOf
        [ Decode.map TechnicalError
            (Decode.at [ "TechnicalError", "error_message" ] Decode.string)
        , Decode.map FullState
            (Decode.at [ "FullState", "board" ] decodeSyncronizedBoard)
        , Decode.map2 (\index step -> ServerNextStep { index = index, step = step })
            (Decode.at [ "NextStep", "index" ] Decode.int)
            (Decode.at [ "NextStep", "step" ] Decode.value)
        ]


send : ClientMessage -> Cmd msg
send clientMessage =
    Ports.websocketSend (encodeClientMessage clientMessage)


listen : (ServerMessage -> msg) -> (Decode.Error -> msg) -> Sub msg
listen onSuccess onError =
    Ports.websocketReceive
        (\json ->
            case Decode.decodeValue decodeServerMessage json of
                Ok message ->
                    onSuccess message

                Err error ->
                    onError error
        )


{-| REST method which starts sharing a board state.
-}
share : (ShareStatus -> msg) -> List Value -> Cmd msg
share onShare steps =
    Http.post
        { url = "/api/share"
        , body = Http.jsonBody (Encode.list (\v -> v) steps)
        , expect = Http.expectString (shareStatusFromHttpResult >> onShare)
        }


{-| When sharing, this hold the game key. Otherwise this explains why we are not
sharing right now.

Note the difference between `ShareExists` and `ShareConnected`:
When sharing a board we get back the game key but still need to connect to this
shared board on the websocket by sending a `Connect 'PT66m8NX'` on the channel.
Only then is the share status `ShareConnected`.

-}
type ShareStatus
    = NotShared
    | ShareRequested
    | ShareFailed Http.Error
    | ShareExists String
    | ShareConnected String


shareStatusFromHttpResult : Result Http.Error String -> ShareStatus
shareStatusFromHttpResult result =
    case result of
        Ok gameKey ->
            ShareExists gameKey

        Err error ->
            ShareFailed error


getGameKey : ShareStatus -> Maybe String
getGameKey shareStatus =
    case shareStatus of
        ShareExists gameKey ->
            Just gameKey

        ShareConnected gameKey ->
            Just gameKey

        _ ->
            Nothing
