using HTTP, LazyJSON

include("pacosako.jl")

r = HTTP.request("GET", "https://pacoplay.com/api/game/1056")

p = LazyJSON.parse(String(r.body))

actions = p["actions"]
first_action = actions[1]

function parse_action(json)::Int64
    if "Lift" in keys(json)
        1 + json["Lift"]
    elseif "Place" in keys(json)
        1 + json["Place"] + 64
    elseif "Promote" in keys(json)
        piece_type = json["Promote"]
        if piece_type == "Rook"
            2 * 64 + 1
        elseif piece_type == "Knight"
            2 * 64 + 2
        elseif piece_type == "Bishop"
            2 * 64 + 3
        elseif piece_type == "Queen"
            2 * 64 + 4
        else
            error("Piece type $piece_type is in JSON and not understood.")
        end
    else
        error("There is an action in the JSON that is not understood.")
    end
end

action_ids = parse_action.(actions)


p = PacoSako()
Game.apply_action!.(p, action_ids)
p