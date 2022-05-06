module Pages.Login exposing (Model, Msg, Params, getCurrentLogin, page)

import Api.Backend exposing (DiscordApplicationId(..))
import Effect exposing (Effect)
import Element exposing (Element, padding, spacing)
import Element.Border as Border
import Element.Input as Input
import Http
import Json.Decode as Decode exposing (Decoder)
import Page
import RemoteData exposing (RemoteData)
import Request
import Shared exposing (User)
import Url exposing (Url)
import Url.Builder
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared request =
    Page.advanced
        { init = init shared
        , update = update
        , subscriptions = subscriptions
        , view = view shared request.url
        }



-- INIT


type alias Params =
    ()


type alias Model =
    { usernameRaw : String
    , passwordRaw : String
    , user : RemoteData () User
    , discordApplicationId : Maybe DiscordApplicationId
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { usernameRaw = ""
      , passwordRaw = ""
      , user = initUser shared.user
      , discordApplicationId = Nothing
      }
    , Api.Backend.getDiscordApplicationId (\_ -> LoginError) SetDiscordAppId
        |> Effect.fromCmd
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
    | LoggedIn User
    | DoLogout
    | LoggedOut
    | LoginError
    | SetDiscordAppId DiscordApplicationId


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        TypeUsername raw ->
            ( { model | usernameRaw = raw }, Effect.none )

        TypePassword raw ->
            ( { model | passwordRaw = raw }, Effect.none )

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

        SetDiscordAppId id ->
            ( { model | discordApplicationId = Just id }, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Url -> Model -> View Msg
view shared url model =
    { title = "Log in to Paco Play"
    , element =
        case model.discordApplicationId of
            Just id ->
                discordLoginButton url shared.oAuthState id

            Nothing ->
                Element.none
    }


redirectUrl : Url -> String -> DiscordApplicationId -> String
redirectUrl url oAuthState (DiscordApplicationId id) =
    let
        redirectUri =
            (case url.protocol of
                Url.Https ->
                    "https://"

                Url.Http ->
                    "http://"
            )
                ++ url.host
                ++ (case url.port_ of
                        Just port_ ->
                            ":" ++ String.fromInt port_

                        Nothing ->
                            ""
                   )
                ++ "/api/oauth/redirect"
    in
    Url.Builder.crossOrigin "https://discord.com"
        [ "api", "oauth2", "authorize" ]
        [ Url.Builder.string "client_id" id
        , Url.Builder.string "response_type" "code"
        , Url.Builder.string "scope" "identify"
        , Url.Builder.string "state" oAuthState
        , Url.Builder.string "redirect_uri" redirectUri

        -- You can set "consent" here which forces the user to accept the connection.
        , Url.Builder.string "prompt" "none"
        ]


discordLoginButton : Url -> String -> DiscordApplicationId -> Element Msg
discordLoginButton url oAuthState (DiscordApplicationId id) =
    Element.link []
        { url =
            redirectUrl url oAuthState (DiscordApplicationId id)
        , label = Element.text "Log in with Discord"
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
        , Input.currentPassword []
            { label = Input.labelAbove [] (Element.text "Password")
            , onChange = TypePassword
            , placeholder = Just (Input.placeholder [] (Element.text "Password"))
            , text = model.passwordRaw
            , show = False
            }
        , if params.isWaiting then
            Input.button [] { label = Element.text "Logging in ...", onPress = Nothing }

          else
            Input.button [ Element.alignRight ] { label = Element.text "Login", onPress = Nothing }
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


decodeUser : Decoder User
decodeUser =
    Decode.map2 User
        (Decode.field "user_id" Decode.int)
        (Decode.field "username" Decode.string)


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
