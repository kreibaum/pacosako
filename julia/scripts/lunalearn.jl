

#using ArgParse

#s = ArgParseSettings()

module Generate

  import Random
  using Printf

  using JtacPacoSako

  function until_not_over(f)
    game = f()
    while Game.is_over(game)
      game = f()
    end
    game
  end

  const INSTANCE = Dict{String, Function}(
    "random" => () -> until_not_over() do
      if rand() < 0.5
        game = random_position()
        Game.random_turns!(game, 1:5)
      else
        Game.random_turns!(PacoSako(), 0:150)
      end
    end
  )

  function add_entry!(ds, game, output)
    push!(ds.games, game)
    targets = Target.targets(ds)
    for (i, t) in enumerate(targets)
      key = Target.name(t)
      out = Float32[output[key]...]
      push!(ds.labels[i], out)
    end
  end

  function read_output(ch, luna; n, folder)
    k = 0
    ds = Data.DataSet(luna)

    step, finish = Util.stepper(@sprintf("Dataset #%04d", k), n)
    tstart = time()

    while isopen(ch)
      try
        game, output = take!(ch)
        add_entry!(ds, game, output)
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
          @info "Saved dataset '$path' ($gps g/s)"

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
    @info "Initiating lunalearn session '$session'"
    @info "Quit the session gracefully via ctrl-d"

    name = "lunalearn-p$power-t$temperature-n$n-$session"
    @info "Prefix: $name"

    luna = Player.MCTSPlayer(Luna(); power, temperature, name)

    ch = Channel{Any}(n)

    @sync begin
      @async Player.evaluate(luna, ch; instance = INSTANCE[instance], threads = true)
      @async read_output(ch, luna; n, folder)
      @async begin
        read(stdin) # this should block until ctrl-d is typed
        close(ch)
      end
    end

    @info "Shutting down session '$session'..."

  end

end # module Generate

using ArgParse

function main()
  s = ArgParseSettings()

  @add_arg_table s begin
    "generate"
      help = "let a Luna-based player generate PacoSako datasets"
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
      help = "data folder, is created if it does not exist"
      arg_type = String
      default = "./data"
    "-n"
      help = "size of the datasets saved in one jtm file"
      arg_type = Int
      default = 10000
  end

  args = parse_args(s, as_symbols = true)

  if args[:_COMMAND_] == :generate
    Generate.main(; args[:generate]...)
  else
    println("don't know what to do with $args")
  end
end

isinteractive() || main()

