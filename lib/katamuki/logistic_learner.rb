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
    @Y = {}
    @P = {}
    @x0_useds.each.with_index do |x0, i|
      @Y[x0] = Vector.new(db.size)
      @P[x0] = Vector.new(db.size).fill(1.0/@x0_useds.size)
    end
    @db.each.with_index do |(row, weight), i| @Y[db.decode(row, 0)][i] = 1.0 end
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
      1.upto(db.J - 1) do |j| cD[i,db.decode(row, j)] += 1.0 end
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
    @x0_useds.each do |x0|
      begin
        classifier.betas_set[x0] = {}
        y, p = @Y[x0], @P[x0]
        w = (1.0 - p).hadamard!(p)
        z = (y - p).hadamard!(w.power_elements(-1.0, 0.0))
        beta = solve_weighted_least_squares(z, cD, w.hadamard!(@wD))
        beta_mean.add!(beta)
        classifier.betas_set[x0][order] = beta
      rescue LAPACK::Info
        $logger&.error(:logistic_learner_solve_weighted_least_squares, "#{t}: #{db.alphamap[x0]} => #{$!}")
        classifier.betas_set[x0][order] = Vector.new(cD.ncols)
      end
    end
    beta_mean.hadamard!(1.0/@x0_useds.length)
    @x0_useds.each do |x0| classifier.betas_set[x0][order].sub!(beta_mean).hadamard!(shrinkage) end
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
      @x0_useds.each.with_index do |x0, k|
        @P[x0][i] = if _P[i,k]*(1.0 - _P[i,k])*weight >= @min_weight then _P[i,k] elsif _P[i,k] >= 0.5 then 1.0 else 0.0 end
      end
    end
    $logger&.set_stage_data({
      :train_total_nnegatives => total_nnegatives, :train_total_npositives => total_npositives,
      :classifier_size => @classifier.size,
    })
  end
end
