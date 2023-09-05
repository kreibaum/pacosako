port module Api.LocalStorage exposing
    ( CustomTimer
    , Data
    , LocalStorage
    , Permission(..)
    , load
    , setPermission
    , store
    , subscribeSave
    , triggerSave
    )

{-| This module handles storing information in Local Storage as well as a
version history for it. Please keep in mind that we should always ask before
storing user information. This means each piece of data has a permission
attached to it that determines if it should be saved.

The format is:

    { version = Int
    , data = DataVx
    , permissions = [ Permission ]
    }

-}

import Colors exposing (ColorConfig)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import Maybe


{-| Usable Local Storage object with all the migration details taken care of.
-}
type alias LocalStorage =
    { data : Data
    , permissions : List Permission
    }


decodeLocalStorage : Decoder LocalStorage
decodeLocalStorage =
    Decode.map2 LocalStorage
        decodeData
        (Decode.field "permissions" decodePermissionList)


{-| Stores the Data in the lastest version.
-}
encodeLocalStorage : LocalStorage -> Value
encodeLocalStorage ls =
    Encode.object
        [ ( "version", Encode.int latestVersion )
        , ( "data", encodeData ls.data )
        , ( "permissions", Encode.list encodePermission ls.permissions )
        ]


port writeToLocalStorage : Value -> Cmd msg


{-| Writes a LocalStorage object to the browsers local storage for later
retrival. Takes care of censorship.
-}
store : LocalStorage -> Cmd msg
store ls =
    { ls | data = censor ls.permissions ls.data }
        |> encodeLocalStorage
        |> writeToLocalStorage


{-| Tries to load data from local storage. If this fails for any reason a
default object is returned.
-}
load : Value -> LocalStorage
load value =
    Decode.decodeValue (Decode.field "localStorage" decodeLocalStorage) value
        |> Result.toMaybe
        |> Maybe.withDefault { data = defaultData, permissions = [] }


{-| A single permission that we got from the user. This module takes care of
only storing information that we have permissions for.

Data without permission:

  - Language: The language is not transfered to the server.

-}
type Permission
    = Username
    | HideGamesArePublicHint


setPermission : Permission -> Bool -> List Permission -> List Permission
setPermission entry shouldBeInList list =
    if shouldBeInList then
        if List.member entry list then
            list

        else
            entry :: list

    else
        List.remove entry list


encodePermission : Permission -> Value
encodePermission p =
    case p of
        Username ->
            Encode.string "Username"

        HideGamesArePublicHint ->
            Encode.string "HideGamesArePublicHint"


decodePermission : Decoder Permission
decodePermission =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "Username" ->
                        Decode.succeed Username

                    "HideGamesArePublicHint" ->
                        Decode.succeed HideGamesArePublicHint

                    otherwise ->
                        Decode.fail ("Not a permission: " ++ otherwise)
            )


{-| A defensive list decoder that will just discard entries that fail to decode
instead of failing the whole decode process.
-}
decodePermissionList : Decoder (List Permission)
decodePermissionList =
    Decode.list Decode.value
        |> Decode.map decodeDefensive


decodeDefensive : List Value -> List Permission
decodeDefensive values =
    List.filterMap
        (Decode.decodeValue decodePermission >> Result.toMaybe)
        values


{-| The latest data object for local storage. If the user is using an outdated
data model, it will be migrated automatically to the lastest version on load.
-}
type alias Data =
    DataV1


defaultData : Data
defaultData =
    { username = ""
    , recentCustomTimes = []
    , playSounds = True
    , colorConfig = Colors.defaultBoardColors
    }


latestVersion : Int
latestVersion =
    1


{-| While there are multiple decoders, there is only one encoder.
-}
encodeData : Data -> Value
encodeData data =
    Encode.object
        [ ( "username", Encode.string data.username )
        , ( "recentCustomTimes", Encode.list encodeCustomTimer data.recentCustomTimes )
        , ( "playSounds", Encode.bool data.playSounds )
        , ( "colorConfig", Colors.encodeColorConfig data.colorConfig )
        ]


decodeData : Decoder Data
decodeData =
    Decode.field "version" Decode.int
        |> Decode.andThen (\version -> decodeDataVersioned version)


decodeDataVersioned : Int -> Decoder Data
decodeDataVersioned version =
    case version of
        1 ->
            Decode.field "data" decodeDataV1 |> Decode.map migrateDataV1

        _ ->
            Decode.fail "Version not supported, local storage corrupted."


{-| We don't want to store data where the user has not given us permission to
store it.
-}
censor : List Permission -> Data -> Data
censor permissions data =
    data
        |> censorUser permissions


type alias DataV1 =
    { username : String
    , recentCustomTimes : List CustomTimer
    , playSounds : Bool
    , colorConfig : ColorConfig
    }


{-| A timer setting the user can define themself. This is in LocalStorage because
we persist it.
-}
type alias CustomTimer =
    { minutes : Int, seconds : Int, increment : Int }


migrateDataV1 : DataV1 -> Data
migrateDataV1 dataV1 =
    dataV1


censorUser : List Permission -> Data -> Data
censorUser permissions data =
    if List.member Username permissions then
        data

    else
        { data | username = "" }


decodeDataV1 : Decoder DataV1
decodeDataV1 =
    Decode.map4 DataV1
        (Decode.field "username" Decode.string)
        (Decode.maybe (Decode.field "recentCustomTimes" (Decode.list decodeCustomTimer))
            |> Decode.map (Maybe.withDefault [])
        )
        (Decode.maybe (Decode.field "playSounds" Decode.bool)
            |> Decode.map (Maybe.withDefault True)
        )
        (Decode.maybe (Decode.field "colorConfig" Colors.decodeColorConfig)
            |> Decode.map (Maybe.withDefault Colors.defaultBoardColors)
        )


decodeCustomTimer : Decoder CustomTimer
decodeCustomTimer =
    Decode.map3 CustomTimer
        (Decode.field "minutes" Decode.int)
        (Decode.field "seconds" Decode.int)
        (Decode.field "increment" Decode.int)


encodeCustomTimer : CustomTimer -> Value
encodeCustomTimer record =
    Encode.object
        [ ( "minutes", Encode.int <| record.minutes )
        , ( "seconds", Encode.int <| record.seconds )
        , ( "increment", Encode.int <| record.increment )
        ]



--------------------------------------------------------------------------------
--- Trampoline functionality ---------------------------------------------------
--------------------------------------------------------------------------------
-- The trampolineIn and trampolineOut are a way to send a global message.
-- This is used to trigger a save of the local storage from any component.
-- The Shared.Model itself is updated by the page's save method.


port trampolineOut : () -> Cmd msg


port trampolineIn : (() -> msg) -> Sub msg


{-| Make sure to always trigger this port when you update data that should be
stored in local storage. The Shared Module will then automatically respond and
trigger a save.
-}
triggerSave : Cmd msg
triggerSave =
    trampolineOut ()


subscribeSave : msg -> Sub msg
subscribeSave msg =
    trampolineIn (\() -> msg)
