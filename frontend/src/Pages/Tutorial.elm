module Pages.Tutorial exposing (Model, Msg, page)

import Animation exposing (Timeline)
import Content.References
import Dict exposing (Dict)
import Effect exposing (Effect)
import Element exposing (Element, centerX, centerY, el, fill, height, maximum, padding, paddingEach, paddingXY, paragraph, px, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Embed.Youtube as Youtube
import Embed.Youtube.Attributes as YoutubeA
import Fen
import Gen.Route as Route
import Header
import Layout
import List.Extra as List
import Page
import PositionView exposing (OpaqueRenderData)
import Request exposing (Request)
import Sako
import Set exposing (Set)
import Shared
import StaticAssets
import Svg.Custom exposing (BoardRotation(..))
import Time exposing (Posix)
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
    { enabledVideos : Set String

    -- key => ( isStarted, animation )
    , animations : Dict String ( Bool, Timeline OpaqueRenderData )
    }


init : Shared.Model -> ( Model, Effect Msg )
init _ =
    ( { enabledVideos = Set.empty
      , animations = initialAnimations
      }
    , Effect.none
    )



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | EnableVideo String
    | StartAnimation String
    | AnimationTick Posix


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        EnableVideo url ->
            ( { model | enabledVideos = Set.insert url model.enabledVideos }, Effect.none )

        AnimationTick now ->
            ( { model | animations = updateAnimations now model.animations }, Effect.none )

        StartAnimation key ->
            ( { model | animations = startAnimation key model.animations }, Effect.none )


updateAnimations : Posix -> Dict String ( Bool, Timeline OpaqueRenderData ) -> Dict String ( Bool, Timeline OpaqueRenderData )
updateAnimations now animations =
    Dict.map (updateOneAnimation now) animations


updateOneAnimation : Posix -> String -> ( Bool, Timeline OpaqueRenderData ) -> ( Bool, Timeline OpaqueRenderData )
updateOneAnimation now _ ( isStarted, animation ) =
    if isStarted then
        ( isStarted, Animation.tick now animation )

    else
        ( isStarted, animation )


startAnimation : String -> Dict String ( Bool, Timeline OpaqueRenderData ) -> Dict String ( Bool, Timeline OpaqueRenderData )
startAnimation key animations =
    Dict.update key
        (\_ ->
            Dict.get key initialAnimations
                |> Maybe.map (\( _, animation ) -> ( True, animation ))
        )
        animations


{-| Finds the first started and still running animation to get a subscription.
This subscription will drive all animations.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    model.animations
        |> Dict.values
        |> List.filter (\( isStarted, _ ) -> isStarted)
        |> List.filter (\( _, animation ) -> Animation.isRunning animation)
        |> List.head
        |> Maybe.map (\( _, animation ) -> Animation.subscription animation AnimationTick)
        |> Maybe.withDefault Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.tutorialPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \r -> r == Route.Tutorial
            , isWithBackground = True
            }
            (case T.compiledLanguage of
                English ->
                    textPageWrapper (englishTutorial shared model)

                Dutch ->
                    textPageWrapper (englishTutorial shared model)

                Esperanto ->
                    textPageWrapper
                        [ paragraph [] [ text "Beda\u{00AD}ŭrinde ĉi tiu paĝo ne haveblas en Esperanto :-(" ] ]

                German ->
                    textPageWrapper (englishTutorial shared model)

                Swedish ->
                    textPageWrapper (englishTutorial shared model)

                Spanish ->
                    textPageWrapper (englishTutorial shared model)
            )
    }


textPageWrapper : List (Element msg) -> Element msg
textPageWrapper content =
    Layout.vScollBox
        [ Element.column [ width (fill |> maximum 1000), centerX, padding 10, spacing 10 ]
            content
        ]


grayBox : List (Element msg) -> Element msg
grayBox content =
    Element.column
        [ width fill
        , height fill
        , Background.color (Element.rgba 1 1 1 0.6)
        , Border.rounded 5
        ]
        content


{-| Embeds a youtube video into the website and makes sure the user needs to
confirm before data is loaded from youtube.
-}
youtubeEmbed : ( Int, Int ) -> Set String -> String -> Element Msg
youtubeEmbed ( w, _ ) allowed url =
    let
        videoWidth =
            min 640 (w - 20)

        videoHeight =
            videoWidth * 9 // 16
    in
    if Set.member url allowed then
        Youtube.fromString url
            |> Youtube.attributes
                [ YoutubeA.width videoWidth
                , YoutubeA.height videoHeight
                ]
            |> Youtube.toHtml
            |> Element.html
            |> Element.el [ centerX ]

    else
        Input.button [ centerX ]
            { label =
                Element.el
                    [ width (px videoWidth)
                    , height (px videoHeight)
                    , centerX
                    , Background.image StaticAssets.messyPawns
                    , Font.bold
                    ]
                    (paragraph [ padding 25, centerX, centerY, Font.center ] [ text T.tutorial00ClickToEnableYoutube ])
            , onPress = Just (EnableVideo url)
            }



