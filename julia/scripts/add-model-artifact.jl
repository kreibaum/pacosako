
using Pkg.Artifacts, SHA

function add_model_artifact(name, file)
  # Wrap model in .tar.gz
  file_targz = "$name.tar.gz"
  println("> creating file '$file_targz'")
  run(`tar -czf $file_targz -C $(dirname(file)) $(basename(file))`)

  # Obtain SHA256 hash of the zipped file (needed for download verification)
  hash_targz = bytes2hex(open(sha256, file_targz))

  # Move model to static.kreibaum.dev
  println("> moving file '$file_targz' to pacoplay:static")
  run(`scp -q $file_targz pacoplay:static/`)
  run(`rm $file_targz`)

  # Create artifact directory containing the model file
  hash_artifact = create_artifact() do artifact_dir
    run(`cp $file $artifact_dir`)
  end

  url = "https://static.kreibaum.dev/$file_targz"

  # Bind the artifact to Artifacts.toml
  println("> binding the artifact 'model.$name' in 'Artifacts.toml'")
  bind_artifact!(
    "Artifacts.toml",
    "model.$name",
    hash_artifact;
    download_info = [(url, hash_targz)],
    lazy = true,
    force = true,
  )
  println("> done!")
end

if length(ARGS) == 2
  name = ARGS[1]
  file = ARGS[2]
elseif length(ARGS) == 1
  file = ARGS[1]
  name = splitext(basename(file))[1]
end

println("> trying to derive artifact 'model.$name' from file '$file'")
println("> continue? [Y|n]")
answer = readline() |> strip |> lowercase

if !(answer in ["", "y"])
  println("> aborting")
else
  add_model_artifact(name, file)
end

