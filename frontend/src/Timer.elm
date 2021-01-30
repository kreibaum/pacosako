module Timer exposing (Timer, TimerConfig, TimerState(..), TimerViewData, decodeTimer, encodeConfig, render, secondsConfig)

{-| Timer implementation that represents the server state of a Paco Ŝako game
timer. This timer will not be updated every second, instead it is rendered
together with a Posix to produce TimerViewData which can then be shown in the
view.
-}

import Duration exposing (Duration)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Quantity
import Sako
import Time exposing (Posix)


{-| This is the type we get send from the server. Constructing timer objects
happens with the decodeTimer function.
-}
type alias Timer =
    { lastTimestamp : Posix
    , timeLeftWhite : Duration
    , timeLeftBlack : Duration
    , timerState : TimerState
    , config : TimerConfig
    }


decodeTimer : Decoder Timer
decodeTimer =
    Decode.map5 Timer
        (Decode.field "last_timestamp" Iso8601.decoder)
        (Decode.field "time_left_white" decodeSeconds)
        (Decode.field "time_left_black" decodeSeconds)
        (Decode.field "timer_state" decodeTimerState)
        (Decode.field "config" decodeConfig)


decodeSeconds : Decoder Duration
decodeSeconds =
    Decode.float |> Decode.map Duration.seconds


encodeSeconds : Duration -> Value
encodeSeconds duration =
    Duration.inSeconds duration |> Encode.float


{-| Use this to configure a timer.
-}
type alias TimerConfig =
    { timeBudgetWhite : Duration
    , timeBudgetBlack : Duration
    , increment : Maybe Duration
    }


{-| A simple way to build a timer configuration object without having to deal
with the Duration units.
-}
secondsConfig : { white : Int, black : Int, increment : Maybe Int } -> TimerConfig
secondsConfig data =
    { timeBudgetWhite = Duration.seconds (toFloat data.white)
    , timeBudgetBlack = Duration.seconds (toFloat data.black)
    , increment = Maybe.map (Duration.seconds << toFloat) data.increment
    }


decodeConfig : Decoder TimerConfig
decodeConfig =
    Decode.map3 TimerConfig
        (Decode.field "time_budget_white" decodeSeconds)
        (Decode.field "time_budget_black" decodeSeconds)
        (Decode.field "increment" (Decode.maybe decodeSeconds))


encodeConfig : TimerConfig -> Value
encodeConfig config =
    Encode.object
        [ ( "time_budget_white", encodeSeconds config.timeBudgetWhite )
        , ( "time_budget_black", encodeSeconds config.timeBudgetBlack )
        , ( "increment"
          , Maybe.map encodeSeconds config.increment
                |> Maybe.withDefault Encode.null
          )
        ]


{-| The timer view data is used to show the timer in the UI.
-}
type alias TimerViewData =
    { secondsLeftWhite : Int
    , secondsLeftBlack : Int
    , timerState : TimerState
    , runningFor : Maybe Sako.Color
    }


{-| Current state of the timer. Note that Timeout White means that white has lost.
-}
type TimerState
    = NotStarted
    | Running
    | Timeout Sako.Color
    | Stopped


decodeTimerState : Decoder TimerState
decodeTimerState =
    Decode.oneOf
        [ decodeConstant "NotStarted" NotStarted
        , decodeConstant "Running" Running
        , Decode.field "Timeout" Sako.decodeColor |> Decode.map Timeout
        , decodeConstant "Stopped" Stopped
        ]


decodeConstant : String -> a -> Decoder a
decodeConstant tag value =
    Decode.string
        |> Decode.andThen
            (\s ->
                if s == tag then
                    Decode.succeed value

                else
                    Decode.fail (s ++ " is not " ++ tag)
            )


{-| The time is not stored in the timer directly, instead we use the current
player and the current time to turn the Timer into a TimerViewData record that
we can then use to render the timer in the UI.
-}
render : Sako.Color -> Posix -> Timer -> TimerViewData
render currentPlayer now timer =
    case timer.timerState of
        NotStarted ->
            renderPausedTimer timer

        Running ->
            renderRunningTimer currentPlayer now timer

        Timeout _ ->
            renderPausedTimer timer

        Stopped ->
            renderPausedTimer timer


{-| This function is executed if the timer is already running.
-}
renderRunningTimer : Sako.Color -> Posix -> Timer -> TimerViewData
renderRunningTimer currentPlayer now timer =
    let
        timePassed =
            Duration.from timer.lastTimestamp now
    in
    case currentPlayer of
        Sako.White ->
            { secondsLeftWhite = timer.timeLeftWhite |> Quantity.minus timePassed |> Duration.inSeconds |> round
            , secondsLeftBlack = timer.timeLeftBlack |> Duration.inSeconds |> round
            , timerState = timer.timerState
            , runningFor = Just Sako.White
            }

        Sako.Black ->
            { secondsLeftWhite = timer.timeLeftWhite |> Duration.inSeconds |> round
            , secondsLeftBlack =
                timer.timeLeftBlack
                    |> Quantity.minus timePassed
                    |> Duration.inSeconds
                    |> round
            , timerState = timer.timerState
            , runningFor = Just Sako.Black
            }


renderPausedTimer : Timer -> TimerViewData
renderPausedTimer timer =
    { secondsLeftWhite = timer.timeLeftWhite |> Duration.inSeconds |> round
    , secondsLeftBlack = timer.timeLeftBlack |> Duration.inSeconds |> round
    , timerState = timer.timerState
    , runningFor = Nothing
    }
