module Colors exposing
    ( BoardColorConfig
    , ColorConfig
    , ColorOptions
    , configToOptions
    , decodeColorConfig
    , defaultBoardColors
    , encodeColorConfig
    , getOptionsByName
    , suggestedBoardColors
    , toElement
    , withBoardColorConfig
    , withPieceColorScheme
    )

{-| Module that captures all the types and helper methods I have for colors.
-}

import Color exposing (Color)
import Element
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


type alias BoardColorConfig =
    { whiteTileColor : Color
    , blackTileColor : Color
    , borderColor : Color
    , highlightColor : Color
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


toElement : Color -> Element.Color
toElement color =
    let
        record =
            Color.toRgba color
    in
    Element.rgba record.red record.green record.blue record.alpha


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


{-| Merging the editor piece color choice. This is important to separately choose
the piece colors from the board colors.
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


withBoardColorConfig : BoardColorConfig -> ColorConfig -> ColorConfig
withBoardColorConfig config options =
    { options
        | whiteTileColor = config.whiteTileColor
        , blackTileColor = config.blackTileColor
        , borderColor = config.borderColor
        , highlightColor = config.highlightColor
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


yellowFelixHighlight : Color
yellowFelixHighlight =
    Color.rgba 1 0.933333333 0.631372549 0.5


greenFelixHighlight : Color
greenFelixHighlight =
    Color.rgba 0.592156863 1 0.607843137 0.5


blueFelixHighlight : Color
blueFelixHighlight =
    Color.rgba 0.615686275 0.937254902 0.97254902 0.5


suggestedBoardColors : List BoardColorConfig
suggestedBoardColors =
    [ -- Pastel Grey (Felix)
      { whiteTileColor = Color.rgb255 241 241 241
      , blackTileColor = Color.rgb255 180 180 180
      , borderColor = Color.rgb255 153 153 153
      , highlightColor = greenFelixHighlight
      }

    -- Pastel Blue (Felix)
    , { whiteTileColor = Color.rgb255 203 213 222
      , blackTileColor = Color.rgb255 95 125 154
      , borderColor = Color.rgb255 66 81 110
      , highlightColor = yellowFelixHighlight
      }

    -- Pastel Green (Felix)
    , { whiteTileColor = Color.rgb255 235 235 213
      , blackTileColor = Color.rgb255 106 137 85
      , borderColor = Color.rgb255 82 102 60
      , highlightColor = yellowFelixHighlight
      }

    -- Pastel Turquoise (Felix)
    , { whiteTileColor = Color.rgb255 229 241 239
      , blackTileColor = Color.rgb255 85 148 142
      , borderColor = Color.rgb255 72 130 138
      , highlightColor = yellowFelixHighlight
      }

    -- Pastel Wood (Felix)
    , { whiteTileColor = Color.rgb255 244 228 219
      , blackTileColor = Color.rgb255 183 139 111
      , borderColor = Color.rgb255 143 113 101
      , highlightColor = blueFelixHighlight
      }

    -- Pastel Purple (Felix)
    , { whiteTileColor = Color.rgb255 243 226 229
      , blackTileColor = Color.rgb255 149 121 152
      , borderColor = Color.rgb255 111 85 115
      , highlightColor = yellowFelixHighlight
      }

    -- Intense Blue (Felix)
    , { whiteTileColor = Color.rgb255 146 213 188
      , blackTileColor = Color.rgb255 0 101 122
      , borderColor = Color.rgb255 0 56 85
      , highlightColor = greenFelixHighlight
      }

    -- Intense Red (Felix)
    , { whiteTileColor = Color.rgb255 234 208 197
      , blackTileColor = Color.rgb255 159 58 51
      , borderColor = Color.rgb255 130 45 41
      , highlightColor = yellowFelixHighlight
      }

    -- Intense Purple (Felix)
    , { whiteTileColor = Color.rgb255 246 204 201
      , blackTileColor = Color.rgb255 135 87 141
      , borderColor = Color.rgb255 91 62 120
      , highlightColor = blueFelixHighlight
      }

    -- Intense Green (Original)
    , { whiteTileColor = Color.rgb255 153 255 153
      , blackTileColor = Color.rgb255 85 153 85
      , borderColor = Color.rgb255 34 68 34
      , highlightColor = Color.rgba 1 1 0 0.5
      }

    -- Intense Orange (Felix)
    , { whiteTileColor = Color.rgb255 249 220 192
      , blackTileColor = Color.rgb255 228 85 39
      , borderColor = Color.rgb255 195 53 16
      , highlightColor = blueFelixHighlight
      }

    -- Intense Wood (Felix)
    , { whiteTileColor = Color.rgb255 227 198 171
      , blackTileColor = Color.rgb255 126 79 57
      , borderColor = Color.rgb255 83 51 44
      , highlightColor = blueFelixHighlight
      }
    , { whiteTileColor = Color.hsl 0.4 0.2 0.9
      , blackTileColor = Color.hsl 0.4 0.4 0.4
      , borderColor = Color.hsl 0.4 0.3 0.3
      , highlightColor = Color.rgba 1 1 0 0.52
      }
    , { whiteTileColor = Color.rgb255 153 153 255
      , blackTileColor = Color.rgb255 85 85 153
      , borderColor = Color.rgb255 34 34 68
      , highlightColor = Color.rgba 0 1 1 0.5
      }
    , { whiteTileColor = Color.hsl 0.55 0.2 0.9
      , blackTileColor = Color.hsl 0.55 0.4 0.4
      , borderColor = Color.hsl 0.55 0.3 0.3
      , highlightColor = Color.rgba 1 1 0 0.52
      }
    , { whiteTileColor = Color.hsl 0.7 0.2 0.9
      , blackTileColor = Color.hsl 0.7 0.3 0.4
      , borderColor = Color.hsl 0.7 0.3 0.3
      , highlightColor = Color.rgba 1 0.7 1 0.6
      }
    , { whiteTileColor = Color.hsl 0.11 0.2 0.9
      , blackTileColor = Color.hsl 0.11 0.4 0.4
      , borderColor = Color.hsl 0.11 0.3 0.3
      , highlightColor = Color.rgba 1 1 0 0.52
      }
    , { whiteTileColor = Color.rgb255 227 229 241
      , blackTileColor = Color.rgb255 140 142 153
      , borderColor = Color.rgb255 85 84 91
      , highlightColor = greenFelixHighlight
      }
    ]
