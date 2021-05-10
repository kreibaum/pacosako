module Pages.Tournament.Id_ exposing (Params, page)

import Components
import Element exposing (Element, centerX, fill, fillPortion, maximum, padding, spacing, width)
import Element.Font as Font
import Gen.Route as Route
import List.Extra as List
import Page exposing (Page)
import Request
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page
page _ { params } =
    Page.static
        { view = view params
        }



-- VIEW


type alias Params =
    { id : String }


view : Params -> View msg
view params =
    case String.toLower params.id of
        "dutchopen2020" ->
            dutchOpen2020

        _ ->
            notFound


notFound : View msg
notFound =
    { title = "Tournament not found - pacoplay.com"
    , element = Components.header1 "Tournament not found."
    }


dutchOpen2020 : View msg
dutchOpen2020 =
    { title = "Dutch Open 2020 - pacoplay.com"
    , element =
        Element.column []
            [ Components.header1 "Dutch Open 2020"
            , Element.column [ width (fill |> maximum 1000), centerX, spacing 20, padding 10 ]
                [ Components.paragraph
                    """The Dutch Open 2020 was an online tournament held in December
                2020 with 11 participants. This was the first online tournament
                of Paco Ŝako. On this page all games are listed and you can watch Felix Albers
                cast the game or analyse the replays yourself."""
                , Components.paragraph
                    """The best way to get an overview will be a video that is
                currently being prepared by Felix."""
                , Components.header2 "Group 1"
                , Components.paragraph
                    """Group one was player with 5 competitors, each pairing played
                two games. Each row links to the match where they played as white."""
                , group1Table
                , Components.header2 "Group 2"
                , Components.paragraph
                    """Group two was player with 6 competitors, each pairing played
                two games. Each row links to the match where they played as white."""
                , group2Table
                , Components.header2 "Semifinals"
                , Components.paragraph
                    """The semifinals were a best of three with 20 minutes time limit.
                The first place of a group would play against the second place of the other group.
                The first place player got to start with white."""
                , Components.header3 "Semifinal 1: Rolf Kreibaum vs Raimond Flujit"
                , semifinal1Table
                , Components.header3 "Semifinal 2: Alon Nir vs Derk Dekker"
                , semifinal2Table
                , Components.header2 "Final: Alon Nir vs Raimond Flujit"
                , Components.paragraph
                    """The finals were a best of seven with a 15 minutes time limit."""
                , finalTable
                , Components.paragraph
                    """Congratulations to Raimond Flujit for winning this tournament.
                It was a very exiting final series, they gave us many great games.
                Raimond takes over the title of Dutch Paco Ŝako Champion from Derk Dekker
                who held this title the last two years."""
                ]
            ]
    }


type alias GroupTableData =
    { name : String
    , games : List Int
    }


group1Table : Element msg
group1Table =
    Element.table []
        { data =
            [ { name = "McGoohan", games = [ -1, 0, 154, 78, 64 ] }
            , { name = "Elsemiek Kemkes", games = [ 0, -1, 134, 93, 125 ] }
            , { name = "Derk Dekker", games = [ 155, 135, -1, 34, 138 ] }
            , { name = "Rolf Kreibaum", games = [ 77, 94, 36, -1, 69 ] }
            , { name = "Ralph Schuler", games = [ 31, 123, 136, 66, -1 ] }
            ]
        , columns =
            [ nameColumn
            , gameColumn 0 "McGoohan"
            , gameColumn 1 "Elsemiek"
            , gameColumn 2 "Derk"
            , gameColumn 3 "Rolf"
            , gameColumn 4 "Ralph"
            ]
        }


group2Table : Element msg
group2Table =
    Element.table []
        { data =
            [ { name = "Nico Bibo", games = [ -1, 114, 83, 107, 0, 0 ] }
            , { name = "Dieter Kreibaum", games = [ 113, -1, 80, 82, 0, 0 ] }
            , { name = "Raimond Flujit", games = [ 86, 79, -1, 37, 110, 127 ] }
            , { name = "Alon Nir", games = [ 108, 85, 38, -1, 96, 76 ] }
            , { name = "Sipho Kemkes", games = [ 0, 0, 111, 95, -1, 0 ] }
            , { name = "Mozart", games = [ 0, 0, 124, 73, 0, -1 ] }
            ]
        , columns =
            [ nameColumn
            , gameColumn 0 "Nico"
            , gameColumn 1 "Dieter"
            , gameColumn 2 "Raimond"
            , gameColumn 3 "Alon"
            , gameColumn 4 "Sipho"
            , gameColumn 5 "Mozart"
            ]
        }


th : String -> Element msg
th header =
    Element.el [ Font.bold ] (Element.text header)


nameColumn : Element.Column GroupTableData msg
nameColumn =
    { header = th "Contester"
    , width = fillPortion 2
    , view = \r -> Element.text r.name
    }


gameColumn : Int -> String -> Element.Column GroupTableData msg
gameColumn index header =
    { header = th header
    , width = fillPortion 1
    , view = \r -> r.games |> List.getAt index |> Maybe.withDefault 0 |> gameLink
    }


gameLink : Int -> Element msg
gameLink key =
    if key < 0 then
        Element.text "x"

    else if key == 0 then
        Element.text "?"

    else
        Element.link [ Font.color (Element.rgb255 0 0 255) ]
            { url = Route.toHref (Route.Replay__Id_ { id = String.fromInt key })
            , label = Element.text (String.fromInt key)
            }


type alias EliminationTableData =
    { white : String
    , black : String
    , key : Int
    }


semifinal1Table : Element msg
semifinal1Table =
    Element.table []
        { data =
            [ { white = "Rolf", black = "Raimond", key = 166 }
            , { white = "Raimond", black = "Rolf", key = 167 }
            , { white = "Rolf", black = "Raimond", key = 169 }
            ]
        , columns = [ whiteColumn, blackColumn, gameLinkColumn ]
        }


semifinal2Table : Element msg
semifinal2Table =
    Element.table []
        { data =
            [ { white = "Alon", black = "Derk", key = 161 }
            , { white = "Derk", black = "Alon", key = 162 }
            , { white = "Alon", black = "Derk", key = 163 }
            ]
        , columns = [ whiteColumn, blackColumn, gameLinkColumn ]
        }


finalTable : Element msg
finalTable =
    Element.table []
        { data =
            [ { white = "Alon", black = "Raimond", key = 170 }
            , { white = "Raimond", black = "Alon", key = 171 }
            , { white = "Alon", black = "Raimond", key = 172 }
            , { white = "Raimond", black = "Alon", key = 173 }
            , { white = "Alon", black = "Raimond", key = 174 }
            , { white = "Raimond", black = "Alon", key = 175 }
            , { white = "Alon", black = "Raimond", key = 176 }
            ]
        , columns = [ whiteColumn, blackColumn, gameLinkColumn ]
        }


whiteColumn : Element.Column EliminationTableData msg
whiteColumn =
    { header = th "White"
    , width = fillPortion 2
    , view = \r -> Element.text r.white
    }


blackColumn : Element.Column EliminationTableData msg
blackColumn =
    { header = th "Black"
    , width = fillPortion 2
    , view = \r -> Element.text r.black
    }


gameLinkColumn : Element.Column EliminationTableData msg
gameLinkColumn =
    { header = th "Link"
    , width = fillPortion 1
    , view = \r -> gameLink r.key
    }
