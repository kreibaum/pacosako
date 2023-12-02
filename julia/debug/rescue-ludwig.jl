
import Jtac
import MsgPack

function reconstruct_model(G, dict)
  @assert dict["type"]["name"] == "neural_model"
  heads = map(reconstruct_layer, dict["heads"])
  heads = (value = heads[1], policy = heads[2])
  trunk = reconstruct_layer(dict["trunk"])
  targets = Target.defaulttargets(G)
  Model.NeuralModel(G, trunk; targets, heads)
end

function reconstruct_layer(dict)
  tname = dict["type"]["name"]
  if tname == "chain"
    reconstruct_chain(dict)
  elseif tname == "residual"
    reconstruct_residual(dict)
  elseif tname == "dense"
    reconstruct_dense(dict)
  elseif tname == "conv"
    reconstruct_conv(dict)
  elseif tname == "batchnorm"
    reconstruct_batchnorm(dict)
  else
    error("cannot reconstruct layer")
  end
end

function reconstruct_conv(dict)
  @assert dict["type"]["name"] == "conv"
  pad = Int(dict["p"][1]), Int(dict["p"][2])
  stride = Int(dict["s"][1]), Int(dict["s"][2])
  f = Model.resolve(Model.Activation, dict["a"]["name"])
  w = reinterpret(Float32, dict["w"]["bytes"])
  w = reshape(w, Int.(dict["w"]["dims"])...)
  b = reinterpret(Float32, dict["b"]["bytes"])
  Model.Conv{Array{Float32}}(w, b, f, true, pad, stride)
end

function reconstruct_dense(dict)
  @assert dict["type"]["name"] == "dense"
  f = Model.resolve(Model.Activation, dict["a"]["name"])
  w = reinterpret(Float32, dict["w"]["bytes"])
  w = reshape(w, Int.(dict["w"]["dims"])...)
  b = reinterpret(Float32, dict["b"]["bytes"])
  Model.Dense{Array{Float32}}(w, b, f, true)
end

function reconstruct_batchnorm(dict)
  @assert dict["type"]["name"] == "batchnorm"
  f = Model.resolve(Model.Activation, dict["a"]["name"])
  mean = reinterpret(Float32, dict["moments"]["mean"]["bytes"])
  var = reinterpret(Float32, dict["moments"]["var"]["bytes"])
  params = reinterpret(Float32, dict["params"]["bytes"])
  @assert length(params) == length(mean) + length(var)
  scale = params[1:length(var)]
  bias = params[length(var)+1:end]
  Model.Batchnorm{Array{Float32}}(mean, var, bias, scale, f)
end

function reconstruct_chain(dict)
  @assert dict["type"]["name"] == "chain"
  layers = map(reconstruct_layer, dict["layers"])
  Model.Chain{Array{Float32}}(layers)
end

function reconstruct_residual(dict)
  @assert dict["type"]["name"] == "residual"
  chain = reconstruct_chain(dict["chain"])
  f = Model.resolve(Model.Activation, dict["a"]["name"])
  Model.Residual{Array{Float32}}(chain, f)
end


file = open("models/v0.1/ludwig-1.0.jtm")
ludwig = MsgPack.unpack(file)
model = reconstruct_model(PacoSako, ludwig)

# players = [
#   [Player.MCTSPlayer(model, power = p, name = "ludwig$p") for p in [10, 20]]..., 
#   [Player.MCTSPlayer(PacoSako, power = p) for p in [10, 20, 100, 500, 5000]]..., 
# ]

# Player.pvp(players[1], players[end])

Model.save("models/ludwig-1.0.jtm", model)