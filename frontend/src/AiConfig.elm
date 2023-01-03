module AiConfig exposing (AiConfig, AiControl(..), Msg, RawAiConfig, init, parseSelf, reduce, update, view)

{-| This module contains the configuration setup for the ai, including the view
and the model.
-}

import Components
import Custom.Element as Element
import Element exposing (Element, centerX, fill, px, spacing, width)
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import Translations as T


{-| Determines which pieces the ai plays with.
-}
type AiControl
    = AiControlWhite
    | AiControlBlack
    | AiControlBoth


type alias AiConfig =
    { control : AiControl
    , exploration : Float
    , liftPower : Int
    , chainPower : Int
    }


type alias RawAiConfig =
    { control : AiControl
    , exploration : Float
    , explorationRaw : String
    , liftPower : Int
    , liftPowerRaw : String
    , chainPower : Int
    , chainPowerRaw : String
    }


init : RawAiConfig
init =
    { control = AiControlWhite
    , exploration = 0.1
    , explorationRaw = "0.1"
    , liftPower = 200
    , liftPowerRaw = "200"
    , chainPower = 100
    , chainPowerRaw = "100"
    }


parseSelf : RawAiConfig -> RawAiConfig
parseSelf data =
    { data
        | exploration = String.toFloat data.explorationRaw |> Maybe.withDefault data.exploration
        , liftPower = String.toInt data.liftPowerRaw |> Maybe.withDefault data.liftPower
        , chainPower = String.toInt data.chainPowerRaw |> Maybe.withDefault data.chainPower
    }


reduce : RawAiConfig -> AiConfig
reduce data =
    { control = data.control
    , exploration = data.exploration
    , liftPower = data.liftPower
    , chainPower = data.chainPower
    }


type Msg
    = SetControl AiControl
    | SetExploration String
    | SetLiftPower String
    | SetChainPower String
    | Remove


view : (Msg -> msg) -> RawAiConfig -> Element msg
view wrapper data =
    Components.glassContainerWithTitle T.configureAi
        [ Element.paragraph [ Font.bold ] [ Element.text T.aiEarlyAccessExplanation ]
        , playAsSelection wrapper data.control
        , Element.text "Evaluation Model: Luna"
        , Input.text []
            { onChange = SetLiftPower >> wrapper
            , text = data.liftPowerRaw
            , placeholder = Just (Input.placeholder [] (Element.text "A whole number"))
            , label = Input.labelLeft [] (Element.text "Lift Power")
            }
        , Input.text []
            { onChange = SetChainPower >> wrapper
            , text = data.chainPowerRaw
            , placeholder = Just (Input.placeholder [] (Element.text "A whole number"))
            , label = Input.labelLeft [] (Element.text "Chain Power")
            }
        , Input.text []
            { onChange = SetExploration >> wrapper
            , text = data.explorationRaw
            , placeholder = Just (Input.placeholder [] (Element.text "A number between 0 and 1"))
            , label = Input.labelLeft [] (Element.text "Exploration")
            }
        , Components.button2
            { colorScheme = Components.red
            , onPress = Components.ButtonClickable (Remove |> wrapper)
            , contentRow =
                [ Element.el [ width (px 20) ] (Element.icon [ centerX ] Solid.trash)
                , Element.text "Remove AI"
                ]
            }
        ]


playAsSelection : (Msg -> msg) -> AiControl -> Element msg
playAsSelection wrapper control =
    let
        onPressFkt =
            ifeq control (\_ -> Components.ButtonActivated) (SetControl >> wrapper >> Components.ButtonClickable)
    in
    Element.row [ spacing 5, width fill ]
        [ Element.text "Ai plays:"
        , Components.button2
            { colorScheme = Components.gray
            , onPress = onPressFkt AiControlWhite
            , contentRow = [ Element.text "White" ]
            }
        , Components.button2
            { colorScheme = Components.gray
            , onPress = onPressFkt AiControlBlack
            , contentRow = [ Element.text "Black" ]
            }
        , Components.button2
            { colorScheme = Components.gray
            , onPress = onPressFkt AiControlBoth
            , contentRow = [ Element.text "Both" ]
            }
        ]


ifeq : a -> (a -> b) -> (a -> b) -> a -> b
ifeq checkAgainst ifTrue ifFalse data =
    if checkAgainst == data then
        ifTrue data

    else
        ifFalse data


update : Msg -> RawAiConfig -> Maybe RawAiConfig
update msg data =
    case msg of
        SetControl control ->
            Just { data | control = control }

        SetExploration exploration ->
            Just ({ data | explorationRaw = exploration } |> parseSelf)

        SetLiftPower liftPower ->
            Just ({ data | liftPowerRaw = liftPower } |> parseSelf)

        SetChainPower chainPower ->
            Just ({ data | chainPowerRaw = chainPower } |> parseSelf)

        Remove ->
            Nothing
