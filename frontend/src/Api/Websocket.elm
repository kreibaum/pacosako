module Api.Websocket exposing
    ( ClientMessage(..)
    , ServerMessage(..)
    , WebsocketConnectionState(..)
    , listen
    , listenToStatus
    , send
    )

{-|


# Websocket api

To syncronize state quickly between multiple browsers, we have a websocket
connection open.

Note that this module does not take complete care of serialization and
deserialization, as it has no knowledge of the types which would be required for
this.

I do allow this module access to the Sako module.

-}

import Api.Decoders exposing (CurrentMatchState, decodeMatchState)
import Api.Ports as Ports
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Sako
import Time exposing (Posix)


{-| Elm version of websocket::ClientMessage

All allowed messages that may be send by the client to the server.

-}
type ClientMessage
    = DoAction { key : String, action : List Sako.Action }
    | Rollback String
    | TimeDriftCheck Posix


encodeClientMessage : ClientMessage -> Value
encodeClientMessage clientMessage =
    case clientMessage of
        DoAction data ->
            Encode.object
                [ ( "DoAction"
                  , Encode.object
                        [ ( "key", Encode.string data.key )
                        , ( "action", Encode.list Sako.encodeAction data.action )
                        ]
                  )
                ]

        Rollback key ->
            Encode.object
                [ ( "Rollback"
                  , Encode.object
                        [ ( "key", Encode.string key )
                        ]
                  )
                ]

        TimeDriftCheck timestamp ->
            Encode.object
                [ ( "TimeDriftCheck"
                  , Encode.object
                        [ ( "send", Iso8601.encode timestamp )
                        ]
                  )
                ]


{-| Elm version of websocket::ServerMessage

All allowed messages that may be send by the server to the client.

-}
type ServerMessage
    = TechnicalError String
    | NewMatchState CurrentMatchState
    | TimeDriftRespose { send : Posix, bounced : Posix }


decodeServerMessage : Decoder ServerMessage
decodeServerMessage =
    Decode.oneOf
        [ Decode.map TechnicalError
            (Decode.at [ "TechnicalError", "error_message" ] Decode.string)
        , Decode.map NewMatchState
            (Decode.field "CurrentMatchState" decodeMatchState)
        , Decode.map2
            (\sendTimestamp bouncedTimestamp ->
                TimeDriftRespose
                    { send = sendTimestamp
                    , bounced = bouncedTimestamp
                    }
            )
            (Decode.at [ "TimeDriftResponse", "send" ] Iso8601.decoder)
            (Decode.at [ "TimeDriftResponse", "bounced" ] Iso8601.decoder)
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


{-| The state of the websocket connection together with the last change that happened.
-}
type WebsocketConnectionState
    = WebsocketConnecting
    | WebsocketConnected
    | WebsocketReconnecting


decodeWebsocketStatus : String -> WebsocketConnectionState
decodeWebsocketStatus code =
    case code of
        "Connected" ->
            WebsocketConnected

        "Disconnected" ->
            WebsocketReconnecting

        _ ->
            -- Typescript says this is impossible, but elm does not know that.
            WebsocketReconnecting


listenToStatus : (WebsocketConnectionState -> msg) -> Sub msg
listenToStatus msg =
    Ports.websocketStatus (decodeWebsocketStatus >> msg)
