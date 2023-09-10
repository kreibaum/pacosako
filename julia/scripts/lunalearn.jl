

#using ArgParse

#s = ArgParseSettings()

module Generate

  import Random
  using Printf

  using JtacPacoSako

  function return_active_game(f)
    game = f()
    while Game.is_over(game)
      game = f()
    end
    game
  end

  const INSTANCE = Dict{String, Function}(
    "random" => () -> return_active_game() do
      if rand() < 0.5
        game = random_position()
        Game.random_turns!(game, 1:5)
      else
        Game.random_turns!(PacoSako(), 0:150)
      end
    end
  )

  function add_entry!(ds, targets, game, output)
    push!(ds.games, game)
    for (i, t) in enumerate(targets)
      key = Target.name(t)
      out = Float32[output[key]...]
      push!(ds.labels[i], out)
    end
  end

  function read_output(ch, luna; n, folder)
    k = 0
    ds = Data.DataSet(luna)
    targets = Target.targets(ds)

    step, finish = Util.stepper(@sprintf("Dataset #%04d", k), n)
    tstart = time()

    while true
      try
        game, output = take!(ch)
        add_entry!(ds, targets, game, output)
        step()

        # save dataset if enough games have been gathered
        if length(ds) >= n
          finish()
          tend = time()
          gps = @sprintf "%.2f" n / (tend - tstart)

          name = Player.name(luna)
          file = @sprintf "%s-%04d.jtd" name k

          path = joinpath(folder, file)
          Data.save(path, ds)
          @info "Saving '$path' ($gps g/s)"

          k += 1
          ds = Data.DataSet(luna)
          step, finish = Util.stepper(@sprintf("Dataset #%04d", k), n)
          tstart = time()
        end

      catch err
        finish()
        close(ch)
        if err isa InvalidStateException
          @info "input channel closed"
        else
          @error "received unexpected exception when handling output channel: $err"
          showerror(stdout, err)
        end
        break
      end
    end
  end

  function main(
               ; n = 5000
               , power = 1000
               , temperature = 1.0
               , instance = "random"
               , folder = "./data"
               )

    @assert Threads.nthreads() > 1 "Can only run lualearn with background threads. Run `julia -t N lualearn.jl ...`"
    @assert instance in keys(INSTANCE) "Instance string '$instance' is invalid"

    if !isdir(folder)
      try
        mkpath(folder)
        @info "Created folder $folder"
      catch
        @error "Could not create folder $folder"
        return
      end
    end

    session = Random.randstring(8)
    @info "Initiating lunalearn-generate session '$session'"
    @info "Quit the session gracefully via ctrl-d"

    name = "lunalearn-p$power-t$temperature-n$n-$session"
    @info "Prefix: $name"

    luna = Player.MCTSPlayer(Luna(); power, temperature, name)

    ch = Channel{Any}(100)

    @sync begin
      for _ in 1:(Threads.nthreads() - 1)
        Threads.@spawn Player.evaluate(luna, ch; instance = INSTANCE[instance])
      end
      @async read_output(ch, luna; n, folder)
      @async begin
        read(stdin) # this should block until ctrl-d is typed
        close(ch)
      end
    end

    @info "Shutting down session '$session'..."

  end

end # module Generate

