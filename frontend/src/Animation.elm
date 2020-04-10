module Animation exposing
    ( AnimationProperty(..)
    , AnimationState
    , Timeline
    , animate
    , animateProperty
    , init
    , milliseconds
    , subscription
    , tick
    )

{-| This module is heavily inspired by mdgriffith/elm-animator. I am building my
own version to have direct access to internals.
-}

import Browser.Events
import Time exposing (Posix)


{-| Duration in milliseconds
-}
type Duration
    = Duration Int


timeInOrder : Posix -> Posix -> Bool
timeInOrder old new =
    Time.posixToMillis old <= Time.posixToMillis new


milliseconds : Int -> Duration
milliseconds =
    Duration


addDuration : Duration -> Posix -> Posix
addDuration (Duration d) old =
    Time.millisToPosix (Time.posixToMillis old + d)


inverseLerp : Posix -> Posix -> Posix -> Float
inverseLerp old new now =
    toFloat (Time.posixToMillis now - Time.posixToMillis old)
        / toFloat (Time.posixToMillis new - Time.posixToMillis old)


type alias Timeline event =
    { now : Posix
    , old : ( Posix, event )
    , new : Maybe ( Posix, event )
    , queued : List ( Duration, event )

    --, interrupt : Bool
    , running : Bool
    }


{-| Create a timeline with an initial `state`.
-}
init : event -> Timeline event
init initial =
    { now = Time.millisToPosix 0
    , old = ( Time.millisToPosix 0, initial )
    , new = Nothing
    , queued = []

    --, interrupt = False
    , running = True
    }


{-| Use this subscription to drive the animation with request animaton frame.
-}
subscription : Timeline event -> (Time.Posix -> msg) -> Sub msg
subscription timeline wrapper =
    if timeline.running then
        Browser.Events.onAnimationFrame wrapper

    else
        Sub.none


tick : Posix -> Timeline event -> Timeline event
tick now timeline =
    { timeline | now = now }
        |> schedule


{-| Schedule queued events
-}
schedule : Timeline event -> Timeline event
schedule timeline =
    case timeline.new of
        Just ( newTime, value ) ->
            if timeInOrder timeline.now newTime then
                timeline

            else
                scheduleNothingPlanned
                    { timeline
                        | old = ( newTime, value )
                        , new = Nothing
                    }

        Nothing ->
            scheduleNothingPlanned timeline


{-| Version of schedule that gets called, when we know that .new is Nothing.
-}
scheduleNothingPlanned : Timeline event -> Timeline event
scheduleNothingPlanned timeline =
    case timeline.queued of
        [] ->
            { timeline | running = False }

        ( duration, value ) :: tail ->
            { timeline
                | new = Just ( addDuration duration (first timeline.old), value )
                , queued = tail
            }


first : ( a, b ) -> a
first ( a, _ ) =
    a


second : ( a, b ) -> b
second ( _, b ) =
    b


type AnimationState state
    = Resting state
    | Transition { t : Float, old : state, new : state }


{-| Find out information about the current state of the animation. This is used
to render the animated objects.
-}
animate : Timeline state -> AnimationState state
animate timeline =
    case timeline.new of
        Just ( newTime, newValue ) ->
            Transition
                { t = inverseLerp (first timeline.old) newTime timeline.now
                , old = second timeline.old
                , new = newValue
                }

        Nothing ->
            Resting (second timeline.old)


{-| An animated state may have a property. This property is animated as well.
It is also optional, so fading in and out must be implemented as well.
-}
type AnimationProperty property
    = Interpolate { t : Float, old : property, new : property }
    | FadeIn { t : Float, new : property }
    | FadeOut { t : Float, old : property }
    | Fixed property


animateProperty : (state -> Maybe property) -> AnimationState state -> Maybe (AnimationProperty property)
animateProperty extract animationState =
    case animationState of
        Resting state ->
            Maybe.map Fixed (extract state)

        Transition { t, old, new } ->
            case ( extract old, extract new ) of
                ( Just o, Just n ) ->
                    Just (Interpolate { t = t, old = o, new = n })

                ( Nothing, Just n ) ->
                    Just (FadeIn { t = t, new = n })

                ( Just o, Nothing ) ->
                    Just (FadeOut { t = t, old = o })

                ( Nothing, Nothing ) ->
                    Nothing
