class Alphamap16
  module Decoder
    def decode(s, j=-1, to_sym: false)
      if j == -1 then
        a = s.unpack('s<*')
        if to_sym then a.collect! do |xj| alphamap[xj] end else a end
      else
        xj = s[(2*j)..(2*j+1)].unpack('s<')[0]
        if to_sym then alphamap[xj] else xj end
      end
    end
    def extract(s, j)
      s[(2*j)..(2*j+1)]
    end
  end
  module Encoder
    def encode(row)
      row.map do |xj| alphamap.inverse(xj) end.pack('s<*')
    end
  end

  attr_reader :path
  def initialize(inverse)
    @path = path
    @inverse = inverse.collect do |name| name.to_s.to_sym end
    @map = {}
    @inverse.each.with_index do |name, i| @map[name] = i end
  end
  def Alphamap16::from_alphamaps(alphamaps)
    alphamap = alphamaps.first.clone
    1.upto(alphamaps.length-1) do |i| alphamap.merge!(alphamaps[i]) end
    alphamap
  end
  def inspect(max=5)
    "Alphamap<path=#{path}, inverse=[#{@inverse[0..(max-1)].map do |name| name.inspect end.join(',')}#{if @inverse.length > max then ",... and other #{@inverse.length - max} alphabet(s)" end}]>"
  end
  alias to_s inspect
  def clone
    other = super
    @inverse = @inverse.clone
    @map = @map.clone
    other
  end
  def size
    @inverse.length + 1
  end

  def each(all: false)
    @inverse.each.with_index do |name, i| yield(name, i) end
    yield(:__UNKNOWN__, @inverse.length) if all
  end
  def [](id)
    return :__UNKNOWN__ if id == -1
    return @inverse[id] || :__UNKNOWN__ if id.is_a? Integer
    throw "unsupported id class: #{id.class}"
  end
  def inverse(name)
    return name if name.is_a? Integer
    return @map[name] || -1 if name.is_a? Symbol
    throw "unsupported name class: #{name.class}"
  end

  def merge!(other)
    other.each do |name, i|
      next if @map[name]
      @inverse << name
      @map[name] = @inverse.length - 1
    end
  end
end
