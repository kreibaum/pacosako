module Pages.Me exposing (Model, Msg, page)

import Browser.Dom
import Custom.Element exposing (icon)
import Custom.Events exposing (fireMsg, forKey, onKeyUpAttr)
import Effect exposing (Effect)
import Element exposing (Element, centerX, centerY, column, el, fill, height, image, maximum, padding, paragraph, px, rgb255, row, spacing, text, width, wrappedRow)
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
import Random exposing (Generator)
import Random.Char
import Random.String
import Request
import Shared
import Svg.Discord
import Task exposing (Task)
import Translations as T
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
            ( LoggedIn
                { user = userData
                , newAvatarsSuggested = []
                , selectedAvatarSuggestion = ""
                , avatarLoadingSpinner = False
                }
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
    , newAvatarsSuggested : List String
    , selectedAvatarSuggestion : String
    , avatarLoadingSpinner : Bool
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
    | RandomizeAvatarSuggestions
    | UpdateAvatarSuggestions (List String)
    | SelectAvatarSuggestion String
    | UpdateAvatar String


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

        RandomizeAvatarSuggestions ->
            ( model, Effect.fromCmd generateRandomStrings )

        UpdateAvatarSuggestions suggestions ->
            updateLoggedIn model (\m -> ( { m | newAvatarsSuggested = suggestions, avatarLoadingSpinner = False }, Effect.none ))

        SelectAvatarSuggestion suggestion ->
            updateLoggedIn model (\m -> ( { m | selectedAvatarSuggestion = suggestion, avatarLoadingSpinner = False }, Effect.none ))

        UpdateAvatar newAvatar ->
            updateLoggedIn model
                (\m ->
                    ( { m | avatarLoadingSpinner = True }
                    , Http.post
                        { url = "/api/me/avatar"
                        , body = Http.stringBody "text/plain" newAvatar
                        , expect = Http.expectWhatever (\_ -> ToShared Shared.TriggerReload)
                        }
                        |> Effect.fromCmd
                    )
                )


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


updateLoggedIn : Model -> (LoggedInModel -> ( LoggedInModel, Effect Msg )) -> ( Model, Effect Msg )
updateLoggedIn model innerUpdate =
    case model of
        LoggedIn innerModel ->
            let
                ( newInnerModel, effects ) =
                    innerUpdate innerModel
            in
            ( LoggedIn newInnerModel, effects )

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
    { title = T.mePageTitle
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
            [ paragraph [ Font.bold ] [ text T.mePageNotLoggedIn ]
            , paragraph [] [ text T.mePageDiscordExplanation ]
            , paragraph []
                [ text T.mePageAccountExplanation ]
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
                (paragraph [] [ text T.mePageDiscordSignIn ])
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
                    , text T.mePageSignInError
                    ]

              else
                Element.none
            , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg UsernameComplete ] ]
                { onChange = SetRawUsername
                , text = model.usernameRaw
                , placeholder = Nothing
                , label = Input.labelAbove [] (text T.mePageUsername)
                }
            , Input.currentPassword
                [ width fill
                , onKeyUpAttr [ forKey "Enter" |> fireMsg (SignIn model.usernameRaw model.passwordRaw) ]
                , Element.htmlAttribute (Html.Attributes.id "password-input")
                ]
                { onChange = SetRawPassword
                , text = model.passwordRaw
                , placeholder = Nothing
                , label = Input.labelAbove [] (text T.mePagePassword)
                , show = False
                }
            , colorButton [ width fill ]
                { background = Element.rgb255 51 191 255
                , backgroundHover = Element.rgb255 102 206 255
                , onPress = Just (SignIn model.usernameRaw model.passwordRaw)
                , buttonIcon =
                    if model.withLoadingSpinner then
                        Element.html
                            (FontAwesome.Icon.viewStyled [ FontAwesome.Attributes.spin ]
                                Solid.spinner
                            )

                    else
                        icon [ centerX ] Solid.arrowCircleRight
                , caption = T.mePageSignIn
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
            [ paragraph [ Font.bold ] [ text T.mePagePrivacyNote ]
            , paragraph [] [ text T.mePagePrivacyNoteL1 ]
            , paragraph [] [ text T.mePagePrivacyNoteL2 ]
            , paragraph [] [ text T.mePagePrivacyNoteL3 ]
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
        [ image [ width (px 100), height (px 100) ]
            { src = model.user.userAvatar, description = T.mePageProfileImageAltText }
        , column []
            [ el [ Font.size 32 ] (text model.user.userName)
            , Input.button []
                { onPress = Just RandomizeAvatarSuggestions
                , label =
                    row
                        [ spacing 10
                        , padding 5
                        , Background.color (Element.rgb255 220 220 220)
                        , Element.mouseOver [ Background.color (Element.rgb255 200 200 200) ]
                        , Border.rounded 5
                        ]
                        [ icon [] Solid.pen
                        , text T.meChangeAvatar
                        ]
                }
            ]
        ]
    , if List.isEmpty model.newAvatarsSuggested then
        Element.none

      else
        column
            [ spacing 10
            , padding 10
            , Background.color (Element.rgba 1 1 1 0.6)
            , Border.rounded 5
            , width fill
            ]
            [ paragraph [ Font.bold ] [ text T.meChoseNewAvatar ]
            , paragraph [] [ text T.meChoseNewAvatarL1 ]
            , wrappedRow [ width fill, spacing 10 ]
                (List.map
                    (\avatar -> avatarSuggestion avatar (avatar == model.selectedAvatarSuggestion))
                    model.newAvatarsSuggested
                )
            , wrappedRow [ spacing 10 ]
                [ colorButton []
                    { background = Element.rgb255 51 191 255
                    , backgroundHover = Element.rgb255 102 206 255
                    , onPress = Just RandomizeAvatarSuggestions
                    , buttonIcon = icon [ centerX ] Solid.dice
                    , caption = T.meNewSuggestions
                    }
                , if not (List.member model.selectedAvatarSuggestion model.newAvatarsSuggested) then
                    colorButton [ Font.color (rgb255 100 100 100) ]
                        { background = Element.rgb255 200 200 200
                        , backgroundHover = Element.rgb255 200 200 200
                        , onPress = Nothing
                        , buttonIcon = icon [ centerX ] Solid.checkCircle
                        , caption = T.meUpdateAvatar
                        }

                  else if model.avatarLoadingSpinner then
                    colorButton []
                        { background = Element.rgb255 51 191 255
                        , backgroundHover = Element.rgb255 102 206 255
                        , onPress = Nothing
                        , buttonIcon =
                            Element.html
                                (FontAwesome.Icon.viewStyled [ FontAwesome.Attributes.spin ]
                                    Solid.spinner
                                )
                        , caption = T.meUpdateAvatar
                        }

                  else
                    colorButton []
                        { background = Element.rgb255 51 191 255
                        , backgroundHover = Element.rgb255 102 206 255
                        , onPress = Just (UpdateAvatar model.selectedAvatarSuggestion)
                        , buttonIcon = icon [ centerX ] Solid.check
                        , caption = T.meUpdateAvatar
                        }
                , colorButton []
                    { background = Element.rgb255 255 68 51
                    , backgroundHover = Element.rgb255 255 102 102
                    , onPress = Just (UpdateAvatarSuggestions [])
                    , buttonIcon = icon [] Solid.times
                    , caption = T.cancel
                    }
                ]
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
                , text T.mePageSignOut
                ]
        }
    ]


