module Pages.Login exposing (Model, Msg, Params, getCurrentLogin, page)

import Custom.Events exposing (fireMsg, forKey, onKeyUpAttr)
import Effect exposing (Effect)
import Element exposing (Element, padding, spacing)
import Element.Border as Border
import Element.Input as Input
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Page exposing (Page)
import RemoteData exposing (RemoteData)
import Request
import Shared exposing (User)
import Spa.Url exposing (Url)
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init shared
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- INIT


type alias Params =
    ()


type alias Model =
    { usernameRaw : String
    , passwordRaw : String
    , user : RemoteData () User
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { usernameRaw = ""
      , passwordRaw = ""
      , user = initUser shared.user
      }
    , Effect.none
    )


initUser : Maybe User -> RemoteData a User
initUser maybeUser =
    maybeUser
        |> Maybe.map RemoteData.Success
        |> Maybe.withDefault RemoteData.NotAsked



-- UPDATE


type Msg
    = TypeUsername String
    | TypePassword String
    | TryLogin
    | LoggedIn User
    | DoLogout
    | LoggedOut
    | LoginError


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        TypeUsername raw ->
            ( { model | usernameRaw = raw }, Effect.none )

        TypePassword raw ->
            ( { model | passwordRaw = raw }, Effect.none )

        TryLogin ->
            ( { model | user = RemoteData.Loading }
            , postLoginPassword
                { password = model.passwordRaw
                , username = model.usernameRaw
                }
                |> Effect.fromCmd
            )

        DoLogout ->
            ( { model
                | user = RemoteData.Loading
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , getLogout |> Effect.fromCmd
            )

        LoggedOut ->
            ( { model
                | user = RemoteData.NotAsked
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , Effect.none
            )

        LoggedIn user ->
            ( { model
                | user = RemoteData.Success user
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , Effect.none
            )

        LoginError ->
            ( { model | user = RemoteData.Failure () }, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> View Msg
view model =
    { title = "Log in to Paco Play"
    , element =
        case model.user of
            RemoteData.Success user ->
                loginInfoPage user

            RemoteData.NotAsked ->
                loginDialog { isFailed = False, isWaiting = False } model

            RemoteData.Failure () ->
                loginDialog { isFailed = True, isWaiting = False } model

            RemoteData.Loading ->
                loginDialog { isFailed = False, isWaiting = True } model
    }


loginDialog : { isFailed : Bool, isWaiting : Bool } -> Model -> Element Msg
loginDialog params model =
    Element.column [ padding 10, spacing 10, Element.centerX, Element.centerY ]
        [ Input.username []
            { label = Input.labelAbove [] (Element.text "Username")
            , onChange = TypeUsername
            , placeholder = Just (Input.placeholder [] (Element.text "Username"))
            , text = model.usernameRaw
            }
        , Input.currentPassword [ onKeyUpAttr [ forKey "Enter" |> fireMsg TryLogin ] ]
            { label = Input.labelAbove [] (Element.text "Password")
            , onChange = TypePassword
            , placeholder = Just (Input.placeholder [] (Element.text "Password"))
            , text = model.passwordRaw
            , show = False
            }
        , if params.isWaiting then
            Input.button [] { label = Element.text "Logging in ...", onPress = Nothing }

          else
            Input.button [ Element.alignRight ] { label = Element.text "Login", onPress = Just TryLogin }
        , if params.isFailed then
            Element.text "Error while logging in"

          else
            Element.none
        ]
        |> thinBorder


loginInfoPage : User -> Element Msg
loginInfoPage user =
    Element.column [ Element.centerX, Element.centerY ]
        [ Element.text ("Username: " ++ user.username)
        , Element.text ("ID: " ++ String.fromInt user.id)
        , Input.button [] { label = Element.text "Logout", onPress = Just DoLogout }
        ]


thinBorder : Element msg -> Element msg
thinBorder content =
    Element.el
        [ Border.color (Element.rgb255 230 230 230)
        , Border.rounded 5
        , Border.width 1
        , Element.centerX
        , Element.centerY
        ]
        content



-- API


type alias LoginData =
    { username : String
    , password : String
    }


encodeLoginData : LoginData -> Value
encodeLoginData record =
    Encode.object
        [ ( "username", Encode.string <| record.username )
        , ( "password", Encode.string <| record.password )
        ]


decodeUser : Decoder User
decodeUser =
    Decode.map2 User
        (Decode.field "user_id" Decode.int)
        (Decode.field "username" Decode.string)


postLoginPassword : LoginData -> Cmd Msg
postLoginPassword data =
    Http.post
        { url = "/api/login/password"
        , body = Http.jsonBody (encodeLoginData data)
        , expect =
            Http.expectJson
                (\res ->
                    case res of
                        Ok user ->
                            LoggedIn user

                        Err _ ->
                            LoginError
                )
                decodeUser
        }


{-| Gets information on the currently logged in user. This method will not
differentiate between "no user logged in" and an http error. The shared logic
is expected to trigger this to decide if the user is logged in or not.
-}
getCurrentLogin : (Maybe User -> msg) -> Cmd msg
getCurrentLogin toMessage =
    Http.get
        { url = "/api/user_id"
        , expect =
            Http.expectJson
                (\result ->
                    case result of
                        Ok maybeUser ->
                            toMessage maybeUser

                        Err _ ->
                            toMessage Nothing
                )
                (Decode.maybe decodeUser)
        }


getLogout : Cmd Msg
getLogout =
    Http.get
        { url = "/api/logout"
        , expect =
            Http.expectWhatever
                (\res ->
                    case res of
                        Err _ ->
                            LoginError

                        Ok () ->
                            LoggedOut
                )
        }
