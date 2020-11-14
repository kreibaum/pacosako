module Pages.Login exposing (Model, Msg, Params, getCurrentLogin, page)

import Element exposing (Element, padding, spacing)
import Element.Border as Border
import Element.Input as Input
import EventsCustom exposing (onEnter)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import RemoteData exposing (RemoteData)
import Shared exposing (User)
import Spa.Document exposing (Document)
import Spa.Page as Page exposing (Page)
import Spa.Url exposing (Url)


page : Page Params Model Msg
page =
    Page.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , save = save
        , load = load
        }



-- INIT


type alias Params =
    ()


type alias Model =
    { usernameRaw : String
    , passwordRaw : String
    , user : RemoteData () User
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared _ =
    ( { usernameRaw = ""
      , passwordRaw = ""
      , user = initUser shared.user
      }
    , Cmd.none
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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TypeUsername raw ->
            ( { model | usernameRaw = raw }, Cmd.none )

        TypePassword raw ->
            ( { model | passwordRaw = raw }, Cmd.none )

        TryLogin ->
            ( { model | user = RemoteData.Loading }
            , postLoginPassword
                { password = model.passwordRaw
                , username = model.usernameRaw
                }
            )

        DoLogout ->
            ( { model
                | user = RemoteData.Loading
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , getLogout
            )

        LoggedOut ->
            ( { model
                | user = RemoteData.NotAsked
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , Cmd.none
            )

        LoggedIn user ->
            ( { model
                | user = RemoteData.Success user
                , usernameRaw = ""
                , passwordRaw = ""
              }
            , Cmd.none
            )

        LoginError ->
            ( { model | user = RemoteData.Failure () }, Cmd.none )


save : Model -> Shared.Model -> Shared.Model
save model shared =
    { shared | user = RemoteData.toMaybe model.user }


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( { model | user = initUser shared.user }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Document Msg
view model =
    { title = "Log in to Paco Play"
    , body =
        [ case model.user of
            RemoteData.Success user ->
                loginInfoPage user

            RemoteData.NotAsked ->
                loginDialog { isFailed = False, isWaiting = False } model

            RemoteData.Failure () ->
                loginDialog { isFailed = True, isWaiting = False } model

            RemoteData.Loading ->
                loginDialog { isFailed = False, isWaiting = True } model
        ]
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
        , Input.currentPassword [ onEnter TryLogin ]
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
