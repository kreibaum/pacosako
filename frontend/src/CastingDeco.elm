module CastingDeco exposing
    ( InputMode(..)
    , Messages
    , Model
    , clearArrows
    , clearTiles
    , configView
    , initModel
    , mouseDown
    , mouseMove
    , mouseUp
    , toDecoration
    )

import Arrow exposing (Arrow)
import Components exposing (btn, isEnabledIf, isSelectedIf, viewButton, withMsg, withMsgIf)
import Custom.Element as Element
import Custom.Events exposing (BoardMousePosition)
import Element exposing (Element, padding, spacing)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import List.Extra as List
import Tile exposing (Tile(..))
import Translations as T


type alias Model =
    { tiles : List Tile
    , arrows : List Arrow
    , ghostArrow : Maybe Arrow
    }


initModel : Model
initModel =
    { tiles = []
    , arrows = []
    , ghostArrow = Nothing
    }


type InputMode
    = InputTiles
    | InputArrows String


mouseDown : InputMode -> BoardMousePosition -> Model -> Model
mouseDown mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows color ->
            mouseDownArrows color mouse model


{-| Create a ghost arrow.
-}
mouseDownArrows : String -> BoardMousePosition -> Model -> Model
mouseDownArrows color mouse model =
    { model | ghostArrow = Maybe.map (\tile -> Arrow tile tile Arrow.defaultTailWidth color) mouse.tile }


mouseMove : InputMode -> BoardMousePosition -> Model -> Model
mouseMove mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows _ ->
            mouseMoveArrows mouse model


{-| Update the ghost arrow if it exists.
-}
mouseMoveArrows : BoardMousePosition -> Model -> Model
mouseMoveArrows mouse model =
    { model
        | ghostArrow =
            Maybe.map2 setHead mouse.tile model.ghostArrow
    }


setHead : Tile -> Arrow -> Arrow
setHead head arrow =
    { arrow | head = head }


mouseUp : InputMode -> BoardMousePosition -> Model -> Model
mouseUp mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            mouseUpTiles mouse model

        InputArrows _ ->
            model
                |> mouseMoveArrows mouse
                |> mouseUpArrows


{-| Commit the ghost arrow to the arrows map or remove it if it already exists.
-}
mouseUpArrows : Model -> Model
mouseUpArrows model =
    case model.ghostArrow of
        Just ghostArrow ->
            { model
                | ghostArrow = Nothing
                , arrows = ghostArrow :: model.arrows
            }

        Nothing ->
            model


mouseUpTiles : BoardMousePosition -> Model -> Model
mouseUpTiles mouse model =
    case mouse.tile of
        Just tile ->
            { model | tiles = flipEntry tile model.tiles }

        Nothing ->
            model


flipEntry : a -> List a -> List a
flipEntry entry list =
    if List.member entry list then
        List.remove entry list

    else
        entry :: list


{-| Removes all tiles.
-}
clearTiles : Model -> Model
clearTiles model =
    { model | tiles = [] }


{-| Removes all tiles.
-}
clearArrows : Model -> Model
clearArrows model =
    { model | arrows = [], ghostArrow = Nothing }


{-| Helper function to display the tiles and arrows.
-}
toDecoration : { tile : Tile -> a, arrow : Arrow -> a } -> Model -> List a
toDecoration mappers model =
    List.map mappers.tile model.tiles
        ++ List.map mappers.arrow (allArrows model)


allArrows : Model -> List Arrow
allArrows model =
    case model.ghostArrow of
        Just arrow ->
            arrow :: model.arrows

        Nothing ->
            model.arrows


type alias Messages msg =
    { setInputMode : Maybe InputMode -> msg
    , clearTiles : msg
    , clearArrows : msg
    }


{-| Input element where you can manage the casting deco.
-}
configView : Messages msg -> Maybe InputMode -> Model -> Element msg
configView messages mode model =
    Element.column [ spacing 5 ]
        [ normalInputModeButton messages mode
        , tileInputMode messages mode model
        , arrowInputMode messages mode model
        ]


normalInputModeButton : Messages msg -> Maybe InputMode -> Element msg
normalInputModeButton messages mode =
    btn T.decoNormalMode
        |> withMsg (messages.setInputMode Nothing)
        |> isSelectedIf (mode == Nothing)
        |> viewButton


tileInputMode : Messages msg -> Maybe InputMode -> Model -> Element msg
tileInputMode messages mode model =
    Element.row [ spacing 5 ]
        [ tileInputModeButton messages mode
        , tileInputClearButton messages model
        ]


tileInputModeButton : Messages msg -> Maybe InputMode -> Element msg
tileInputModeButton messages mode =
    btn T.decoHighlight
        |> withMsg (messages.setInputMode (Just InputTiles))
        |> withMsgIf (mode == Just InputTiles) (messages.setInputMode Nothing)
        |> isSelectedIf (mode == Just InputTiles)
        |> viewButton


tileInputClearButton : Messages msg -> Model -> Element msg
tileInputClearButton messages model =
    btn T.decoClearHighlight
        |> withMsgIf (not <| List.isEmpty model.tiles) messages.clearTiles
        |> isEnabledIf (not <| List.isEmpty model.tiles)
        |> viewButton


arrowInputMode : Messages msg -> Maybe InputMode -> Model -> Element msg
arrowInputMode messages mode model =
    Element.row [ spacing 5 ]
        [ arrowInputModeButton (Element.rgb255 255 200 0) "rgb(255, 200, 0, 0.5)" messages mode
        , arrowInputModeButton (Element.rgb255 200 0 255) "rgb(200, 0, 255, 0.5)" messages mode
        , arrowInputModeButton (Element.rgb255 0 0 0) "rgb(0, 0, 0, 0.5)" messages mode
        , arrowInputModeButton (Element.rgb255 255 255 255) "rgb(255, 255, 255, 0.7)" messages mode
        , arrowInputClearButton messages model
        ]


arrowInputModeButton : Element.Color -> String -> Messages msg -> Maybe InputMode -> Element msg
arrowInputModeButton eColor color messages mode =
    Input.button
        [ padding 5
        , Background.color
            (if mode == Just (InputArrows color) then
                Element.rgb255 200 200 200

             else
                Element.rgb255 240 240 240
            )
        , Border.rounded 5
        , Element.mouseOver [ Background.color (Element.rgb255 220 220 220) ]
        ]
        { onPress = Just (messages.setInputMode (Just (InputArrows color)))
        , label = Element.icon [ Font.color eColor ] Solid.arrowRight
        }


arrowInputClearButton : Messages msg -> Model -> Element msg
arrowInputClearButton messages model =
    btn T.decoClearArrows
        |> withMsgIf (not <| List.isEmpty model.arrows) messages.clearArrows
        |> isEnabledIf (not <| List.isEmpty model.arrows)
        |> viewButton
