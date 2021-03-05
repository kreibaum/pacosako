module Pages.Settings exposing (Model, Msg, Params, page)

import Color exposing (Color)
import ColorPicker
import Element exposing (column, el)
import Element.Input as Input
import Html
import Shared
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
    { oneColor : Color
    , colorPicker : ColorPicker.State
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared { params } =
    ( initModel
    , Cmd.none
    )


initModel : { oneColor : Color, colorPicker : ColorPicker.State }
initModel =
    { oneColor = Color.lightGreen
    , colorPicker = ColorPicker.empty
    }



-- UPDATE


type Msg
    = ColorPickerMsg ColorPicker.Msg
    | ResetColorScheme


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ColorPickerMsg cpMsg ->
            let
                ( m, newColor ) =
                    ColorPicker.update cpMsg model.oneColor model.colorPicker
            in
            ( { model
                | colorPicker = m
                , oneColor = newColor |> Maybe.withDefault model.oneColor
              }
            , Cmd.none
            )

        ResetColorScheme ->
            ( initModel, Cmd.none )


save : Model -> Shared.Model -> Shared.Model
save model shared =
    shared


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Document Msg
view model =
    { title = "Settings"
    , body =
        [ column []
            [ Element.text "Customize your colors"
            , Input.button []
                { onPress = Just ResetColorScheme
                , label = Element.text "Reset to defaults"
                }
            , Element.html
                (ColorPicker.view model.oneColor model.colorPicker
                    |> Html.map ColorPickerMsg
                )
            ]
        ]
    }
