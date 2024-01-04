
const COLORS = Dict(1 => "white", -1 => "black")

function log(msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay ", color = 245)
  println(String(take!(buf)) * msg)
end

function log(match :: Int, msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay:", color = 245)
  printstyled(ctx, "$match", color = 245)
  printstyled(ctx, " ", color = 245)
  println(String(take!(buf)) * msg)
end

function logerr(msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay ", color = 245)
  printstyled(ctx, "Error: $msg\n", color = :red)
  println(stderr, String(take!(buf)) * msg)
end

