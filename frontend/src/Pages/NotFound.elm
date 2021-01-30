module Pages.NotFound exposing (Model, Msg, Params, body, page)

import Element exposing (..)
import Element.Font as Font
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route
import Spa.Page as Page exposing (Page)
import Spa.Url exposing (Url)


type alias Params =
    ()


type alias Model =
    Url Params


type alias Msg =
    Never


page : Page Params Model Msg
page =
    Page.static
        { view = view
        }



-- VIEW


view : Url Params -> Document Msg
view _ =
    { title = "404"
    , body =
        [ body
        ]
    }


body : Element msg
body =
    Element.link [ padding 10, Font.underline, Font.color (Element.rgb 0 0 1) ]
        { url = Route.toString Route.Top, label = text "Page not found. Return to start page." }
