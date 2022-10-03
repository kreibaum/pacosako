module Reactive exposing (Classification(..), DeviceOrientation(..), classify, orientation)


type DeviceOrientation
    = Landscape
    | Portrait


{-| Everything that is about square or wider is Landscape, otherwise it is
portrait.

I only want to switch to Portrait Device mode if the screen is clearly longer
than wide like on a smartphone. So I am using height / width > 4 / 3

-}
orientation : ( Int, Int ) -> DeviceOrientation
orientation ( width, height ) =
    if height * 3 < width * 4 then
        Landscape

    else
        Portrait


type Classification
    = Phone
    | Tablet
    | Desktop


classify : ( Int, Int ) -> Classification
classify ( width, height ) =
    if width < 550 then
        Phone

    else if width < 750 then
        Tablet

    else
        Desktop
