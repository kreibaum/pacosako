module Api.Websocket exposing
    ( ClientMessage(..)
    , CurrentMatchState
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

I do allow this module access to the Sako module.

-}

import Api.Ports as Ports
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Sako
import Timer


{-| Elm version of websocket::ClientMessage

All allowed messages that may be send by the client to the server.

-}
type ClientMessage
    = Subscribe String
    | ClientNextStep { index : Int, step : Value }
    | SubscribeToMatch String
    | DoAction { key : String, action : Sako.Action }
    | Rollback String
    | SetTimer { key : String, timer : Timer.TimerConfig }
    | StartTimer String


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

        SubscribeToMatch key ->
            Encode.object
                [ ( "SubscribeToMatch"
                  , Encode.object
                        [ ( "key", Encode.string key )
                        ]
                  )
                ]

        DoAction data ->
            Encode.object
                [ ( "DoAction"
                  , Encode.object
                        [ ( "key", Encode.string data.key )
                        , ( "action", Sako.encodeAction data.action )
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

        SetTimer data ->
            Encode.object
                [ ( "SetTimer"
                  , Encode.object
                        [ ( "key", Encode.string data.key )
                        , ( "timer", Timer.encodeConfig data.timer )
                        ]
                  )
                ]

        StartTimer key ->
            Encode.object
                [ ( "StartTimer"
                  , Encode.object
                        [ ( "key", Encode.string key )
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
    | NewMatchState CurrentMatchState
    | MatchConnectionSuccess { key : String, state : CurrentMatchState }


type alias CurrentMatchState =
    { key : String
    , actionHistory : List Sako.Action
    , legalActions : List Sako.Action
    , controllingPlayer : Sako.Color
    , timer : Maybe Timer.Timer
    , gameState : Sako.VictoryState
    }


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
        , Decode.map NewMatchState
            (Decode.field "CurrentMatchState" decodeMatchState)
        , Decode.map2 (\key matchState -> MatchConnectionSuccess { key = key, state = matchState })
            (Decode.at [ "MatchConnectionSuccess", "key" ] Decode.string)
            (Decode.at [ "MatchConnectionSuccess", "state" ] decodeMatchState)
        ]


decodeMatchState : Decoder CurrentMatchState
decodeMatchState =
    Decode.map6
        (\key actionHistory legalActions controllingPlayer timer gameState ->
            { key = key
            , actionHistory = actionHistory
            , legalActions = legalActions
            , controllingPlayer = controllingPlayer
            , timer = timer
            , gameState = gameState
            }
        )
        (Decode.field "key" Decode.string)
        (Decode.field "actions" (Decode.list Sako.decodeAction))
        (Decode.field "legal_actions" (Decode.list Sako.decodeAction))
        (Decode.field "controlling_player" Sako.decodeColor)
        (Decode.field "timer" (Decode.maybe Timer.decodeTimer))
        (Decode.field "victory_state" Sako.decodeVictoryState)


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
