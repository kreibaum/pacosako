
using Test
using JtacPacoSako

@testset "PacoSako" begin
  g = PacoSako()
  f = fen(g)
  @test f == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -"
  for g in [PacoSako()]
    @test g == copy(g)
    @test PacoSako(f) == g
    @test Game.is_over(g) == false
    gf = Pack.freeze(g)
    @test Pack.is_frozen(gf)
    @test g == Pack.unfreeze(gf)
  end
  ds = JtacPacoSako.find_simple_positions(tries = 100)
  while length(ds) == 0
    ds = JtacPacoSako.find_simple_positions(tries = 100)
  end
  g = ds.games[1]
  s = JtacPacoSako.find_paco_sequences(g) 
  @test !isempty(s)
  p = Pack.pack(ds)
  u = Pack.unpack(p, Data.DataSet)
  @test all(ds.games .== u.games)
  @test all(ds.labels .== u.labels)
  @test all(ds.targets .== u.targets)
end


