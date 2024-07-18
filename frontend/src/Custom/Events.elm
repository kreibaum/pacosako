module Custom.Events exposing (BoardMousePosition, KeyBinding, KeyMatcher, fireMsg, forKey, onKeyUp, onKeyUpAttr, svgDown, svgMove, svgRightClick, svgUp, withAlt, withCtrl)

{-| The default events we get for SVG graphics are a problem, because they are
using external coordinates. It is a lot easier to work with internal coordinates
of the svg, so we have introduces custom events.

This also implements an onEnter event attribute.

-}

import Browser.Events
import Element
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Svg exposing (Attribute)
import Svg.Custom as Svg exposing (BoardRotation, safeTileCoordinate)
import Svg.Events
import Tile exposing (Tile(..))


type alias BoardMousePosition =
    { x : Int
    , y : Int
    , tile : Maybe Tile
    }


boardMousePosition : BoardRotation -> Float -> Float -> BoardMousePosition
boardMousePosition rotation x y =
    { x = round x
    , y = round y
    , tile = safeTileCoordinate rotation (Svg.Coord (round x) (round y))
    }


decodeBoardMousePosition : BoardRotation -> Decoder BoardMousePosition
decodeBoardMousePosition rotation =
    Decode.map2 (boardMousePosition rotation)
        (Decode.at [ "detail", "x" ] Decode.float)
        (Decode.at [ "detail", "y" ] Decode.float)


svgDown : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgDown rotation message =
    Svg.Events.on "svgdown" (Decode.map message (decodeBoardMousePosition rotation))


svgMove : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgMove rotation message =
    Svg.Events.on "svgmove" (Decode.map message (decodeBoardMousePosition rotation))


svgUp : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgUp rotation message =
    Svg.Events.on "svgup" (Decode.map message (decodeBoardMousePosition rotation))


svgRightClick : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgRightClick rotation message =
    Svg.Events.on "svgrightclick" (Decode.map message (decodeBoardMousePosition rotation))



--------------------------------------------------------------------------------
-- Keyboard input --------------------------------------------------------------
--------------------------------------------------------------------------------


type alias KeyStroke =
    { key : String
    , ctrlKey : Bool
    , altKey : Bool
    }


decodeKeyStroke : Decoder KeyStroke
decodeKeyStroke =
    Decode.map3 KeyStroke
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "altKey" Decode.bool)


{-| Describes how to match a key. This is created with the `forKey` function
or by using a KeyMatcher constant like `enterKey`.

You can add additional conditions by piping the matcher through `withCtrl` or
through `withAlt`.

    keybindings =
        [ forKey "1" |> withCtrl |> fireMsg Button1Up
        , enterKey |> fireMsg Confirm
        , enterKey |> withAlt |> fireMsg ForceConfirm
        ]

    subscriptions _ =
        onKeyUp keybindings

-}
type KeyMatcher
    = KeyMatcher
        { key : String
        , withCtrl : Bool
        , withAlt : Bool
        }


{-| Initializes a key matcher for the given key.
-}
forKey : String -> KeyMatcher
forKey key =
    KeyMatcher { key = key, withCtrl = False, withAlt = False }


{-| Modifies a key matcher, requiring that ctrl must be pressed.
-}
withCtrl : KeyMatcher -> KeyMatcher
withCtrl (KeyMatcher data) =
    KeyMatcher { data | withCtrl = True }


{-| Modifies a key matcher, requiring that alt must be pressed.
-}
withAlt : KeyMatcher -> KeyMatcher
withAlt (KeyMatcher data) =
    KeyMatcher { data | withAlt = True }


type KeyBinding msg
    = KeyBinding
        { matcher : KeyMatcher
        , out : msg
        }


{-| Turns a key matcher into a key binding by assigning a message that should
be fired if the key is pressed.
-}
fireMsg : msg -> KeyMatcher -> KeyBinding msg
fireMsg out matcher =
    KeyBinding { matcher = matcher, out = out }


buildDecoder : List (KeyBinding msg) -> Decoder msg
buildDecoder keybindings =
    decodeKeyStroke
        |> Decode.andThen
            (\data ->
                Decode.oneOf (List.map (decodeOne data) keybindings)
            )


decodeOne : KeyStroke -> KeyBinding msg -> Decoder msg
decodeOne data (KeyBinding binding) =
    if matches binding.matcher data then
        Decode.succeed binding.out

    else
        Decode.fail "Key does not match."


matches : KeyMatcher -> KeyStroke -> Bool
matches (KeyMatcher matcher) data =
    data.key == matcher.key && data.ctrlKey == matcher.withCtrl && data.altKey == matcher.withAlt


{-| Turns a list of key bindings into a subscription that will capture "global"
keyboard shortcuts.
-}
onKeyUp : List (KeyBinding msg) -> Sub msg
onKeyUp binding =
    Browser.Events.onKeyUp (buildDecoder binding)


{-| Turns a list of key bindings into an attribute that can be applied to a
single element.

For example, this is how to react to "Enter" being released:

    onKeyUpAttr [ forKey "Enter" |> fireMsg Confirm ]

This is great for inputs that are not part of a larger form and where just
entering a single value has meaning.

-}
onKeyUpAttr : List (KeyBinding msg) -> Element.Attribute msg
onKeyUpAttr binding =
    Element.htmlAttribute (Html.Events.on "keyup" (buildDecoder binding))
