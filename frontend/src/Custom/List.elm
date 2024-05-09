module Custom.List exposing (breakAt, diff)

{-| Custom List extensions. Ideally I should upstream this to
elm-community/list-extra.
-}


{-| Separates a list into sublist where a new list is started whenever the
predicate is true.

    breakAt id [ True, False, True ]
        == [ [ True, False ], [ True ] ]

    breakAt id [ False, False, True, True, False, True, False ]
        == [ [ False, False ], [ True ], [ True, False ], [ True, False ] ]

-}
breakAt : (a -> Bool) -> List a -> List (List a)
breakAt p list =
    case list of
        [] ->
            []

        x :: xs ->
            breakAtInner p xs ( [ x ], [] )
                |> (\( _, accOuter ) -> List.reverse accOuter)


breakAtInner : (a -> Bool) -> List a -> ( List a, List (List a) ) -> ( List a, List (List a) )
breakAtInner p list ( accInner, accOuter ) =
    case list of
        [] ->
            ( [], List.reverse accInner :: accOuter )

        x :: xs ->
            if p x then
                breakAtInner p xs ( [ x ], List.reverse accInner :: accOuter )

            else
                breakAtInner p xs ( x :: accInner, accOuter )


{-| What needs to be done to extend the "old" list to the "new" list?
If the old list contains the new list as a prefix, an empty list is returned.
This is because with locally determined legal moves, it is possible that our
local state is already two actions advanced when the server accnowledges the
first action.
-}
diff : List a -> List a -> Maybe (List a)
diff old new =
    case ( old, new ) of
        ( [], newTail ) ->
            Just newTail

        ( _, [] ) ->
            Just []

        ( o :: oldTail, n :: newTail ) ->
            if o == n then
                diff oldTail newTail

            else
                Debug.log "diff-missmatch" ":-("
                    |> (\_ -> Nothing)