--------------------------------------------------------------------------------
-- START: Animation Data Section -----------------------------------------------
--------------------------------------------------------------------------------


initialAnimations : Dict String ( Bool, Timeline OpaqueRenderData )
initialAnimations =
    Dict.fromList
        [ ( "traditionalChessAnimation", ( False, traditionalChessAnimation ) )
        , ( "creatingUnionAnimation", ( False, creatingUnionAnimation ) )
        , ( "movingUnionAnimation", ( False, movingUnionAnimation ) )
        , ( "takeoverUnionAnimation", ( False, takeoverUnionAnimation ) )
        , ( "takeoverUnionAnimation2", ( False, takeoverUnionAnimation2 ) )
        , ( "chainAnimation", ( False, chainAnimation ) )
        , ( "promotionAnimation", ( False, promotionAnimation ) )
        ]



-- TODO: Make all the animationEmbed have a play button when not running.
-- Maybe even a restart icon if it has already ran.


{-| Data for this is taken from <https://pacoplay.com/replay/14580>
-}
traditionalChessAnimation : Timeline OpaqueRenderData
traditionalChessAnimation =
    movesToTimeline Sako.initialPosition traditionalChessAnimationData


traditionalChessAnimationData : List (List Sako.Action)
traditionalChessAnimationData =
    [ [ Sako.Lift (Sako.Tile 1 0), Sako.Place (Sako.Tile 2 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 6), Sako.Place (Sako.Tile 3 4) ]
    , []
    , [ Sako.Lift (Sako.Tile 6 0), Sako.Place (Sako.Tile 5 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 7 6), Sako.Place (Sako.Tile 7 4) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 1), Sako.Place (Sako.Tile 3 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 7 7), Sako.Place (Sako.Tile 7 5) ]
    , []
    , [ Sako.Lift (Sako.Tile 2 0), Sako.Place (Sako.Tile 5 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 2 7), Sako.Place (Sako.Tile 6 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 2 2), Sako.Place (Sako.Tile 1 4) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 7), Sako.Place (Sako.Tile 3 5) ]
    , []
    , [ Sako.Lift (Sako.Tile 4 1), Sako.Place (Sako.Tile 4 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 4 6), Sako.Place (Sako.Tile 4 4) ]
    ]


traditionalChessAnimationEnd : Sako.Position
traditionalChessAnimationEnd =
    Sako.doActionsList (List.concat traditionalChessAnimationData) Sako.initialPosition
        |> Maybe.withDefault Sako.emptyPosition


creatingUnionAnimation : Timeline OpaqueRenderData
creatingUnionAnimation =
    movesToTimeline traditionalChessAnimationEnd creatingUnionAnimationData


creatingUnionAnimationData : List (List Sako.Action)
creatingUnionAnimationData =
    [ [ Sako.Lift (Sako.Tile 5 3), Sako.Place (Sako.Tile 4 4) ]
    , []
    , [ Sako.Lift (Sako.Tile 6 3), Sako.Place (Sako.Tile 5 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 1 4), Sako.Place (Sako.Tile 3 5) ]
    ]


creatingUnionAnimationEnd : Sako.Position
creatingUnionAnimationEnd =
    Sako.doActionsList (List.concat creatingUnionAnimationData) traditionalChessAnimationEnd
        |> Maybe.withDefault Sako.emptyPosition


movingUnionAnimation : Timeline OpaqueRenderData
movingUnionAnimation =
    movesToTimeline creatingUnionAnimationEnd movingUnionAnimationData


movingUnionAnimationData : List (List Sako.Action)
movingUnionAnimationData =
    [ [ Sako.Lift (Sako.Tile 4 4), Sako.Place (Sako.Tile 4 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 5 2), Sako.Place (Sako.Tile 6 4) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 5), Sako.Place (Sako.Tile 1 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 1 3), Sako.Place (Sako.Tile 2 5) ]
    , []
    , [ Sako.Lift (Sako.Tile 2 5), Sako.Place (Sako.Tile 6 5) ]
    , []
    , [ Sako.Lift (Sako.Tile 6 4), Sako.Place (Sako.Tile 7 2) ]
    ]


