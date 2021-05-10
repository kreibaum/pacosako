module Pages.NotFound exposing (Params, body, page)

import Element exposing (..)
import Element.Font as Font
import Gen.Route as Route
import Page exposing (Page)
import Request
import Shared
import View exposing (View)


type alias Params =
    ()


page : Shared.Model -> Request.With Params -> Page
page _ _ =
    Page.static
        { view = view
        }



-- VIEW


view : View msg
view =
    { title = "404"
    , element =
        body
    }


body : Element msg
body =
    Element.link [ padding 10, Font.underline, Font.color (Element.rgb 0 0 1) ]
        { url = Route.toHref Route.Home_, label = text "Page not found. Return to start page." }
