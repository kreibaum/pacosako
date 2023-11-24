module Pages.Me exposing (Model, Msg, page)

import Custom.Element exposing (icon)
import Effect exposing (Effect)
import Element exposing (Element, centerX, centerY, column, el, fill, height, image, maximum, padding, paragraph, px, rgb255, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import Gen.Params.Me exposing (Params)
import Header
import Http
import Json.Encode as Encode
import Layout
import Page
import Request
import Shared
import Svg.Discord
import Url exposing (Protocol(..))
import User
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init shared
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type Model
    = NotLoggedIn NotLoggedInModel
    | LoggedIn LoggedInModel


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    case shared.loggedInUser of
        Nothing ->
            ( NotLoggedIn { usernameRaw = "", passwordRaw = "" }
            , Effect.none
            )

        Just userData ->
            ( LoggedIn { user = userData }
            , Effect.none
              -- TODO: Load data
            )


type alias NotLoggedInModel =
    { usernameRaw : String
    , passwordRaw : String
    }


type alias LoggedInModel =
    { user : User.LoggedInUserData
    }



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | SignIn String String
    | SignOut
    | SetRawUsername String
    | SetRawPassword String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        SignIn username password ->
            ( model, Effect.fromCmd (loginCmd username password) )

        SignOut ->
            ( model, Effect.fromCmd logoutCmd )

        SetRawUsername rawUsername ->
            case model of
                NotLoggedIn notLoggedInModel ->
                    ( NotLoggedIn { notLoggedInModel | usernameRaw = rawUsername }, Effect.none )

                _ ->
                    ( model, Effect.none )

        SetRawPassword rawPassword ->
            case model of
                NotLoggedIn notLoggedInModel ->
                    ( NotLoggedIn { notLoggedInModel | passwordRaw = rawPassword }, Effect.none )

                _ ->
                    ( model, Effect.none )


loginCmd : String -> String -> Cmd Msg
loginCmd username password =
    -- TODO: loading spinner or something...
    Http.post
        { url = "/api/username_password"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "username", Encode.string username )
                    , ( "password", Encode.string password )
                    ]
                )
        , expect =
            Http.expectWhatever
                (\res ->
                    case res of
                        Ok _ ->
                            ToShared Shared.TriggerReload

                        Err _ ->
                            -- TODO: Error handling
                            ToShared Shared.TriggerReload
                )
        }


logoutCmd : Cmd Msg
logoutCmd =
    Http.get
        { url = "/api/logout"
        , expect = Http.expectWhatever (\_ -> ToShared Shared.TriggerReload)
        }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Me"
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = True
            }
            (Layout.textPageWrapper (profilePageView shared model))
    }


{-| Decides which mode of the profile page to show based on whether the user is
logged in and whether their profile data is available.
-}
profilePageView : Shared.Model -> Model -> List (Element Msg)
profilePageView shared model =
    case model of
        NotLoggedIn notLoggedInModel ->
            notLoggedInView shared notLoggedInModel

        LoggedIn loggedInModel ->
            loggedInView shared loggedInModel


notLoggedInView : Shared.Model -> NotLoggedInModel -> List (Element Msg)
notLoggedInView shared model =
    [ row
        [ spacing 10
        , padding 10
        , Background.color (Element.rgba 1 1 1 0.6)
        , Border.rounded 5
        , width fill
        , Font.size 20
        ]
        [ column [ width fill, spacing 10 ]
            [ paragraph [ Font.bold ] [ text "You are not logged in right now." ]
            , paragraph [] [ text "New accounts will be set up by logging in with Discord. (Still under construction)" ]
            , paragraph []
                [ text "A user account helps you keep track of the games you have played and the people you have played with. But you'll always be able to play on our site without creating an account." ]
            ]
        ]
    , row [ width fill, spacing 10 ]
        [ column
            [ width fill
            , height fill
            , centerX
            , spacing 7
            , padding 10
            , Background.color (Element.rgba 1 1 1 0.6)
            ]
            [ el
                [ width (fill |> maximum 400)
                , padding 10
                , centerX
                , centerY
                ]
                Svg.Discord.discordLogo
            , el
                [ Font.color Svg.Discord.discordLogoColor
                , Font.size 25
                , centerX
                , centerY
                ]
                (paragraph [] [ text "Log in with Discord (Under construction)" ])
            ]
        , column
            [ spacing 10
            , padding 10
            , Background.color (Element.rgba 1 1 1 0.6)
            , Border.rounded 5
            , width fill
            , height fill
            ]
            [ Input.text [ width fill ]
                -- TODO: On Enter, go to password field
                { onChange = SetRawUsername
                , text = model.usernameRaw
                , placeholder = Nothing
                , label = Input.labelAbove [] (text "Username")
                }
            , Input.currentPassword [ width fill ]
                -- TODO: On Enter, submit form
                { onChange = SetRawPassword
                , text = model.passwordRaw
                , placeholder = Nothing
                , label = Input.labelAbove [] (text "Password")
                , show = False
                }
            , Input.button
                [ Background.color (Element.rgb255 51 191 255)
                , Element.mouseOver [ Background.color (Element.rgb255 102 206 255) ]
                , Border.rounded 5
                , width fill
                ]
                { onPress = Just (SignIn model.usernameRaw model.passwordRaw)
                , label =
                    Element.row
                        [ height fill
                        , centerX
                        , Element.paddingEach { top = 15, right = 20, bottom = 15, left = 20 }
                        , spacing 5
                        ]
                        [ el [ width (px 20) ] (icon [ centerX ] Solid.arrowCircleRight)
                        , Element.text "Sign in"
                        ]
                }
            ]
        ]
    ]


loggedInView : Shared.Model -> LoggedInModel -> List (Element Msg)
loggedInView shared model =
    [ row
        [ spacing 10
        , padding 10
        , Background.color (Element.rgba 1 1 1 0.6)
        , Border.rounded 5
        , width fill
        ]
        [ image [ width (px 100), height (px 100) ] { src = model.user.userAvatar, description = "Your current profile picture" }
        , el [ Font.size 32 ] (text model.user.userName)
        ]
    , Input.button [ width fill ]
        { onPress = Just SignOut
        , label =
            row
                [ spacing 10
                , padding 10
                , Background.color (Element.rgba 1 1 1 0.6)
                , Border.rounded 5
                , width fill
                , Font.size 20
                ]
                [ icon [ Font.color (rgb255 200 0 0) ] Solid.signOutAlt
                , text "Sign out"
                ]
        }
    ]
