module User exposing (LoggedInUserData, parseLoggedInUser)

{-| User management module.
-}

import Json.Decode as Decode exposing (Decoder, Value)


{-| Data that the frontend has on the logged in user.
-}
type alias LoggedInUserData =
    { userName : String
    , userId : Int
    , userAvatar : String
    }


parseLoggedInUser : Value -> Maybe LoggedInUserData
parseLoggedInUser flags =
    Decode.decodeValue decodeLoggedInUser flags
        |> Result.toMaybe
        |> Maybe.andThen
            (\userData ->
                if checkUsernameNonEmpty userData then
                    Just userData

                else
                    Nothing
            )


decodeLoggedInUser : Decoder LoggedInUserData
decodeLoggedInUser =
    Decode.map3 LoggedInUserData
        (Decode.field "myUserName" Decode.string)
        (Decode.field "myUserId" Decode.int)
        (Decode.field "myUserAvatar" Decode.string)


checkUsernameNonEmpty : LoggedInUserData -> Bool
checkUsernameNonEmpty userData =
    not (String.isEmpty userData.userName)
