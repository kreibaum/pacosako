module Svg.PlayerLabel exposing (both, rotationToYPosition)

{-| Wraps the SVG on top and bottom of the game which shows the players.
-}

import Api.Decoders exposing (PublicUserData)
import Maybe.Extra as Maybe
import Sako exposing (VictoryState(..))
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))


type alias DataRequiredForPlayers =
    { rotation : BoardRotation
    , whitePlayer : Maybe PublicUserData
    , blackPlayer : Maybe PublicUserData
    , victoryState : VictoryState
    , isWithTimer : Bool

    -- The player isn't getting calculated in replays yet.
    , currentPlayer : Maybe Sako.Color
    }


{-| Renders the SVG for the player labels.
-}
both : DataRequiredForPlayers -> List (Maybe (Svg a))
both model =
    let
        aiXPos =
            aiLabelXPosition model.isWithTimer

        yPosition =
            rotationToYPosition model.rotation

        nameExtension =
            victoryStateToText model.victoryState model.currentPlayer
    in
    [ model.whitePlayer |> Maybe.map (playerLabelSvg aiXPos yPosition.white nameExtension.white)
    , model.blackPlayer |> Maybe.map (playerLabelSvg aiXPos yPosition.black nameExtension.black)
    ]


{-| Renders a single player label SVG.
-}
playerLabelSvg : String -> Int -> String -> PublicUserData -> Svg a
playerLabelSvg aiXPos yPos nameExtension userData =
    Svg.g [ SvgA.transform ("translate(0 " ++ String.fromInt yPos ++ ")") ]
        [ Svg.image
            [ SvgA.xlinkHref ("/p/" ++ userData.avatar)
            , SvgA.width "50"
            , SvgA.height "50"
            ]
            []
        , Svg.text_
            [ SvgA.style "text-anchor:start;font-size:40px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
            , SvgA.x "60"
            , SvgA.y "30"
            ]
            [ Svg.text (userData.name ++ nameExtension) ]
        , case userData.ai of
            Just aiData ->
                Svg.text_
                    [ SvgA.style "text-anchor:end;font-size:20px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
                    , SvgA.x aiXPos
                    , SvgA.y "15"
                    ]
                    [ Svg.text ("\u{1F916} " ++ aiData.modelName) ]

            Nothing ->
                Svg.text_ [] []
        , case userData.ai of
            Just aiData ->
                Svg.text_
                    [ SvgA.style "text-anchor:end;font-size:20px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
                    , SvgA.x aiXPos
                    , SvgA.y "40"
                    ]
                    [ Svg.text ("💡 " ++ String.fromInt aiData.modelStrength) ]

            Nothing ->
                Svg.text_ [] []
        ]


aiLabelXPosition : Bool -> String
aiLabelXPosition isWithTimer =
    if isWithTimer then
        "540"

    else
        "800"


{-| Determines the Y position of the on-svg timer label and player label.
This is required to flip the labels when the board is flipped to have Black
at the bottom.
-}
rotationToYPosition : BoardRotation -> { white : Int, black : Int }
rotationToYPosition rotation =
    case rotation of
        WhiteBottom ->
            { white = 820, black = -70 }

        BlackBottom ->
            { white = -70, black = 820 }


victoryStateToText : VictoryState -> Maybe Sako.Color -> { white : String, black : String }
victoryStateToText victoryState currentPlayer =
    case victoryState of
        PacoVictory Sako.White ->
            { white = " 🏆", black = "" }

        PacoVictory Sako.Black ->
            { white = "", black = " 🏆" }

        TimeoutVictory Sako.White ->
            { white = " 🏆", black = " 🐌" }

        TimeoutVictory Sako.Black ->
            { white = " 🐌", black = " 🏆" }

        _ ->
            case currentPlayer of
                Just Sako.White ->
                    { white = " ⏳", black = "" }

                Just Sako.Black ->
                    { white = "", black = " ⏳" }

                Nothing ->
                    { white = "", black = "" }