module Pages.Tutorial exposing (Model, Msg, page)

import Effect exposing (Effect)
import Element exposing (Element, centerX, el, fill, height, maximum, padding, paddingXY, paragraph, spacing, text, width)
import Element.Background as Background
import Element.Font as Font
import Embed.Youtube as Youtube
import Embed.Youtube.Attributes as YoutubeA
import Gen.Route as Route
import Header
import Layout
import Page
import Request exposing (Request)
import Shared
import Translations as T exposing (Language(..))
import View exposing (View)


page : Shared.Model -> Request -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init shared
        , update = update
        , subscriptions = subscriptions
        , view = view shared
        }



-- INIT


type alias Model =
    ()


init : Shared.Model -> ( Model, Effect Msg )
init _ =
    ( (), Effect.none )



-- UPDATE


type Msg
    = ToShared Shared.Msg


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared _ =
    { title = T.tutorialPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \r -> r == Route.Tutorial
            , isWithBackground = True
            }
            (case T.compiledLanguage of
                English ->
                    textPageWrapper (englishTutorial shared.windowSize)

                Dutch ->
                    dutchTutorial shared

                Esperanto ->
                    textPageWrapper
                        [ paragraph [] [ text "Beda\u{00AD}ŭrinde ĉi tiu paĝo ne haveblas en Esperanto :-(" ] ]

                German ->
                    textPageWrapper
                        [ paragraph [] [ text "Wir haben leider noch keine deutsche Anleitung :-(" ] ]

                Swedish ->
                    textPageWrapper
                        [ paragraph [] [ text "Tyvärr har vi ingen svensk manual än :-(" ] ]
            )
    }


textPageWrapper : List (Element msg) -> Element msg
textPageWrapper content =
    Layout.vScollBox
        [ Element.column [ width (fill |> maximum 1000), centerX, padding 10, spacing 10 ]
            content
        ]


{-| The tutorial needs only a language and this is stored outside. It contains
the language toggle for now, so it needs to be taught to send language messages.
-}
dutchTutorial : Shared.Model -> Element msg
dutchTutorial shared =
    Layout.vScollBox
        [ Element.column [ width (fill |> maximum 1000), centerX, paddingXY 10 20, spacing 10 ]
            [ "Leer Paco Ŝako"
                |> text
                |> el [ Font.size 40, centerX ]
            , paragraph []
                [ "Felix bereidt een reeks video-instructies over Paco Ŝako voor. Je kunt ze hier en op zijn YouTube-kanaal vinden." |> text ]
            , oneVideo shared.windowSize ( "Opstelling", Just "1jybatEtdPo" )
            , oneVideo shared.windowSize ( "Beweging van de stukken", Just "mCoara3xUlk" )
            , oneVideo shared.windowSize ( "4 Paco Ŝako Regles", Just "zEq1fqBoL9M" )
            , oneVideo shared.windowSize ( "Doel Van Het Spel", Nothing )
            , oneVideo shared.windowSize ( "Combo's, Loop, Ketting", Nothing )
            , oneVideo shared.windowSize ( "Strategie", Nothing )
            , oneVideo shared.windowSize ( "Opening, Middenspel, Eindspel", Nothing )
            , oneVideo shared.windowSize ( "Rokeren, Promoveren, En Passant", Nothing )
            , oneVideo shared.windowSize ( "Creatieve Speelwijze", Nothing )
            , oneVideo shared.windowSize ( "Spel Plezier & Schoonheid", Nothing )
            ]
        ]


oneVideo : ( Int, Int ) -> ( String, Maybe String ) -> Element msg
oneVideo ( w, _ ) ( caption, link ) =
    let
        videoWidth =
            min 640 (w - 20)

        videoHeight =
            videoWidth * 9 // 16
    in
    Element.column
        [ width fill
        , height fill
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        [ paragraph [ padding 10 ] [ text caption |> el [ Font.size 25 ] ]
        , case link of
            Just videoKey ->
                Youtube.fromString videoKey
                    |> Youtube.attributes
                        [ YoutubeA.width videoWidth
                        , YoutubeA.height videoHeight
                        ]
                    |> Youtube.toHtml
                    |> Element.html
                    |> Element.el []

            Nothing ->
                paragraph []
                    [ "Felix bereidt momenteel deze video voor." |> text ]
        ]


grayBox : List (Element msg) -> Element msg
grayBox content =
    Element.column
        [ width fill
        , height fill
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        content


englishTutorial : ( Int, Int ) -> List (Element msg)
englishTutorial ( w, _ ) =
    let
        videoWidth =
            min 640 (w - 20)

        videoHeight =
            videoWidth * 9 // 16
    in
    [ grayBox
        [ paragraph [ padding 10 ] [ text "A short introduction to Paco Ŝako" |> el [ Font.size 25 ] ]
        , paragraph [ padding 10 ] [ text """Paco Ŝako pieces move just like traditional chess pieces.
            But instead of removing the opponents pieces you form unions. This video shows you
            how to create and move a union and how you can then take over existing unions
            to play with chain reactions.""" ]
        , Youtube.fromString "yJVcQK2gTdM"
            |> Youtube.attributes
                [ YoutubeA.width videoWidth
                , YoutubeA.height videoHeight
                ]
            |> Youtube.toHtml
            |> Element.html
            |> Element.el []
        ]
    , grayBox
        [ paragraph [ padding 10 ] [ text "Learn more about Chains from Felix" |> el [ Font.size 25 ] ]
        , paragraph [ padding 10 ] [ text "Learn more about chains and loop from Felix Albers, the creator Paco Ŝako." ]
        , Youtube.fromString "tQ2JLsFvfxI"
            |> Youtube.attributes
                [ YoutubeA.width videoWidth
                , YoutubeA.height videoHeight
                ]
            |> Youtube.toHtml
            |> Element.html
            |> Element.el []
        ]
    , grayBox
        [ paragraph [ padding 10 ]
            [ text "Paco Ŝako is a game about Peace created by the Dutch Artist Felix Albers. On the "
            , Element.newTabLink [ Font.underline, Font.color (Element.rgb 0 0 1) ]
                { url = "http://pacosako.com/en"
                , label = Element.text "Paco Ŝako website"
                }
            , text """ Felix explains, that the name Paco Ŝako means "Peace Chess"
                in Esperanto (An international constructed language of peace.)"""
            ]
        ]
    ]
