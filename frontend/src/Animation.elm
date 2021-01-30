module Animation exposing
    ( AnimationProperty(..)
    , AnimationState(..)
    , Duration
    , Timeline
    , animate
    , animateProperty
    , init
    , interrupt
    , map
    , milliseconds
    , pause
    , queue
    , subscription
    , tick
    )

{-| This module is heavily inspired by mdgriffith/elm-animator. I am building my
own version to have direct access to internals.
-}

import Browser.Events
import List.Extra as List
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
    , running = True
    }


{-| Map over a timeline. This is important if you have some function that takes
a `Timeline b` for rendering but are storing a `Timeline a` yourself.
-}
map : (a -> b) -> Timeline a -> Timeline b
map f timeline =
    { now = timeline.now
    , old = mapSecond f timeline.old
    , new = Maybe.map (mapSecond f) timeline.new
    , queued = List.map (mapSecond f) timeline.queued
    , running = timeline.running
    }


mapSecond : (a -> b) -> ( t, a ) -> ( t, b )
mapSecond f ( t, x ) =
    ( t, f x )


{-| Tells the animation to transition to a new event over a given duration.
If the animation is currently running, this will be added at the end of the
animation queue.
-}
queue : ( Duration, event ) -> Timeline event -> Timeline event
queue step timeline =
    { timeline
        | queued = timeline.queued ++ [ step ]
        , running = True
    }


{-| Step to the given event without animation and interrupt any
currently running or queued animation.
-}
interrupt : event -> Timeline event -> Timeline event
interrupt event timeline =
    { timeline
        | old = ( first timeline.old, event )
        , new = Nothing
        , queued = []
        , running = True
    }


{-| Copies the last queued event of the timeline and queues it. This effectively
pauses the animation for that duration.
-}
pause : Duration -> Timeline event -> Timeline event
pause duration timeline =
    queue ( duration, lastEvent timeline ) timeline


{-| Returns the newest event that is sheduled, animated to or old.
-}
lastEvent : Timeline event -> event
lastEvent timeline =
    let
        snd ( _, e ) =
            e

        fallback =
            timeline.new
                |> Maybe.withDefault timeline.old
                |> snd
    in
    List.last timeline.queued
        |> Maybe.map snd
        |> Maybe.withDefault fallback


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


{-| Schedule queued Events. This method needs to tail call itself, because the
current time may be progressed so much, than an entire section of the animation
is skipped completely. This usually happen when an event is scheduled for
duration zero. (Duration zero just means "jump to this event now.")
-}
schedule : Timeline event -> Timeline event
schedule timeline =
    case timeline.new of
        Just ( newTime, value ) ->
            if timeInOrder timeline.now newTime then
                timeline

            else
                { timeline
                    | old = ( newTime, value )
                    , new = Nothing
                }
                    |> scheduleNext

        Nothing ->
            scheduleNothingPlanned timeline


{-| Version of schedule that gets called, when we know that .new is Nothing.
-}
scheduleNothingPlanned : Timeline event -> Timeline event
scheduleNothingPlanned timeline =
    case timeline.queued of
        [] ->
            { timeline | running = timeline.new /= Nothing }

        ( duration, value ) :: tail ->
            { timeline
                | new = Just ( addDuration duration timeline.now, value )
                , queued = tail
                , old = ( timeline.now, second timeline.old )
            }
                |> schedule


scheduleNext : Timeline event -> Timeline event
scheduleNext timeline =
    case timeline.queued of
        [] ->
            { timeline | running = False }

        ( duration, value ) :: tail ->
            { timeline
                | new = Just ( addDuration duration (first timeline.old), value )
                , queued = tail
                , old = ( timeline.now, second timeline.old )
            }
                |> schedule


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


animateProperty : (state -> Maybe property) -> { t : Float, old : state, new : state } -> Maybe (AnimationProperty property)
animateProperty extract { t, old, new } =
    case ( extract old, extract new ) of
        ( Just o, Just n ) ->
            Just (Interpolate { t = t, old = o, new = n })

        ( Nothing, Just n ) ->
            Just (FadeIn { t = t, new = n })

        ( Just o, Nothing ) ->
            Just (FadeOut { t = t, old = o })

        ( Nothing, Nothing ) ->
            Nothing
