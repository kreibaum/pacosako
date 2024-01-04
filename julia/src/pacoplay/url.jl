
function server(; domain = :dev)
  if domain in [:official, nothing]
    "https://pacoplay.com"
  elseif domain in [:localhost]
    "http://localhost:8000"
  else
    "https://$domain.pacoplay.com"
  end
end

function websocket(uuid :: String; domain = :dev)
  if domain in [:official, nothing]
    "wss://pacoplay.com/websocket?uuid=$uuid"
  elseif domain in [:localhost]
    "ws://localhost:8000/websocket?uuid=$uuid"
  else
    "wss://$domain.pacoplay.com/websocket?uuid=$uuid"
  end
end

editor(; domain = :dev) = server(; domain) * "/editor"

function editor(fen_string :: String; domain = :dev)
  editor(; domain) * "?fen=" * replace(fen_string, " " => "%20")
end

editor(ps :: PacoSako; domain = :dev) = editor(JtacPacoSako.fen(ps); domain)

game(; domain = :dev) = server(; domain) * "/game"
game(match :: Int; domain = :dev) = game(; domain) * "/$match"

replay(; domain = :dev) = server(; domain) * "/replay"
replay(match :: Int; domain = :dev) = replay(; domain) * "/$match"

