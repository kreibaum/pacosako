module CastingDeco exposing
    ( InputMode(..)
    , Model, toDecoration
    , clearArrows
    , clearTiles
    , initModel
    , mouseDown
    , mouseMove
    , mouseUp
    )

import Arrow exposing (Arrow)
import EventsCustom exposing (BoardMousePosition)
import List.Extra as List
import Sako exposing (Tile)


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
    | InputArrows


mouseDown : InputMode -> BoardMousePosition -> Model -> Model
mouseDown mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows ->
            mouseDownArrows mouse model


{-| Create a ghost arrow.
-}
mouseDownArrows : BoardMousePosition -> Model -> Model
mouseDownArrows mouse model =
    { model | ghostArrow = Maybe.map2 Arrow mouse.tile mouse.tile }


mouseMove : InputMode -> BoardMousePosition -> Model -> Model
mouseMove mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows ->
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

        InputArrows ->
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
                , arrows = flipEntry ghostArrow model.arrows
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


{-| Helper function to display the tiles and arrows. -}
toDecoration : { tile : (Tile -> a), arrow: (Arrow -> a)} -> Model -> List a
toDecoration mappers model =
    List.map mappers.tile model.tiles
        ++ List.map mappers.arrow (allArrows model)


allArrows : Model -> List Arrow
allArrows model =
    case model.ghostArrow of
        Just arrow ->
            flipEntry arrow model.arrows

        Nothing ->
            model.arrows