module Merge

  using JtacPacoSako

  function get_jtd_files(folder)
    filepaths = String[]
    for (root, _dirs, files) in walkdir(folder)
      for file in files
        if splitext(file)[2] == ".jtd"
          push!(filepaths, joinpath(root, file))
        end
      end
    end
    filepaths
  end

  function prompt()
    while true
      try
        ch = read(stdin, Char)
        if ch in "yY\n"
          return true
        elseif ch in "nN" || isnothing(ch)
          return false
        end
      catch
        return false
      end
    end
  end

  function main(; output :: String, files = [], folder = "./data", session = "", power = "", n = "")

    # if no filters are given, all files are used
    if session == power == n == ""
      if isempty(files)
        @info "No filters given. Will merge all jtd files in '$folder'"
      else
        @info "No filters given. Will merge all specified files"
      end

      regs = [""]
    # if filters are given, expect lunalearn-generate-like files
    else
      sessions = split(session, ",", keepempty = false)
      sessions = isempty(sessions) ? ["[0-9a-zA-Z]+"] : sessions

      powers = parse.(Int, split(power, ",", keepempty = false))
      powers = isempty(powers) ? ["[0-9]+"] : powers

      ns = parse.(Int, split(n, ",", keepempty = false))
      ns = isempty(ns) ? ["[0-9]+"] : ns

      regs = map(Iterators.product(ns, powers, sessions)) do (n, p, s)
        Regex("lunalearn-p$p-t[0-9\\.]+-n$n+-$s-[0-9]+\\.jtd")
      end
    end

    files = isempty(files) ? get_jtd_files(folder) : files

    filter!(files) do file
      any((occursin(r, file) for r in regs))
    end

    if isempty(files)
      @info "No jtd files matching the selection found"
      return
    end

    @info "Will merge $(length(files)) jtd files into '$output'. Proceed? [Y/n]"
    proceed = prompt()

    proceed || return

    ds = merge(map(Data.load, files))
    @info "All datasets loaded. Found $(length(ds)) game states in total"

    Data.save(output, ds)
    @info "Merged $(length(files)) datasets into '$output'"

  end

end # module Merge

module Pretrain

  import CUDA, Knet

  using JtacPacoSako

  function load_model(path :: String)
    ext = splitext(path)[2]
    if ext == ".jl"
      # evalfile and include are relative to THIS file, not to the current
      # directory...
      path = isabspath(path) ? path : joinpath(pwd(), path)
      evalfile(path)
    elseif ext == ".jtm"
      Model.load(path)
    else
      throw(ArgumentError("File '$path' is neither a jtm nor julia file"))
    end
  end

  function parse_weights(str)
    options = split(str, ",", keepempty = false)
    kwargs = map(options) do opt
      key, value = split(opt, ":")
      key = Symbol(key)
      value = parse(Float64, value)
      key => value
    end
    (; kwargs...)
  end

  function parse_optimizer(str)
    str = lowercase(str)
    if str in ["sgd"]
      Knet.SGD
    elseif str in ["momentum"]
      Knet.Momentum
    elseif str in ["adam"]
      Knet.Adam
    elseif str in ["rmsprop"]
      Knet.Rmsprop
    else
      throw(ArgumentError("Cannot parse optimizer '$str'"))
    end
  end

  function parse_reg_targets(str)
    str = lowercase(str)
    if str == ""
      []
    elseif str in ["l1", "l1reg"]
      [Target.L1Reg()]
    elseif str == ["l2", "l2reg"]
      [Target.L2Reg()]
    else
      throw(ArgumentError("'$str' not a valid regularization target"))
    end
  end

  function main(
               ; data
               , model
               , output
               , batchsize = 512
               , splitsize = 500_000
               , epochs = 10
               , checkpoints = 5
               , optimizer = "momentum"
               , lr = 1e-2
               , gpu = true
               , reg = ""
               , weights = "value:1,policy:1"
               )

    @info "Loading model file '$model'..."
    try model = load_model(model)
    catch err
      @info "Loading model file failed: $err"
      return
    end
    print("\n")
    show(stdin, MIME("text/plain"), model)
    print("\n\n")

    @info "Loading dataset '$data'..."
    ds = nothing
    try ds = Data.load(data)
    catch err
      @error "Loading data file failed: '$err'"
      return
    end
    @info "Dataset of length $(length(ds)) loaded"

    dss = split(ds, splitsize, shuffle = false)
    @info "Dataset split in $(length(dss)) subsets"

    try reg = parse_reg_targets(reg)
    catch err
      @error "Parsing reg targets failed: '$err'"
      return
    end
    @info "Regularization targets: $reg"

    try weights = parse_weights(weights)
    catch err
      @error "Parsing target weights failed: '$err'"
      return
    end
    @info "Training weights: $weights"

    try optimizer = parse_optimizer(optimizer)
    catch err
      @error "Parsing optimizer failed: '$err'"
      return
    end
    @info "Training optimizer: $optimizer(lr = $lr)"

    if gpu
      if !CUDA.functional()
        @info "Will run training on CPU due to lack of CUDA support"
      else
        model = Model.to_gpu(model)
      end
    end

    callback_epoch(epoch) = begin

      if epoch % checkpoints == 0 && epoch != epochs
        k = div(epoch, checkpoints)
        base, ext = splitext(output)
        name = base * "-checkpoint-$k" * ext
        Model.save(name, Model.to_cpu(model))
        @info "Created checkpoint '$name'"
      end

    end


    @info "Starting training session"
    Training.train!( model, dss
                   ; batchsize
                   , epochs
                   , weights
                   , reg_targets = reg
                   , optimizer
                   , lr
                   , store_on_gpu = false
                   , callback_epoch
                   )

    Model.save(output, Model.to_cpu(model))
    @info "Saved final model as '$output'"

  end

