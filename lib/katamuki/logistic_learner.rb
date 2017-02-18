require 'katamuki/logistic_classifier'

class LogisticLearner
  attr_reader :db, :min_weight, :shrinkage, :order, :classifier, :clustering
  def initialize(db, min_weight: 1e-05, shrinkage: 1.0, clustering_method: nil, order: nil)
    @db = db
    @min_weight = min_weight
    @shrinkage = shrinkage
    @clustering_method, @order = if clustering_method then
      raise "specify clustering_method of #{
        (Clustering.methods - Clustering.class.methods).join(' or ')
      }" if !Clustering.respond_to? clustering_method
      raise "specify order" unless order
      [clustering_method, order]
    else
      [:none, 0]
    end
    @classifier = LogisticClassifier.new(self)
    internals = get_internal_representation
    @x0_useds, @x0_useds_map = internals[:x0_useds], internals[:x0_useds_map]
    @cD, @wD = internals[:cD], internals[:wD]
    @Y = Matrix.new(db.size, @x0_useds.size)
    @P = Matrix.new(db.size, @x0_useds.size).fill(1.0/@x0_useds.size)
    db.each.with_index do |(row, _), i| @Y[i,@x0_useds_map[db.decode(row, 0)]] = 1.0 end
    @clustering = Clustering.method(@clustering_method).call(@cD, @wD, db.alphamap, nextras: 1)
  end
  def inspect
    "LogisticLearner<db=#{@db}, min_weight=#{@min_weight}, shrinkage=#{@shrinkage}, clustering=#{@clustering}, order=#{@order}>"
  end
  alias to_s inspect
  def parameter_string
    "LogisticLearner-min_weight#{@min_weight}-shrinkage#{@shrinkage}-clustering_#{@clustering_method}-order#{@order}"
  end

  def get_internal_representation
    x0_useds = {}
    cD = Matrix.new(db.size, db.alphamap.size + 1)
    wD = Vector.new(db.size)
    db.each.with_index do |(row, weight), i|
      x0 = db.decode(row, 0)
      x0_useds[x0] = true
      cD[i,-1] = 1.0
      1.upto(db.J - 1) do |j| cD[i,db.decode(row, j)%db.alphamap.size] += 1.0 end
      wD[i] = weight
    end
    x0_useds = x0_useds.keys.sort!
    x0_useds_map = {}
    x0_useds.each.with_index do |x0, i| x0_useds_map[x0] = i end
    {:x0_useds => x0_useds, :x0_useds_map => x0_useds_map, :cD => cD, :wD => wD}
  end

  def learn(t)
    order = if @order < 0 then (t/Float(-@order)).ceil else @order end
    cD = @clustering.transform_count_matrix(@cD, order, nextras: 1)
    classifier = LogisticClassifier.new(self)
    beta_mean = Vector.new(cD.ncols)
    _W = (1.0 - @P).hadamard!(@P)
    _Z = (@Y - @P).hadamard!(_W.power_elements(-1.0, 0.0))
    _B = begin
      solve_multiple_weighted_least_squares(_Z, cD, _W.mul_rows!(@wD))
    rescue LAPACK::Info
      $logger&.error(:logistic_learner_solve_multiple_weighted_least_squares, "#{t} => #{$!}")
      Matrix.new(cD.ncols, @Y.ncols)
    end
    # Mathematically same but sometimes optimized-numerically different:
    #   beta_mean = _B.rowsums.hadamard!(1.0/_B.ncols)
    beta_mean = Vector.new(_B.nrows)
    _B.each do |beta| beta_mean.add!(beta) end
    beta_mean.hadamard!(1.0/_B.ncols)
    _B.each.with_index do |beta, i|
      (classifier.betas_set[@x0_useds[i]] = {})[order] = beta.sub!(beta_mean).hadamard!(shrinkage)
    end
    @classifier.merge!(classifier)
    total_nnegatives, total_npositives = 0, 0
    scores_set = @classifier.calculate_scores_set_(@cD, @x0_useds)
    _P = scores_set.softmax_rows
    db.each.with_index do |(row, weight), i|
      score = scores_set[i, @x0_useds_map[db.decode(row, 0)]]
      if score <= 0 then
        total_npositives += weight
      else
        total_nnegatives += weight
      end
    end
    _FP = sign(_P - 0.5, 1.0, 1.0, 0.0)
    @P = sign((1.0 - _P).hadamard!(_P).mul_rows!(@wD) - @min_weight, _P, _FP, _FP)
    $logger&.set_stage_data({
      :train_total_nnegatives => total_nnegatives, :train_total_npositives => total_npositives,
      :classifier_size => @classifier.size,
    })
  end
end
