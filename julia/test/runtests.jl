
using Test
using JtacPacoSako
import JtacPacoSako: fen, sakodata, sakochains, Luna

@testset "PacoSako" begin
  game = PacoSako()
  fstr = fen(game)
  @test fstr == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -"
  @test Game.policylength(PacoSako) == Game.policylength(game) == 132

  for game in [PacoSako(), Game.randominstance(PacoSako)]
    @test game == copy(game)
    fstr = fen(game)
    @test PacoSako(fstr) == game
    @test Game.status(game) == Game.undecided
    @test Game.isover(game) == false
  end

  game = Game.randommatch(PacoSako())
  @test Game.isover(game)

  data = Game.array([game, PacoSako()])
  @test size(data) == (8, 8, 30, 2)

  ds = sakodata(tries = 100)
  while length(ds) == 0
    ds = sakodata(tries = 100)
  end
  g = ds.games[1]
  s = sakochains(g) 
  @test !isempty(s)
  p = Pack.pack(ds)
  u = Pack.unpack(p, Training.DataSet)
  @test all(ds.games .== u.games)
  @test all(ds.target_names .== u.target_names)
  @test all(ds.targets .== u.targets)
  @test all(ds.target_labels[1] .== u.target_labels[1])
  @test all(ds.target_labels[2] .== u.target_labels[2])
end

@testset "Luna" begin
  m1 = Luna()
  @test m1 isa Model.AbstractModel{PacoSako}
  m2 = Model.Zoo.ZeroConv(PacoSako, blocks = 2, filters = 64)
  m2 = Model.configure(m2, assist = m1)
  p1 = Player.MCTSPlayer(m1, power = 50)
  p2 = Player.MCTSPlayer(m2, power = 10)
  @test Player.pvp(p1, p2) isa Game.Status
  @test Pack.unpack(Pack.pack(m1), Model.AbstractModel) == Luna()
end