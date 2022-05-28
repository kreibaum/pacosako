module Custom.List exposing (breakAt)

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
