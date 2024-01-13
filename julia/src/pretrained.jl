
function model_from_artifact(name; kwargs...)
  path = try
    artifact = "model.$name"
    @artifact_str artifact
  catch
    error("No model artifact with name $name exists")
  end
  Model.load(joinpath(path, "$name.jtm"); kwargs...)
end

function Ludwig(version = "1.0"; kwargs...)
  model_from_artifact("ludwig-$version"; kwargs...)
end

function Hedwig(version = "0.1"; kwargs...)
  model_from_artifact("hedwig-$version"; kwargs...)
end