end # module Pretrain

using Jtac, JtacPacoSako
using ArgParse

function main()
  s = ArgParseSettings()

  @add_arg_table s begin
    "generate"
      help = "let a Luna-based player generate PacoSako datasets"
      action = :command
    "merge"
      help = "merge jtac PacoSako datasets"
      action = :command
    "pretrain"
      help = "pretrain a jtac model on a dataset"
      action = :command
  end

  @add_arg_table s["generate"] begin
    "--power", "-p"
      help = "power of the Luna-based player"
      arg_type = Int
      default = 1000
    "--temperature", "-t"
      help = "temperature of the Luna-based player"
      arg_type = Float64
      default = 1.0
    "--instance", "-i"
      help = "algorithm that decides the games to be evaluated"
      arg_type = String
      default = "random"
    "--folder", "-f"
      help = "data folder. Is created if it does not exist"
      arg_type = String
      default = "./data/dump"
    "-n"
      help = "size of the datasets saved in one jtm file"
      arg_type = Int
      default = 10000
  end

  @add_arg_table s["merge"] begin
    "-n"
      help = "filter dataset names for n"
      default = ""
    "--power", "-p"
      help = "filter dataset names for power"
      default = ""
    "--session", "-s"
      help = "filter dataset names for session"
      default = ""
    "--folder", "-f"
      help = "data folder. Is ignored if explicit files are provided"
      default = "./data/dump"
    "--output", "-o"
      help = "output file. Required argument"
    "files"
      help = "jtd files to merge. If not provided, all files specified by --folder are used"
      nargs = '*'
  end

  @add_arg_table s["pretrain"] begin
    "--data", "-d"
      help = "dataset file (.jtd) used for training. Required argument"
    "--model", "-m"
      help = "model file (.jtm) or julia file with model definition. Required argument"
    "--output", "-o"
      help = "model output file. Required argument" 
    "--batchsize", "-b"
      help = "batchsize used for the stochastic gradient descent"
      arg_type = Int
      default = 512
    "--splitsize", "-s"
      help = "split the dataset in smaller sets of this size in order to reduce simultaneously used memory"
      arg_type = Int
      default = 500_000
    "--epochs", "-e"
      help = "number of epochs (iterations through the dataset) of the training process"
      arg_type = Int
      default = 10
    "--checkpoints", "-c"
      help = "number of epochs between saving model checkpoints"
      arg_type = Int
      default = 5
    "--optimizer", "-O"
      help = "which optimizer to use (sgd, rmsprops, adam, ...)"
      default = "momentum"
    "--lr", "-l"
      help = "learning rate for the optimizer"
      arg_type = Float64
      default = 1e-2
    "--reg", "-r"
      help = "network regularization (l1reg, l2reg, ...)"
      default = ""
    "--weights", "-w"
      help = "weights of the different training targets (e.g., 'value:1,policy:0.5,l1reg:1e-3')"
      default = ""
  end

  args = parse_args(s, as_symbols = true)

  if args[:_COMMAND_] == :generate
    Generate.main(; args[:generate]...)
  elseif args[:_COMMAND_] == :merge
    Merge.main(; args[:merge]...)
  elseif args[:_COMMAND_] == :pretrain
    Pretrain.main(; args[:pretrain]...)
  else
    println("don't know what to do with $args")
  end
end

isinteractive() || main()

