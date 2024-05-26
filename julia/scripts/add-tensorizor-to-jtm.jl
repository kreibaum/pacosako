

using JtacPacoSako
# import MsgPack


path, ext = splitext(ARGS[1])
name = path * ext
name_old = path * "-old" * ext

println("> creating template model")
model_template = Model.Zoo.ZeroRes(
  PacoSako,
  tensorizor = PacoSakoTensorizor(), # default tensorizor
  async = false,
)

bytes_template = String(Pack.pack(model_template))

println("> loading old model file '$name'")
bytes_model_old = read(ARGS[1], String)

idx_template = findfirst("value", bytes_template)
idx_model_old = findfirst("value", bytes_model_old)

println("> converting old model file")
bytes_model = bytes_template[1:idx_template[1]] * bytes_model_old[idx_model_old[1]+1:end]

println("> checking consistency of new model file")
Pack.unpack(Vector{UInt8}(bytes_model), AbstractModel)

println("> moving '$name' to '$name_old'")
mv(name, name_old)

println("> writing updated model file '$name'")
write(name, bytes_model)
