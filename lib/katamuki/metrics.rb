module Metrics
  # Pairwise is a module containing methods for computing pairwise
  # similarities of columns of Matrix.
  module Pairwise
    # Reorder the columns of _X, coalesce the columns whose l1norm is 0
    # if specified.
    # Return values are a tuple of reordered _X, Array containing indices
    # of the coalesced columns and the column permutation Array.
    #
    # @param _X Matrix.
    # @param coalesce indicating coalescence.
    def Pairwise::reorder_columns(_X, coalesce: true)
      _Xcolsums = _X.colsums
      zeros = if coalesce then
        _Xcolsums.length.times.collect do |i| if _Xcolsums[i] == 0 then i else nil end end.compact
      else
        []
      end
      pi = (0..(_X.ncols - 1)).to_a.sort_by! do |i| [-_Xcolsums[i], i] end[0..-(zeros.length+1)]
      [_X.project(pi), zeros, pi]
    end
    # Normalize the given similarity matrix.
    #
    # @param _S the square Matrix containing pairwise similarities.
    def Pairwise::normalize_similarity(_S)
      raise '_S must be square Matrix' unless _S.is_a? Matrix and _S.nrows == _S.ncols
      d = _S.diag.power_elements!(0.5)
      _S = _S.hadamard(d.rank1op(d).power_elements!(-1.0, 0.0))
      _S.nrows.times do |i| _S[i,i] = 1.0 end
      _S
    end
    # Convert the given similarity matrix to the corresponding normalized
    # dissimilarity matrix.
    #
    # @param _S the squared Matrix containing pairwise similarities.
    def Pairwise::similarity_to_normalized_dissimilarity(_S)
      1.0 - Metrics::Pairwise::normalize_similarity(_S)
    end
    # Similarities is a module containing methods for the supported pairwise
    # similarities.
    module Similarities
      # Return a Matrix containing cosine similarities of columns.
      #
      # @param _X Matrix.
      def Similarities::cosine(_X)
        raise '_X must be Matrix' unless _X.is_a? Matrix
        Metrics::Pairwise::normalize_similarity((_X.t*_X).power_elements!(2.0))
      end
      # Return a Matrix containing euclidean distances of columns.
      #
      # @param _X Matrix.
      def Similarities::euclidean_distance(_X)
        raise '_X must be Matrix' unless _X.is_a? Matrix
        _XtX = _X.t*_X
        d = _XtX.diag
        ones = Vector.new(d.length).fill(1.0)
        (d.rank1op(ones) + ones.rank1op(d) - 2.0*_XtX).power_elements(0.5)
      end
    end
  end
end
