module Custom.List exposing (breakAt, diff, ListDiff(..))

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


type
    ListDiff a
    -- The new list usually extends the old list when new actions come from the
    -- web socket.
    = NewExtendsOld (List a)
      -- The old list extends the new list, when the client moves faster than the
      -- server can acknowledge.
    | OldExtendsNew (List a)
      -- The lists are equal, no diff. I.e. Server acknowledges the client's
      -- actions in the same order.
    | ListsAreEqual
      -- The lists can't be reconciled. Happens when the client moves out of turn.
    | ListsDontExtendEachOther


{-| What needs to be done to extend the "old" list to the "new" list?
If the old list contains the new list as a prefix, an empty list is returned.
This is because with locally determined legal moves, it is possible that our
local state is already two actions advanced when the server accnowledges the
first action.
-}
diff : List a -> List a -> ListDiff a
diff old new =
    case ( old, new ) of
        ( [], [] ) ->
            ListsAreEqual

        ( [], newTail ) ->
            NewExtendsOld newTail

        ( oldTail, [] ) ->
            OldExtendsNew oldTail

        ( o :: oldTail, n :: newTail ) ->
            if o == n then
                diff oldTail newTail

            else
                ListsDontExtendEachOther
