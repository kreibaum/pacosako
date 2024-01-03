module Svg.PlayerLabel exposing (both, rotationToYPosition)

{-| Wraps the SVG on top and bottom of the game which shows the players.
-}

import Api.Decoders exposing (PublicUserData)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))


type alias DataRequiredForPlayers =
    { rotation : BoardRotation
    , whitePlayer : Maybe PublicUserData
    , blackPlayer : Maybe PublicUserData
    }


{-| Renders the SVG for the player labels.
-}
both : DataRequiredForPlayers -> List (Maybe (Svg a))
both model =
    let
        yPosition =
            rotationToYPosition model.rotation
    in
    [ model.whitePlayer |> Maybe.map (playerLabelSvg yPosition.white)
    , model.blackPlayer |> Maybe.map (playerLabelSvg yPosition.black)
    ]


{-| Renders a single player label SVG.
-}
playerLabelSvg : Int -> PublicUserData -> Svg a
playerLabelSvg yPos userData =
    Svg.g [ SvgA.transform ("translate(0 " ++ String.fromInt yPos ++ ")") ]
        [ Svg.image
            [ SvgA.xlinkHref ("/p/" ++ userData.avatar)
            , SvgA.width "50"
            , SvgA.height "50"
            ]
            []
        , Svg.text_
            [ SvgA.style "text-anchor:left;font-size:40px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
            , SvgA.x "60"
            , SvgA.y "30"
            ]
            [ Svg.text userData.name ]
        ]


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
