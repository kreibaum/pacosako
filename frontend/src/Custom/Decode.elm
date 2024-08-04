module Custom.Decode exposing (decodeConstant)

import Json.Decode as Decode exposing (Decoder)


{-| Decoder to be used with oneOf that checks one of the possibilities.
-}
decodeConstant : String -> a -> Decoder a
decodeConstant tag value =
    Decode.string
        |> Decode.andThen
            (\s ->
                if s == tag then
                    Decode.succeed value

                else
                    Decode.fail (s ++ " is not " ++ tag)
            )
