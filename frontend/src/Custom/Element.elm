module Custom.Element exposing (icon)

import Element exposing (Element)
import FontAwesome.Icon exposing (Icon, viewIcon)


{-| Render an icon into an Element with the given attributes.
-}
icon : List (Element.Attribute msg) -> Icon -> Element msg
icon attributes iconType =
    Element.el attributes (Element.html (viewIcon iconType))