movingUnionAnimationEnd : Sako.Position
movingUnionAnimationEnd =
    Sako.doActionsList (List.concat movingUnionAnimationData) creatingUnionAnimationEnd
        |> Maybe.withDefault Sako.emptyPosition


takeoverUnionAnimation : Timeline OpaqueRenderData
takeoverUnionAnimation =
    movesToTimeline movingUnionAnimationEnd takeoverUnionAnimationData


takeoverUnionAnimationData : List (List Sako.Action)
takeoverUnionAnimationData =
    [ [ Sako.Lift (Sako.Tile 7 5), Sako.Place (Sako.Tile 6 5) ]
    , [ Sako.Place (Sako.Tile 6 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 6 1), Sako.Place (Sako.Tile 7 2) ]
    , [ Sako.Place (Sako.Tile 5 3) ]
    , []
    , [ Sako.Lift (Sako.Tile 5 6), Sako.Place (Sako.Tile 6 5) ]
    , [ Sako.Place (Sako.Tile 2 5) ]
    ]


takeoverUnionAnimation2 : Timeline OpaqueRenderData
takeoverUnionAnimation2 =
    movesToTimeline movingUnionAnimationEnd takeoverUnionAnimation2Data


takeoverUnionAnimation2Data : List (List Sako.Action)
takeoverUnionAnimation2Data =
    [ [ Sako.Lift (Sako.Tile 7 5), Sako.Place (Sako.Tile 6 5) ]
    , [ Sako.Place (Sako.Tile 6 1) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 0), Sako.Place (Sako.Tile 3 2) ]
    , []
    , [ Sako.Lift (Sako.Tile 3 4), Sako.Place (Sako.Tile 4 3) ]
    , [ Sako.Place (Sako.Tile 3 2) ]
    ]


takeoverUnionAnimation2End : Sako.Position
takeoverUnionAnimation2End =
    Sako.doActionsList (List.concat takeoverUnionAnimation2Data) movingUnionAnimationEnd
        |> Maybe.withDefault Sako.emptyPosition


chainAnimation : Timeline OpaqueRenderData
chainAnimation =
    movesToTimeline takeoverUnionAnimation2End chainAnimationData


chainAnimationData : List (List Sako.Action)
chainAnimationData =
    [ [ Sako.Lift (Sako.Tile 2 1), Sako.Place (Sako.Tile 3 2) ]
    , [ Sako.Place (Sako.Tile 4 3) ]
    , [ Sako.Place (Sako.Tile 3 2) ]
    , [ Sako.Place (Sako.Tile 4 3) ]
    , [ Sako.Place (Sako.Tile 4 7) ]
    ]


chainAnimationEnd : Sako.Position
chainAnimationEnd =
    Sako.doActionsList (List.concat chainAnimationData) takeoverUnionAnimation2End
        |> Maybe.withDefault Sako.emptyPosition


promotionAnimation : Timeline OpaqueRenderData
promotionAnimation =
    movesToTimeline
        (Fen.parseFen "1Bk2n2/1Ap4P/rcEi4/1E1pd2q/4ep2/4PnA1/2PQ1P2/3K3R w 0 AHah - -"
            |> Maybe.withDefault Sako.emptyPosition
        )
        promotionAnimationData


promotionAnimationData : List (List Sako.Action)
promotionAnimationData =
    [ [ Sako.Lift (Sako.Tile 7 6), Sako.Place (Sako.Tile 7 7) ]
    , [ Sako.Promote Sako.Queen ]
    , []
    , [ Sako.Lift (Sako.Tile 2 5), Sako.Place (Sako.Tile 4 7) ]
    , [ Sako.Promote Sako.Knight ]
    ]



--------------------------------------------------------------------------------
-- END: Animation Data Section -------------------------------------------------
--------------------------------------------------------------------------------


movesToPositions : Sako.Position -> List (List Sako.Action) -> List Sako.Position
movesToPositions initialPosition moves =
    List.scanl movesToPositionsInner initialPosition moves


movesToPositionsInner : List Sako.Action -> Sako.Position -> Sako.Position
movesToPositionsInner actionsInMove position =
    Sako.doActionsList actionsInMove position
        |> Maybe.withDefault Sako.emptyPosition


