module Pages.Me exposing (Model, Msg, page)

import Browser.Dom
import Custom.Element exposing (icon)
import Custom.Events exposing (fireMsg, forKey, onKeyUpAttr)
import Effect exposing (Effect)
import Element exposing (Element, centerX, centerY, column, el, fill, height, image, maximum, padding, paragraph, px, rgb255, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Attributes
import FontAwesome.Icon
import FontAwesome.Solid as Solid
import Gen.Params.Me exposing (Params)
import Header
import Html.Attributes
import Http
import Json.Encode as Encode
import Layout
import Page
import Request
import Shared
import Svg.Discord
import Task
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
            ( NotLoggedIn
                { usernameRaw = ""
                , passwordRaw = ""
                , withError = False
                , withLoadingSpinner = False
                }
            , Effect.none
            )

        Just userData ->
            ( LoggedIn { user = userData }
            , Effect.none
              -- TODO: Load private data about yourself.
            )


type alias NotLoggedInModel =
    { usernameRaw : String
    , passwordRaw : String
    , withError : Bool
    , withLoadingSpinner : Bool
    }


type alias LoggedInModel =
    { user : User.LoggedInUserData
    }



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | NoOp
    | UsernameComplete
    | SignIn String String
    | SignInError
    | SignOut
    | SetRawUsername String
    | SetRawPassword String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        NoOp ->
            ( model, Effect.none )

        UsernameComplete ->
            ( model, Effect.fromCmd focusPasswordInput )

        SignIn username password ->
            updateNotLoggedIn model
                (\m ->
                    ( { m | withLoadingSpinner = True }
                    , Effect.fromCmd (loginCmd username password)
                    )
                )

        SignInError ->
            updateNotLoggedIn model (\m -> ( { m | withError = True, withLoadingSpinner = False }, Effect.none ))

        SignOut ->
            ( model, Effect.fromCmd logoutCmd )

        SetRawUsername rawUsername ->
            updateNotLoggedIn model (\m -> ( { m | usernameRaw = rawUsername }, Effect.none ))

        SetRawPassword rawPassword ->
            updateNotLoggedIn model (\m -> ( { m | passwordRaw = rawPassword }, Effect.none ))


{-| This method applies the update to the "Not Logged In" Model if applicable
and propagate effects. If the model is in any other state, the inner update
function is skipped.
-}
updateNotLoggedIn : Model -> (NotLoggedInModel -> ( NotLoggedInModel, Effect Msg )) -> ( Model, Effect Msg )
updateNotLoggedIn model innerUpdate =
    case model of
        NotLoggedIn innerModel ->
            let
                ( newInnerModel, effects ) =
                    innerUpdate innerModel
            in
            ( NotLoggedIn newInnerModel, effects )

        _ ->
            ( model, Effect.none )


focusPasswordInput : Cmd Msg
focusPasswordInput =
    Task.attempt (\_ -> NoOp) (Browser.Dom.focus "password-input")


loginCmd : String -> String -> Cmd Msg
loginCmd username password =
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
                            -- On success, we can just reload the page and it
                            -- will then have information about the user.
                            -- As most assets are cached, this does not take
                            -- long.
                            ToShared Shared.TriggerReload

                        Err _ ->
                            SignInError
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
subscriptions _ =
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
            (Layout.textPageWrapper (profilePageView model))
    }


{-| Decides which mode of the profile page to show based on whether the user is
logged in and whether their profile data is available.
-}
profilePageView : Model -> List (Element Msg)
profilePageView model =
    case model of
        NotLoggedIn notLoggedInModel ->
            notLoggedInView notLoggedInModel

        LoggedIn loggedInModel ->
            loggedInView loggedInModel


notLoggedInView : NotLoggedInModel -> List (Element Msg)
notLoggedInView model =
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
            [ if model.withError then
                row [ Font.color (rgb255 200 0 0), spacing 5 ]
                    [ icon [ Font.color (rgb255 200 0 0) ] Solid.exclamationTriangle
                    , text "Invalid username or password"
                    ]

              else
                Element.none
            , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg UsernameComplete ] ]
                { onChange = SetRawUsername
                , text = model.usernameRaw
                , placeholder = Nothing
                , label = Input.labelAbove [] (text "Username")
                }
            , Input.currentPassword
                [ width fill
                , onKeyUpAttr [ forKey "Enter" |> fireMsg (SignIn model.usernameRaw model.passwordRaw) ]
                , Element.htmlAttribute (Html.Attributes.id "password-input")
                ]
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
                        [ el [ width (px 20) ]
                            (if model.withLoadingSpinner then
                                Element.el []
                                    (Element.html
                                        (FontAwesome.Icon.viewStyled [ FontAwesome.Attributes.spin ]
                                            Solid.spinner
                                        )
                                    )

                             else
                                icon [ centerX ] Solid.arrowCircleRight
                            )
                        , Element.text "Sign in"
                        ]
                }
            ]
        ]
    , row
        [ spacing 10
        , padding 10
        , Background.color (Element.rgba 1 1 1 0.6)
        , Border.rounded 5
        , width fill
        , Font.size 20
        ]
        [ column [ width fill, spacing 10 ]
            [ paragraph [ Font.bold ] [ text "Privacy Note:" ]
            , paragraph [] [ text "Any games you play and all other things you create on this page are public and permanent." ]
            , paragraph [] [ text "Your account is visible for everyone, even to users without accounts." ]
            , paragraph []
                [ text "You can delete your account at any point. The games and other things you have created will stay publicly available, but will no longer be linked to you." ]
            ]
        ]
    ]


loggedInView : LoggedInModel -> List (Element Msg)
loggedInView model =
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
