module Spa.Document exposing
    ( Document
    , map
    , toBrowserDocument
    )

import Browser
import Element exposing (..)
import Element.Font as Font
import Html
import Html.Attributes


type alias Document msg =
    { title : String
    , body : List (Element msg)
    }


map : (msg1 -> msg2) -> Document msg1 -> Document msg2
map fn doc =
    { title = doc.title
    , body = List.map (Element.map fn) doc.body
    }


toBrowserDocument : Document msg -> Browser.Document msg
toBrowserDocument doc =
    { title = doc.title
    , body =
        [ Html.canvas [ Html.Attributes.id "offscreen-canvas" ] [ Html.text "Canvas not supported" ]
        , Element.layout
            [ width fill
            , height fill
            , Font.family
                [ Font.typeface "Roboto"
                , Font.sansSerif
                ]
            ]
            (column [ width fill, height fill ] doc.body)
        ]
    }
