module Clustering
  class NoneMap
    attr_reader :alphamap
    def initialize(alphamap)
      @alphamap = alphamap
      @map = {}
      alphamap.each do |name, id| @map[name] = id end
      @map[:__UNKNOWN__] = @map.size
      @I = Matrix::I(alphamap.size)
    end
    def inspect
      "Clustering::NoneMap<alphamap=#{alphamap}>"
    end
    alias to_s inspect

    def map(order)
      {:map => @map, :size => @map.size, :M => @I}
    end
    def transform_count_matrix(cD, order, nextras: 0)
      cD.copy
    end
    def transform_count_vector(c, order, nextras: 0)
      c.copy
    end
  end
  def Clustering::none(cD, wD, alphamap, nextras: 0)
    Clustering::NoneMap.new(alphamap)
  end

  class HierarchicalMap
    attr_reader :alphamap
    def initialize(_D, alphamap, zeros, pi)
      raise '_D must be square Matrix' unless _D.is_a? Matrix and _D.nrows == _D.ncols
      @D = _D
      @alphamap = alphamap
      @zeros = zeros
      @pi = pi
      # Do hierarchical clustering
      _Dt = @D.copy  # D^{(0)} := D
      n = _Dt.ncols
      i = 0
      while i < n do
        _Dt[i,i] = 2.0
        i += 1
      end
      clusters = Hash[*_Dt.ncols.times.map do |j| [j, [pi[j]]] end.flatten(1)]
      @joins = []
      uniques = {}
      until clusters.size == 1 do
        # Find the most nearest two clusters each other
        _Ei, _Ci = _Dt.imin
        min_dist = _Dt[_Ci,_Ei]
        # Join those two into one
        @joins << join = {:C1 => clusters[_Ci], :C2 => clusters[_Ei], :dist => min_dist}
        if min_dist >= 0.99 and (clusters[_Ci].length == 1 or clusters[_Ei].length == 1) then
          uniques[clusters[_Ci][0]] = true if clusters[_Ci].length == 1
          uniques[clusters[_Ei][0]] = true if clusters[_Ei].length == 1
          join[:unique] = true
        else
          join[:unique] = false
        end
        clusters[_Ci] += clusters[_Ei]
        # Update distance matrix D^{(t+1)} s.t.
        #   D^{(t+1)}(A, B) = \min_{a \in A, b \in B} D^{(0)}(\{a\}, \{b\}),
        #     A, B: disjoint clusters at t
        clusters.delete(_Ei)
        _Ai = 0
        while _Ai < n do
          if clusters.include?(_Ai) then
            _Dt[_Ci,_Ai] = _Dt[_Ei,_Ai] = _Dt[_Ai,_Ci] = _Dt[_Ai,_Ei] = [_Dt[_Ai,_Ci], _Dt[_Ai,_Ei]].min
          else
            _Dt[_Ci,_Ai] = _Dt[_Ei,_Ai] = _Dt[_Ai,_Ci] = _Dt[_Ai,_Ei] = 2.0
          end
          _Ai += 1
        end
        _Dt[_Ci,_Ci] = 2.0
      end
      @map = {}
      @joins.each do |join|
        next if join[:unique]
        _A, _B = join[:C1], join[:C2]
        alphamap.each do |name, id|
          @map[name] = (@map[name] || 0)*2 + if not uniques.include?(id) and _A.include?(id) then 1 else 0 end
        end
      end
      if uniques.size >= 1 then
        @order_offset = Math::log2(uniques.size + 1).ceil
        unique_id = 1
        alphamap.each do |name, id|
          if uniques[id] then
            @map[name] = ((@map[name] || 0)<<@order_offset) + unique_id
            unique_id += 1
          else
            @map[name] = (@map[name] || 0)<<@order_offset
          end
        end
      end
      alphamap.each do |name, id|
        @map[name] = if @zeros.include?(id) then 1 else @map[name]*2 end
      end
      @map[:__UNKNOWN__] = 1
      discard_cache
    end
    def inspect
      "Clustering::HierarchicalMap<alphamap=#{alphamap}>"
    end
    alias to_s inspect
    def discard_cache
      @maps_order= {}
      @dendrogram = nil
    end

    def dendrogram
      dg = {}
      @joins.each do |join|
        _C1 = dg[join[:C1][0]] || {:is_leaf => true, :nmembers => 1, :name => alphamap[join[:C1][0]], :dist => 0}
        _C2 = dg[join[:C2][0]] || {:is_leaf => true, :nmembers => 1, :name => alphamap[join[:C2][0]], :dist => 0}
        branch = {:is_leaf => false, :C1 => _C1, :C2 => _C2, :nmembers => join[:C1].length + join[:C2].length, :dist => join[:dist], :unique => join[:unique]}
        dg.delete(join[:C2][0])
        dg[join[:C1][0]] = branch
      end
      raise "joins information must form a dendrogram" unless dg.keys.length == 1
      dg[dg.keys[0]]
    end
    def dendrogram_compact
      df = DataFrame.from_a([], colnames: [:C1, :C2, :dist, :unique])
      @joins.each do |join|
        df << [join[:C1][0], join[:C2][0], join[:dist], join[:unique]]
      end
      df
    end
    def dissimilarity_data_frame
      @D.to_data_frame(colnames: @pi.collect do |i| alphamap[i] end)
    end

    def map(order)
      return @maps_order[order] if @maps_order[order]
      map, size = {}, 0
      if order == 0 then
        alphamap.each do |name, i|
          map[name] = if @zeros.include?(i) then 0 else size += 1 end
        end
        size += 1
      else
        ids = @map.values.collect! do |v| v&((1<<(@order_offset + order)) - 1) end.uniq
        id_map = Hash[*ids.zip((0..(ids.length - 1)).to_a).flatten]
        @map.each do |name, id| map[name] = id_map[id&((1<<(@order_offset + order)) - 1)] end
        size = ids.length
      end
      _M = Matrix::new(size, alphamap.size)
      map.each do |name, id| _M[id,alphamap.inverse(name)] = 1.0 end
      @maps_order[order] = {
        :map => map, :size => size, :M => _M
      }
    end
    def transform_count_matrix(cD, order, nextras: 0)
      map = map(order)
      _M = map[:M].resize(map[:M].nrows + nextras, map[:M].ncols + nextras)
      1.upto(nextras) do |j| _M[-j,-j] = 1.0 end
      cD * _M.t
    end
    def transform_count_vector(c, order, nextras: 0)
      map = map(order)
      tc = Vector.new(map[:size] + nextras)
      (c.length - nextras).times do |j|
        tc[map[:map][alphamap[j]]] += c[j]
      end
      1.upto(nextras) do |j| tc[-j] = c[-j] end
      tc
    end
  end
  def Clustering::hierarchical(cD, wD, alphamap, nextras: 0)
    # Cut extra columns and reorder columns by total counts, then coalesce columns whose count is 0
    cD = cD.resize(cD.nrows, cD.ncols - nextras) if nextras > 0
    cDsums = cD.colsums
    zeros = []
    cDsums.length.times do |i| zeros << i if cDsums[i] == 0 end
    pi = (0..(cD.ncols - 1)).to_a.sort_by! do |i| [-cDsums[i], i] end[0..-(zeros.length+1)]
    cD = cD.project(pi)
    # Calculate cosine-similarity matrix
    wcD = cD.mul_rows(wD)
    _SD = wcD.t * wcD
    d = _SD.diag
    _SD.hadamard!(_SD).hadamard!(d.rank1op(d).power_elements!(-1.0, 0.0))
    _SD.nrows.times do |i| _SD[i,i] = 1.0 end
    Clustering::HierarchicalMap.new(1.0 - _SD, alphamap, zeros, pi)
  end
end