colorButton :
    List (Element.Attribute msg)
    ->
        { background : Element.Color
        , backgroundHover : Element.Color
        , onPress : Maybe msg
        , buttonIcon : Element msg
        , caption : String
        }
    -> Element msg
colorButton attrs { background, backgroundHover, onPress, buttonIcon, caption } =
    Input.button
        ([ Background.color background
         , Element.mouseOver [ Background.color backgroundHover ]
         , Border.rounded 5
         ]
            ++ attrs
        )
        { onPress = onPress
        , label =
            Element.row
                [ height fill
                , centerX
                , Element.paddingEach { top = 15, right = 20, bottom = 15, left = 20 }
                , spacing 5
                ]
                [ el [ width (px 20) ] buttonIcon
                , Element.text caption
                ]
        }


avatarSuggestion : String -> Bool -> Element Msg
avatarSuggestion avatar isSelected =
    Input.button []
        { onPress = Just (SelectAvatarSuggestion avatar)
        , label =
            row
                [ spacing 10
                , padding 5
                , if isSelected then
                    Background.color (Element.rgb255 180 180 180)

                  else
                    Background.color (Element.rgb255 220 220 220)
                , Element.mouseOver [ Background.color (Element.rgb255 200 200 200) ]
                , Border.rounded 5
                ]
                [ image [ width (px 50), height (px 50) ]
                    { src = "/p/" ++ avatar, description = T.mePageProfileImageAltText }
                ]
        }


generateRandomStrings : Cmd Msg
generateRandomStrings =
    Random.String.string 32 Random.Char.lowerCaseLatin
        |> Random.map (\s -> "identicon:" ++ s)
        |> Random.list 30
        |> Random.generate UpdateAvatarSuggestions
