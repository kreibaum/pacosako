module View exposing (View, map, none, placeholder, toBrowserDocument)

import Browser
import Element exposing (Element)
import Html
import Html.Attributes


type alias View msg =
    { title : String
    , element : Element msg
    }


toBrowserDocument : View msg -> Browser.Document msg
toBrowserDocument view =
    { title = view.title
    , body =
        [ Html.canvas [ Html.Attributes.id "offscreen-canvas" ] [ Html.text "Canvas not supported" ]
        , Element.layout [] view.element
        ]
    }


map : (a -> b) -> View a -> View b
map fn view =
    { title = view.title
    , element = Element.map fn view.element
    }


none : View msg
none =
    { title = ""
    , element = Element.none
    }


placeholder : String -> View msg
placeholder pageName =
    { title = pageName
    , element = Element.text pageName
    }
