require 'katamuki/alphamap'
require 'katamuki/clustering'

class JgramDatabase16
  class ColumnPair < Hash
    def select(target)
      column = []
      self.each do |k, v| column << k[2..3] if k[0..1] == target end
      column
    end
  end

  include Alphamap16::Decoder
  include Alphamap16::Encoder
  attr_reader :J, :alphamap
  def initialize(_J, alphamap)
    @J = _J
    @alphamap = alphamap
    @rows = {}
    discard_cache
  end
  def inspect
    "JgramDatabase<J=#{@J}, size=#{size}, weight=#{weight}>"
  end
  alias to_s inspect
  def copy
    other = clone
    @rows = @rows.copy
    other
  end
  def size
    n = 0
    @rows.each do |row, weight| n += 1 if weight > 0 end
    n
  end
  def order_size(order)
    if order == size then size else clustering_map.order_size(order) end
  end
  def weight
    w = 0
    @rows.each do |row, weight| w += weight end
    w
  end
  def discard_cache
    @cache = {}
  end

  def each
    return to_enum unless block_given?
    @rows.each do |row, weight|
      yield(row, weight) if weight > 0
    end
  end
  def [](j1,j2 = nil)
    return @rows[j1] if j1.is_a? String and j2 == nil
    return @cache[[j1,j2]] if @cache[[j1,j2]]
    m = if j2 then ColumnPair.new() else {} end
    @rows.each do |row, weight|
      k1 = row[(j1*2)..(j1*2+1)]
      sk = if k1 == nil or k1 == '' then "\x00\x00" else k1 end
      if j2 then
        k2 = row[(j2*2)..(j2*2+1)]
        sk += if k2 == nil or k2 == '' then "\x00\x00" else k2 end
      end
      m[sk] = (m[sk] || 0) + weight
    end
    @cache[[j1,j2]] = m
    return m
  end

  def has_row?(row)
    @rows[row] and @rows[row] > 0
  end
  def add_weight(row, weight)
    discard_cache
    @rows[row] = (@rows[row] || 0) + weight
  end
  def update_weight(row, weight)
    discard_cache
    @rows[row] = weight
  end
  def update_weights
    discard_cache
    each do |row, weight|
      @rows[row] = yield(row, weight)
    end
  end

  def merge!(db)
    db.each do |row, weight|
      add_weight(row, weight)
    end
  end
  def merge(db)
    copy.merge!(db)
  end
  def split(nsplits, seed: 31337)
    rng = Random.new(seed)
    pi = (0..(nsplits - 1)).to_a
    subdbs = nsplits.times.map do copy end
    weights = Array.new(nsplits)
    each do |row, weight|
      weights_sum = 0
      weights.collect! do
        weights_sum += w = rng.rand
        w
      end
      pi.shuffle!(random: rng)
      remain = weight
      (nsplits - 1).times do |i|
        remain -= w = (weight*weights[i]/weights_sum).floor
        subdbs[pi[i]].update_weight(row, w)
      end
      subdbs[pi[-1]].update_weight(row, remain)
    end
    subdbs
  end
end
