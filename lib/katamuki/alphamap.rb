# Alphamap16 is a implementation of Alphamap whose number of alphabets
# must be less than 2^16.
class Alphamap16
  # Alphamap16::Decoder implements the decoder for Alphamap16.
  module Decoder
    # Decode s.
    #
    # @param s String containing encoded alphabets.
    # @param j indicating to decode all entries if j == -1, to decode
    #          j-th entry otherwise.
    # @param to_sym returns Symbols if true, Integers otherwise.
    def decode(s, j=-1, to_sym: false)
      if j == -1 then
        a = s.unpack('s<*')
        if to_sym then a.collect! do |xj| alphamap[xj] end else a end
      else
        xj = s[(2*j)..(2*j+1)].unpack('s<')[0]
        if to_sym then alphamap[xj] else xj end
      end
    end
    # Extract j-th substring.
    #
    # @param s String containing encoded alphabets.
    # @param j Integer indicating the extracted index.
    def extract(s, j)
      s[(2*j)..(2*j+1)]
    end
  end
  # Alphamap16::Encoder implements the encoder for Alphamap16.
  module Encoder
    # Encode a.
    #
    # @param Array containing Symbols or Integers.
    def encode(a)
      a.map do |xj| alphamap.inverse(xj) end.pack('s<*')
    end
  end

  include Enumerable
  # Create a new Alphamap16 instance.
  #
  # @param map Array containing alphabets for mapping Integer to Symbol.
  def initialize(map)
    @map = map.collect do |name| name.to_s.to_sym end
    @inverse = {}
    @map.each.with_index do |name, i| @inverse[name] = i end
  end
  # Create a merged Alphamap16 instance.
  #
  # @param alphamaps Array containing the merged Alphamaps.
  def Alphamap16::from_alphamaps(*alphamaps)
    alphamap = alphamaps.first.clone
    1.upto(alphamaps.length-1) do |i| alphamap.merge!(alphamaps[i]) end
    alphamap
  end
  def inspect
    "Alphamap<map=[#{@map[0..(Alphamap16::inspect_max-1)].map do |name| name.inspect end.join(',')}#{if @map.length > Alphamap16::inspect_max then ",... and other #{@map.length - Alphamap16::inspect_max} alphabet(s)" end}]>"
  end
  # Return max variable used in inspect for omission.
  def Alphamap16::inspect_max
    @@inspect_max ||= 5
  end
  # Set max variable used in inspect for omission.
  #
  # @param val Integer.
  def Alphamap16::inspect_max=(val)
    raise 'val must be positive Integer' unless val.is_a? Integer and val > 0
    @@inspect_max = val
  end
  alias to_s inspect
  def copy
    Alphamap16.new(@map)
  end
  # Return number of alphabets containing `__UNKNOWN__`.
  def size
    @map.length + 1
  end
  # Returns Array mapping Integer to Symbol.
  def to_a
    @map.copy
  end

  # Iterate all alphabets if the block is given, return Enumerator
  # otherwise.
  #
  # @param all Boolean indicating whether `__UNKNOWN__` is enumerated at
  #            last or not.
  def each(all: false)
    return to_enum(__method__, all: all) unless block_given?
    @map.each.with_index do |name, id| yield(name, id) end
    yield(:__UNKNOWN__, -1) if all
  end
  # Return Symbol indicating alphamap by id.
  #
  # @param id Integer indicating the ID of alphabet.
  def [](id)
    return :__UNKNOWN__ if id == -1
    return @map[id] || :__UNKNOWN__ if id.is_a? Integer
    throw "unsupported id class: #{id.class}"
  end
  # Return ID of name.
  #
  # @param name Integer or Symbol.
  def inverse(name)
    return (if -1 <= name and name < size - 1 then name else -1 end) if name.is_a? Integer
    return @inverse[name] || -1 if name.is_a? Symbol
    throw "unsupported name class: #{name.class}"
  end

  # Merge Alphamap into self.
  #
  # @param other the merged Alphamap.
  def merge!(other)
    other.each do |name, _|
      unless @inverse[name] then
        @map << name
        @inverse[name] = @map.length - 1
      end
    end
  end
end
