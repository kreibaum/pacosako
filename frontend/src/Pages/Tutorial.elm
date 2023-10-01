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

                Spanish ->
                    textPageWrapper
                        [ paragraph [] [ text "Lamentablemente, todavía no tenemos un manual en español :-(" ] ]
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
                Element.el [ width (px videoWidth), height (px videoHeight), centerX, Background.color (Element.rgb 0.9 0.9 0.8) ]
                    (paragraph [ padding 25, centerX, centerY, Font.center ] [ text "Click to enable video. By clicking, you'll load content from YouTube." ])
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
    , [ Sako.Lift (Sako.Tile 3 6), Sako.Place (Sako.Tile 3 4) ]
    , [ Sako.Lift (Sako.Tile 6 0), Sako.Place (Sako.Tile 5 2) ]
    , [ Sako.Lift (Sako.Tile 7 6), Sako.Place (Sako.Tile 7 4) ]
    , [ Sako.Lift (Sako.Tile 3 1), Sako.Place (Sako.Tile 3 3) ]
    , [ Sako.Lift (Sako.Tile 7 7), Sako.Place (Sako.Tile 7 5) ]
    , [ Sako.Lift (Sako.Tile 2 0), Sako.Place (Sako.Tile 5 3) ]
    , [ Sako.Lift (Sako.Tile 2 7), Sako.Place (Sako.Tile 6 3) ]
    , [ Sako.Lift (Sako.Tile 2 2), Sako.Place (Sako.Tile 1 4) ]
    , [ Sako.Lift (Sako.Tile 3 7), Sako.Place (Sako.Tile 3 5) ]
    , [ Sako.Lift (Sako.Tile 4 1), Sako.Place (Sako.Tile 4 2) ]
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
    , [ Sako.Lift (Sako.Tile 6 3), Sako.Place (Sako.Tile 5 2) ]
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
    , [ Sako.Lift (Sako.Tile 5 2), Sako.Place (Sako.Tile 6 4) ]
    , [ Sako.Lift (Sako.Tile 3 5), Sako.Place (Sako.Tile 1 3) ]
    , [ Sako.Lift (Sako.Tile 1 3), Sako.Place (Sako.Tile 2 5) ]
    , [ Sako.Lift (Sako.Tile 2 5), Sako.Place (Sako.Tile 6 5) ]
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
    , [ Sako.Lift (Sako.Tile 6 1), Sako.Place (Sako.Tile 7 2) ]
    , [ Sako.Place (Sako.Tile 5 3) ]
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
    , [ Sako.Lift (Sako.Tile 3 0), Sako.Place (Sako.Tile 3 2) ]
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
        [ heading "An Introduction to Paco Ŝako"
        , textParagraph """Paco Ŝako is a game about Peace
            created by the Dutch Artist Felix Albers.The name Paco Ŝako means
            "Peace Chess" in Esperanto, the language of peace."""
        , textParagraph """This first part of the tutorial is also
            available on Youtube, if you prefer to learn from a video."""
        , youtubeEmbed shared.windowSize model.enabledVideos "yJVcQK2gTdM"
        ]
    , grayBox
        [ heading "The Movement of Pieces"
        , textParagraph """Each Paco Ŝako piece moves in the same way as a traditional chess piece.
            This tutorial assumes you already have a basic understanding of chess."""
        , textParagraph """Here is an opening from game of Paco Ŝako where some
            regular moves are played. Click or tap to play!"""
        , animationEmbed shared model "traditionalChessAnimation"
        , textParagraph """While these moves follow the rules of chess, you'll find
            the look quite reckless. Both players place their valuable pieces
            directly on threatened squares. What is going on here?"""
        ]
    , grayBox
        [ heading "Creating a Union"
        , textParagraph """In Paco Ŝako you never remove the other player's pieces.
            Instead you have the option to unite your piece with their pieces.
            Both player's pieces remain on the board. Play the animation to see this in action!"""
        , animationEmbed shared model "creatingUnionAnimation"
        ]
    , grayBox
        [ heading "Moving a union"
        , textParagraph """Once united, both players can keep on playing with that union.
            You may only move the union according to the rules of movement of your own piece."""
        , animationEmbed shared model "movingUnionAnimation"
        , textParagraph """If your piece is in a union, we are calling it "united".
            You can not move a piece out of the union on its own. You always
            have to take its parter as well. To free your piece from a union, 
            another piece must take over."""
        ]
    , grayBox
        [ heading "Taking over a Union"
        , textParagraph """You can take over a union by playing one of your pieces
            into a union and replacing your original piece. You can then place
            the free piece according to its movement rules in the same turn."""
        , animationEmbed shared model "takeoverUnionAnimation"
        , textParagraph """Instead of moving from the union to an open square,
            the freed piece can also be used to create  a new union."""
        , animationEmbed shared model "takeoverUnionAnimation2"
        ]
    , grayBox
        [ heading "The Chain Reaction"
        , textParagraph """It is also possible to take over another union.
            This creates a chain reaction."""
        , textParagraph """Chain reactions move a lot of your pieces at the same time.
            They are a powerful way to reshape your position on the board and
            have an outstanding impact on the gameplay. As you gain experience,
            you'll be able to find longer and longer chains to do more in a single move."""
        , animationEmbed shared model "chainAnimation"
        ]
    , grayBox
        [ heading "The End Goal"
        , textParagraph """The end goal is to be the first player to unite one
            of your pieces with the other player's king. This means the
            king can never form a union, start a chain or be used in a chain."""
        , textParagraph """You now know the basic rules of Paco Ŝako can are
            ready to play a game. You can play online with a friend or you can
            join our community Discord to find somebody to play with."""
        ]
    , Content.References.discordInvite
    , grayBox
        [ heading "Promotions"
        , textParagraph """A pawn that reaches the opposite side of the board
            must be promoted to a different piece. The player who owns the piece
            gets to chose one of "queen", "knight", "bishop" or "rook"."""
        , textParagraph """
            A difference in Paco Ŝako is, that a pawn can be moved to the opposite
            side of the board as part of a union. In this case it also promotes
            and it is still the owner of the pawn who decides the promotion."""
        , animationEmbed shared model "promotionAnimation"
        ]
    , grayBox
        [ heading "Castling"
        , textParagraph """Castling is a special move which moves the king
            two squares toward a rook and then moving the rook to the square
            that the king passed over."""
        , textParagraph """To castle, select the king first. You'll be offered
            an option to move it two squares. The rook will be moved for you
            automatically."""
        , textParagraph """ You are only allowed to castle, if neither
            the king nor the rook has moved before. All squares between
            the pieces must be empty. Any square the king moves over can not
            be threatened."""
        , textParagraph """In Paco Ŝako, this also includes any threat that is
            created through a chain. This sometimes makes it hard to know,
            if you are actually allowed to castle. When playing on this website,
            you can just lift the king and it will only offer you to castle
            when it is allowed."""
        , textParagraph """Castling at the right moment or denying your opponent
            the opportunity to castle, is often an important part of the stategy."""
        ]
    , grayBox
        [ heading "En Passant"
        , textParagraph """En passant is a special way for a pawn to form a union.
            Directly after a pawn is moved two squares at once, the opponents pawns
            are allowed to unite with it, as if it only moved a single square."""
        , textParagraph """On this website you will be offered the move,
            whenever you lift a pawn that is allowed to unite en passant."""
        , textParagraph """In Paco Ŝako, en passant is allowed at the start,
            in the middle and at the end of a chain."""
        ]
    , grayBox
        [ heading "Learn more about Chains from Felix"
        , textParagraph """You can learn more about chains and loop from Felix Albers,
            the creator Paco Ŝako. This video gives a short recap of this
            tutorial and then more aspects and situations of the game in the second
            part of the video at 1:10."""
        , youtubeEmbed shared.windowSize model.enabledVideos "tQ2JLsFvfxI"
        ]
    ]
