require 'katamuki.rb'

require 'minitest/autorun'

class TestAlphamap < MiniTest::Test
  def test_alphamap16
    alphamap = Alphamap16.new([:a, :b, :c, :d, :e])
    assert_equal("Alphamap<map=[:a,:b,:c,:d,:e]>", alphamap.inspect)
    Alphamap16::inspect_max = 2
    assert_equal("Alphamap<map=[:a,:b,... and other 3 alphabet(s)]>", alphamap.inspect)
    assert_equal(6, alphamap.size)
    alphamap2 = Alphamap16.new([:f, :g, :h, :i, :j])
    alphamap_copy = alphamap.copy
    alphamap_copy.merge!(alphamap2)
    assert_equal([:a, :b, :c, :d, :e], alphamap.to_a)
    assert_equal([:a, :b, :c, :d, :e, :f, :g, :h, :i, :j], alphamap_copy.to_a)
    alphamap3 = Alphamap16.new([:x, :y, :z])
    alphamap.merge!(alphamap3)
    assert_equal([:a, :b, :c, :d, :e, :x, :y, :z], alphamap.to_a)
    assert_equal([:a, :b, :c, :d, :e, :f, :g, :h, :i, :j], alphamap_copy.to_a)
    assert_equal(:a, alphamap[0])
    assert_equal(:__UNKNOWN__, alphamap[8])
    assert_equal(:__UNKNOWN__, alphamap[-1])
    assert_equal(1, alphamap.inverse(:b))
    assert_equal(-1, alphamap.inverse(:w))
    assert_equal(-1, alphamap.inverse(:__UNKNOWN__))
    # Alphamap16::Decoder and Alphamap16::Encoder are tested in JgramDatabase16.
    assert_equal([[:a, 0], [:b, 1], [:c, 2], [:d, 3], [:e, 4], [:x, 5], [:y, 6], [:z, 7]], alphamap.collect do |name, id| [name, id] end)
    assert_equal([[:a, 0], [:b, 1], [:c, 2], [:d, 3], [:e, 4], [:x, 5], [:y, 6], [:z, 7], [:__UNKNOWN__, -1]], alphamap.each(all: true).collect do |name, id| [name, id] end)
    alphamap4 = Alphamap16::from_alphamaps(alphamap, alphamap_copy)
    assert_equal([[:a, 0], [:b, 1], [:c, 2], [:d, 3], [:e, 4], [:x, 5], [:y, 6], [:z, 7], [:f, 8], [:g, 9], [:h, 10], [:i, 11], [:j, 12], [:__UNKNOWN__, -1]], alphamap4.each(all: true).collect do |name, id| [name, id] end)
  end
end
