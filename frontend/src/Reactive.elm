module Reactive exposing (Device(..), classify)


type Device
    = LandscapeDevice
    | PortraitDevice


{-| Everything that is about square or wider is Landscape, otherwise it is
portrait.

I only want to switch to Portrait Device mode if the screen is clearly longer
than wide like on a smartphone. So I am using height / width > 4 / 3

-}
classify : ( Int, Int ) -> Device
classify ( width, height ) =
    if height * 3 < width * 4 then
        LandscapeDevice

    else
        PortraitDevice
