module Pages.Tutorial exposing (Model, Msg, page)

import Effect exposing (Effect)
import Element exposing (Element, centerX, el, fill, height, maximum, padding, paragraph, scrollbarY, spacing, text, width)
import Element.Background as Background
import Element.Font as Font
import Embed.Youtube as Youtube
import Embed.Youtube.Attributes as YoutubeA
import Header
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
        (case T.compiledLanguage of
            English ->
                textPageWrapper englishTutorial

            Dutch ->
                dutchTutorial

            Esperanto ->
                textPageWrapper
                    [ text "Beda\u{00AD}ŭrinde ĉi tiu paĝo ne haveblas en Esperanto :-(" ]

            German ->
                textPageWrapper
                    [ text "Wir haben leider noch keine deutsche Anleitung :-(" ]
        )
            |> Header.wrapWithHeader shared ToShared
    }


textPageWrapper : List (Element msg) -> Element msg
textPageWrapper content =
    Element.el [ width fill, height fill, scrollbarY ]
        (Element.column [ width (fill |> maximum 1000), centerX, padding 30, spacing 10 ]
            content
        )


{-| The tutorial needs only a language and this is stored outside. It contains
the language toggle for now, so it needs to be taught to send language messages.
-}
dutchTutorial : Element msg
dutchTutorial =
    Element.el [ width fill, height fill, scrollbarY ]
        tutorialPageInner


tutorialPageInner : Element msg
tutorialPageInner =
    Element.column [ width (fill |> maximum 1000), centerX, padding 30, spacing 10 ]
        [ "Leer Paco Ŝako"
            |> text
            |> el [ Font.size 40, centerX ]
        , paragraph []
            [ "Felix bereidt een reeks video-instructies over Paco Ŝako voor. Je kunt ze hier en op zijn YouTube-kanaal vinden." |> text ]
        , oneVideo ( "Opstelling", Just "1jybatEtdPo" )
        , oneVideo ( "Beweging van de stukken", Just "mCoara3xUlk" )
        , oneVideo ( "4 Paco Ŝako Regles", Just "zEq1fqBoL9M" )
        , oneVideo ( "Doel Van Het Spel", Nothing )
        , oneVideo ( "Combo's, Loop, Ketting", Nothing )
        , oneVideo ( "Strategie", Nothing )
        , oneVideo ( "Opening, Middenspel, Eindspel", Nothing )
        , oneVideo ( "Rokeren, Promoveren, En Passant", Nothing )
        , oneVideo ( "Creatieve Speelwijze", Nothing )
        , oneVideo ( "Spel Plezier & Schoonheid", Nothing )
        ]


oneVideo : ( String, Maybe String ) -> Element msg
oneVideo ( caption, link ) =
    grayBox
        [ text caption |> el [ Font.size 25 ]
        , case link of
            Just videoKey ->
                Youtube.fromString videoKey
                    |> Youtube.attributes
                        [ YoutubeA.width 640
                        , YoutubeA.height 400
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
        , spacing 10
        , padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        content


englishTutorial : List (Element msg)
englishTutorial =
    [ grayBox
        [ text "A short introduction to Paco Ŝako" |> el [ Font.size 25 ]
        , paragraph [] [ text """Paco Ŝako pieces move just like traditional chess pieces.
            But instead of removing the opponents pieces you form unions. This video shows you
            how to create and move a union and how you can then take over existing unions
            to play with chain reactions.""" ]
        , Youtube.fromString "yJVcQK2gTdM"
            |> Youtube.attributes
                [ YoutubeA.width 640
                , YoutubeA.height 400
                ]
            |> Youtube.toHtml
            |> Element.html
            |> Element.el []
        ]
    , grayBox
        [ text "Learn more about Chains from Felix" |> el [ Font.size 25 ]
        , paragraph [] [ text "Learn more about chains and loop from Felix Albers, the creator Paco Ŝako." ]
        , Youtube.fromString "tQ2JLsFvfxI"
            |> Youtube.attributes
                [ YoutubeA.width 640
                , YoutubeA.height 400
                ]
            |> Youtube.toHtml
            |> Element.html
            |> Element.el []
        ]
    , grayBox
        [ paragraph []
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
