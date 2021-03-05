module Colors exposing
    ( ColorConfig
    , ColorOptions
    , configToOptions
    , defaultBoardColors
    , getOptionsByName
    , withPieceColorScheme
    )

{-| Module that captures all the types and helper methods I have for colors.
-}

import Color exposing (Color)
import Json.Decode
import Json.Decode.Pipeline
import Json.Encode


{-| A color options configuration object where the colors are stored as rich
objects so it is easy to configure and transform them
-}
type alias ColorConfig =
    { whiteTileColor : Color
    , blackTileColor : Color
    , borderColor : Color
    , highlightColor : Color
    , whitePieceFill : Color
    , whitePieceStroke : Color
    , blackPieceFill : Color
    , blackPieceStroke : Color
    }


{-| Default colors of the website.
-}
defaultBoardColors : ColorConfig
defaultBoardColors =
    greenBoardColors


greenBoardColors : ColorConfig
greenBoardColors =
    { whiteTileColor = Color.rgb255 153 255 153
    , blackTileColor = Color.rgb255 85 153 85
    , borderColor = Color.rgb255 34 68 34
    , highlightColor = Color.rgb255 255 255 100
    , whitePieceFill = Color.rgb255 255 255 255
    , whitePieceStroke = Color.rgb255 0 0 0
    , blackPieceFill = Color.rgb255 50 50 50
    , blackPieceStroke = Color.rgb255 0 0 0
    }


fiveAsideBoardColors : ColorConfig
fiveAsideBoardColors =
    { whiteTileColor = Color.rgb255 255 255 50
    , blackTileColor = Color.rgb255 43 43 36
    , borderColor = Color.rgb255 227 227 100
    , highlightColor = Color.rgb255 255 255 100
    , whitePieceFill = Color.rgb255 255 255 255
    , whitePieceStroke = Color.rgb255 0 0 0
    , blackPieceFill = Color.rgb255 50 50 50
    , blackPieceStroke = Color.rgb255 150 150 100
    }


decodeColor : Json.Decode.Decoder Color
decodeColor =
    Json.Decode.map4 Color.rgba
        (Json.Decode.field "red" Json.Decode.float)
        (Json.Decode.field "green" Json.Decode.float)
        (Json.Decode.field "blue" Json.Decode.float)
        (Json.Decode.field "alpha" Json.Decode.float)


encodeColor : Color -> Json.Encode.Value
encodeColor color =
    let
        record =
            Color.toRgba color
    in
    Json.Encode.object
        [ ( "red", Json.Encode.float <| record.red )
        , ( "green", Json.Encode.float <| record.green )
        , ( "blue", Json.Encode.float <| record.blue )
        , ( "alpha", Json.Encode.float <| record.alpha )
        ]


decodeColorConfig : Json.Decode.Decoder ColorConfig
decodeColorConfig =
    Json.Decode.succeed ColorConfig
        |> Json.Decode.Pipeline.required "whiteTileColor" decodeColor
        |> Json.Decode.Pipeline.required "blackTileColor" decodeColor
        |> Json.Decode.Pipeline.required "borderColor" decodeColor
        |> Json.Decode.Pipeline.required "highlightColor" decodeColor
        |> Json.Decode.Pipeline.required "whitePieceFill" decodeColor
        |> Json.Decode.Pipeline.required "whitePieceStroke" decodeColor
        |> Json.Decode.Pipeline.required "blackPieceFill" decodeColor
        |> Json.Decode.Pipeline.required "blackPieceStroke" decodeColor


encodeColorConfig : ColorConfig -> Json.Encode.Value
encodeColorConfig record =
    Json.Encode.object
        [ ( "whiteTileColor", encodeColor <| record.whiteTileColor )
        , ( "blackTileColor", encodeColor <| record.blackTileColor )
        , ( "borderColor", encodeColor <| record.borderColor )
        , ( "highlightColor", encodeColor <| record.highlightColor )
        , ( "whitePieceFill", encodeColor <| record.whitePieceFill )
        , ( "whitePieceStroke", encodeColor <| record.whitePieceStroke )
        , ( "blackPieceFill", encodeColor <| record.blackPieceFill )
        , ( "blackPieceStroke", encodeColor <| record.blackPieceStroke )
        ]


{-| A color options object that is already "compiled" to strings and can be
used directly in SVG objects.
-}
type alias ColorOptions =
    { whiteTileColor : String
    , blackTileColor : String
    , borderColor : String
    , highlightColor : String
    , whitePieceFill : String
    , whitePieceStroke : String
    , blackPieceFill : String
    , blackPieceStroke : String
    }


configToOptions : ColorConfig -> ColorOptions
configToOptions config =
    { whiteTileColor = Color.toCssString config.whiteTileColor
    , blackTileColor = Color.toCssString config.blackTileColor
    , borderColor = Color.toCssString config.borderColor
    , highlightColor = Color.toCssString config.highlightColor
    , whitePieceFill = Color.toCssString config.whitePieceFill
    , whitePieceStroke = Color.toCssString config.whitePieceStroke
    , blackPieceFill = Color.toCssString config.blackPieceFill
    , blackPieceStroke = Color.toCssString config.blackPieceStroke
    }


getOptionsByName : String -> ColorOptions
getOptionsByName name =
    case name of
        "5aside" ->
            configToOptions fiveAsideBoardColors

        "green" ->
            configToOptions greenBoardColors

        _ ->
            configToOptions defaultBoardColors


{-| Merging the editor piece color choice. This is more of a legacy thing that
will stay in until every part of the website uses a unified color management.
-}
withPieceColorScheme : ColorScheme -> ColorOptions -> ColorOptions
withPieceColorScheme scheme options =
    let
        ( wfr, wfg, wfb ) =
            scheme.white.fill

        ( wsr, wsg, wsb ) =
            scheme.white.stroke

        ( bfr, bfg, bfb ) =
            scheme.black.fill

        ( bsr, bsg, bsb ) =
            scheme.black.stroke
    in
    { options
        | whitePieceFill = Color.rgb255 wfr wfg wfb |> Color.toCssString
        , whitePieceStroke = Color.rgb255 wsr wsg wsb |> Color.toCssString
        , blackPieceFill = Color.rgb255 bfr bfg bfb |> Color.toCssString
        , blackPieceStroke = Color.rgb255 bsr bsg bsb |> Color.toCssString
    }


{-| Copied to avoid cyclic reference and to avoid refactoring for now.
-}
type alias SideColor =
    { fill : ( Int, Int, Int )
    , stroke : ( Int, Int, Int )
    }


{-| Copied to avoid cyclic reference and to avoid refactoring for now.
-}
type alias ColorScheme =
    { white : SideColor
    , black : SideColor
    }
