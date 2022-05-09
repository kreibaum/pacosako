module Pages.Settings exposing (Model, Msg, Params, page)

import Color exposing (Color)
import ColorPicker
import Effect exposing (Effect)
import Element exposing (column)
import Element.Input as Input
import Html
import Page
import Request
import Shared
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
    { oneColor : Color
    , colorPicker : ColorPicker.State
    }


init : Shared.Model -> ( Model, Effect Msg )
init _ =
    ( initModel
    , Effect.none
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


update : Msg -> Model -> ( Model, Effect Msg )
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
            , Effect.none
            )

        ResetColorScheme ->
            ( initModel, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> View Msg
view model =
    { title = "Settings"
    , element =
        column []
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
    }
