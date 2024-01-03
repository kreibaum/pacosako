module Svg.TimerGraphic exposing (playTimerReplaceViewport, playTimerSvg)

{-| This module contains the SVG rendering code for the timer.
-}

import Api.Decoders exposing (CurrentMatchState)
import Duration
import Sako
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))
import Svg.PlayerLabel exposing (rotationToYPosition)
import Time exposing (Posix)
import Timer


{-| We are using a "record extension" here to make it possible to pass in an
existing model when the shape is right already.
-}
type alias DataRequiredForTimers a =
    { a
        | rotation : BoardRotation
        , currentState : CurrentMatchState
        , timeDriftMillis : Float
    }


playTimerSvg : Posix -> DataRequiredForTimers x -> Maybe (Svg a)
playTimerSvg now model =
    model.currentState.timer
        |> Maybe.map (justPlayTimerSvg (correctTimeDrift now model.timeDriftMillis) model)


{-| Corrects the `now` value to better match the time on the server. This is
necessary because the client and server clocks are not perfectly in sync.
-}
correctTimeDrift : Posix -> Float -> Posix
correctTimeDrift now timeDriftMillis =
    Time.posixToMillis now
        |> toFloat
        |> (\n -> n - timeDriftMillis)
        |> round
        |> Time.millisToPosix


justPlayTimerSvg : Posix -> DataRequiredForTimers x -> Timer.Timer -> Svg a
justPlayTimerSvg now model timer =
    let
        viewData =
            Timer.render model.currentState.controllingPlayer now timer

        increment =
            Maybe.map (Duration.inSeconds >> round) timer.config.increment

        yPosition =
            rotationToYPosition model.rotation
    in
    Svg.g []
        [ timerTagSvg
            { caption = timeLabel viewData.secondsLeftWhite
            , player = Sako.White
            , at = Svg.Coord 550 yPosition.white
            , increment = increment
            }
        , timerTagSvg
            { caption = timeLabel viewData.secondsLeftBlack
            , player = Sako.Black
            , at = Svg.Coord 550 yPosition.black
            , increment = increment
            }
        ]


{-| Turns an amount of seconds into a mm:ss label.
-}
timeLabel : Int -> String
timeLabel seconds =
    let
        data =
            distributeSeconds seconds
    in
    (String.fromInt data.minutes |> String.padLeft 2 '0')
        ++ ":"
        ++ (String.fromInt data.seconds |> String.padLeft 2 '0')


distributeSeconds : Int -> { seconds : Int, minutes : Int }
distributeSeconds seconds =
    if seconds <= 0 then
        { seconds = 0, minutes = 0 }

    else
        { seconds = seconds |> modBy 60, minutes = seconds // 60 }


{-| Creates a little rectangle with a text which can be used to display the
timer for one player. Picks colors automatically based on the player.
-}
timerTagSvg :
    { caption : String
    , player : Sako.Color
    , at : Svg.Coord
    , increment : Maybe Int
    }
    -> Svg msg
timerTagSvg data =
    let
        ( backgroundColor, textColor ) =
            case data.player of
                Sako.White ->
                    ( "#eee", "#333" )

                Sako.Black ->
                    ( "#333", "#eee" )

        fullCaption =
            case data.increment of
                Just seconds ->
                    data.caption ++ " +" ++ String.fromInt seconds

                Nothing ->
                    data.caption
    in
    Svg.g [ Svg.translate data.at ]
        [ Svg.rect [ SvgA.width "250", SvgA.height "50", SvgA.fill backgroundColor ] []
        , timerTextSvg (SvgA.fill textColor) fullCaption
        ]


timerTextSvg : Svg.Attribute msg -> String -> Svg msg
timerTextSvg fill caption =
    Svg.text_
        [ SvgA.style "text-anchor:middle;font-size:40px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
        , SvgA.x "125"
        , SvgA.y "30"
        , fill
        ]
        [ Svg.text caption ]


playTimerReplaceViewport :
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }
playTimerReplaceViewport =
    { x = -10
    , y = -80
    , width = 820
    , height = 960
    }
