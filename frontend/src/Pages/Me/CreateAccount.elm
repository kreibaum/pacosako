module Pages.Me.CreateAccount exposing (Model, Msg, page)

import Components exposing (colorButton, grayBox, heading, textParagraph)
import Custom.Element exposing (icon)
import Dict exposing (Dict)
import Effect exposing (Effect)
import Element exposing (Element, centerX, el, height, image, padding, paddingEach, px, row, spacing, text, width)
import Element.Font as Font
import FontAwesome.Solid as Solid
import Gen.Params.Me.CreateAccount exposing (Params)
import Header
import Http
import Layout
import Page
import Request
import Shared
import Translations as T
import Url exposing (Protocol(..))
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared { query } =
    Page.advanced
        { init = init query
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }


{-| <http://localhost:8000/me/create-account?encrypted_access_token=DFww8JcMG5AU+fO2:hgsYXWluRZvDhnkGGtlDF2G2N31vnYzkdI6oj0zGfJvr806n2QJJebtPfLot/w==&user_display_name=Rolf%20Kreibaum&user_discord_id=613051631516254210>
-}
type alias CreateAccountQuery =
    { encryptedAccessToken : String
    , userDisplayName : String
    , userDiscordId : String
    }


parseQuery : Dict String String -> Maybe CreateAccountQuery
parseQuery query =
    Maybe.map3 CreateAccountQuery
        (Dict.get "encrypted_access_token" query)
        (Dict.get "user_display_name" query)
        (Dict.get "user_discord_id" query)


type StateMachine
    = WaitsForUserConfirmation
    | WaitsForServerResponse
    | HttpError



-- INIT


type alias Model =
    { data : Maybe CreateAccountQuery
    , state : StateMachine
    }


init : Dict String String -> ( Model, Effect Msg )
init query =
    ( { data = parseQuery query
      , state = WaitsForUserConfirmation
      }
    , Effect.none
    )



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | CreateAccount
    | LoginError Http.Error


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        CreateAccount ->
            -- /api/oauth/pleaseCreateAccount?encrypted_access_token={{ encrypted_access_token }}
            case model.data of
                Just data ->
                    ( { model | state = WaitsForServerResponse }
                    , Http.get
                        { url = "/api/oauth/pleaseCreateAccount?encrypted_access_token=" ++ data.encryptedAccessToken
                        , expect =
                            Http.expectWhatever
                                (\res ->
                                    case res of
                                        Ok _ ->
                                            ToShared (Shared.NavigateTo "/me")

                                        Err e ->
                                            LoginError e
                                )
                        }
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        LoginError _ ->
            ( { model | state = HttpError }, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.createAccountPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = True
            }
            (Layout.textPageWrapper
                (case model.data of
                    Just data ->
                        innerView data

                    Nothing ->
                        [ text "Invalid query" ]
                )
            )
    }


innerView : CreateAccountQuery -> List (Element Msg)
innerView data =
    [ grayBox []
        [ heading "Create an Account"
        , textParagraph "You don't have an account on PacoPlay yet. Do you want to create an account linked to your Discord profile?"
        ]
    , el [ centerX, padding 40 ]
        (grayBox []
            [ row [ padding 10, spacing 10 ]
                [ image [ width (px 100), height (px 100) ]
                    { src = "/p/identicon:" ++ data.userDiscordId, description = T.mePageProfileImageAltText }
                , el [ Font.size 32 ] (text data.userDisplayName)
                ]
            ]
        )
    , grayBox []
        [ heading "About the Avatar"
        , textParagraph "This avatar was randomly generated for you. You can change it later. Discord profile pictures are not supported to ease moderation."
        ]
    , grayBox []
        [ heading "What Data Will Be Stored?"
        , textParagraph "We will store your Discord user ID and your display name. We will not store your email address or any other personal information. (We didn't even get that from Discord.)"
        , textParagraph "Any games you play on PacoPlay while logged in will be associated with your account. They are public."
        , textParagraph "You can delete your account at any time. The games will remain public, but become anonymous: your name and avatar will be removed."
        , heading "Ready to Go?"
        , el
            [ paddingEach
                { top = 0
                , bottom = 20
                , left = 20
                , right = 20
                }
            ]
            (colorButton []
                { background = Element.rgb255 41 204 57
                , backgroundHover = Element.rgb255 68 229 84
                , onPress = Just CreateAccount
                , buttonIcon = icon [ centerX ] Solid.check
                , caption = "Create My Account!"
                }
            )
        ]
    ]