positionsToTimeline : List Sako.Position -> Timeline OpaqueRenderData
positionsToTimeline positions =
    let
        head =
            List.head positions |> Maybe.withDefault Sako.emptyPosition

        tail =
            List.drop 1 positions

        initialTimeline =
            Animation.init (PositionView.renderStatic WhiteBottom head)
                |> Animation.queue ( Animation.milliseconds 300, PositionView.renderStatic WhiteBottom head )
    in
    List.foldl
        (\position existingAnimation ->
            existingAnimation
                -- Move to the next position
                |> Animation.queue ( Animation.milliseconds 300, PositionView.renderStatic WhiteBottom position )
                -- Wait there for a bit
                |> Animation.queue ( Animation.milliseconds 300, PositionView.renderStatic WhiteBottom position )
        )
        initialTimeline
        tail


movesToTimeline : Sako.Position -> List (List Sako.Action) -> Timeline OpaqueRenderData
movesToTimeline initialPosition moves =
    movesToPositions initialPosition moves
        |> positionsToTimeline


animationEmbed : Shared.Model -> Model -> String -> Element Msg
animationEmbed shared model key =
    model.animations
        |> Dict.get key
        |> Maybe.map (\( _, animation ) -> animationEmbedInner shared key animation)
        |> Maybe.withDefault (Element.text "Render Error!")
        |> Element.el [ width (Element.maximum 500 fill), centerX ]


animationEmbedInner : Shared.Model -> String -> Timeline OpaqueRenderData -> Element Msg
animationEmbedInner shared key timeline =
    let
        label =
            PositionView.viewTimeline (PositionView.staticViewConfig shared.colorConfig) timeline
    in
    Input.button [ width fill ]
        { onPress = Just (StartAnimation key)
        , label = label
        }


heading : String -> Element msg
heading content =
    paragraph [ paddingEach { top = 20, right = 10, bottom = 10, left = 10 }, Font.size 25 ]
        [ text content ]


textParagraph : String -> Element msg
textParagraph content =
    paragraph [ padding 10, Font.justify ] [ text content ]


englishTutorial : Shared.Model -> Model -> List (Element Msg)
englishTutorial shared model =
    [ grayBox
        [ heading T.tutorial01Introduction1
        , textParagraph T.tutorial01Introduction2
        , textParagraph T.tutorial01Introduction3
        , youtubeEmbed shared.windowSize model.enabledVideos "yJVcQK2gTdM"
        ]
    , grayBox
        [ heading T.tutorial02Movement1
        , textParagraph T.tutorial02Movement2
        , textParagraph T.tutorial02Movement3
        , animationEmbed shared model "traditionalChessAnimation"
        , textParagraph T.tutorial02Movement4
        ]
    , grayBox
        [ heading T.tutorial03CreateUnion1
        , textParagraph T.tutorial03CreateUnion2
        , animationEmbed shared model "creatingUnionAnimation"
        ]
    , grayBox
        [ heading T.tutorial04MoveUnion1
        , textParagraph T.tutorial04MoveUnion2
        , animationEmbed shared model "movingUnionAnimation"
        , textParagraph T.tutorial04MoveUnion3
        ]
    , grayBox
        [ heading T.tutorial05TakeOverUnion1
        , textParagraph T.tutorial05TakeOverUnion2
        , animationEmbed shared model "takeoverUnionAnimation"
        , textParagraph T.tutorial05TakeOverUnion3
        , animationEmbed shared model "takeoverUnionAnimation2"
        ]
    , grayBox
        [ heading T.tutorial06ChainReaction1
        , textParagraph T.tutorial06ChainReaction2
        , textParagraph T.tutorial06ChainReaction3
        , animationEmbed shared model "chainAnimation"
        ]
    , grayBox
        [ heading T.tutorial07EndGoal1
        , textParagraph T.tutorial07EndGoal2
        , textParagraph T.tutorial07EndGoal3
        ]
    , Content.References.discordInvite
    , grayBox
        [ heading T.tutorial08Promotions1
        , textParagraph T.tutorial08Promotions2
        , textParagraph T.tutorial08Promotions3
        , animationEmbed shared model "promotionAnimation"
        ]
    , grayBox
        [ heading T.tutorial09Castling1
        , textParagraph T.tutorial09Castling2
        , textParagraph T.tutorial09Castling3
        , textParagraph T.tutorial09Castling4
        , textParagraph T.tutorial09Castling5
        , textParagraph T.tutorial09Castling6
        ]
    , grayBox
        [ heading T.tutorial10EnPassant1
        , textParagraph T.tutorial10EnPassant2
        , textParagraph T.tutorial10EnPassant3
        , textParagraph T.tutorial10EnPassant4
        ]
    , grayBox
        [ heading T.tutorial11MoreAboutChains1
        , textParagraph T.tutorial11MoreAboutChains2
        , youtubeEmbed shared.windowSize model.enabledVideos "tQ2JLsFvfxI"
        ]
    ]
