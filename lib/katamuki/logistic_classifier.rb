class LogisticClassifier
  attr_reader :model
  attr_accessor :betas_set
  def initialize(model)
    @model = model
    @betas_set = {}
    discard_score_cache
  end
  def inspect
    "LogisticClassifier<model=#{model}>"
  end
  alias to_s inspect
  def inspect_detail(ndigits: nil)
    str = "LogisticClassifier<model=#{model}>"
    @betas_set.each do |x0, betas|
      beta = get_coefficient(x0)
      next unless beta
      v = if ndigits then beta[-1].round(ndigits) else beta[-1] end
      str += "\nif y($_) == #{model.db.alphamap[x0].inspect} then score = #{v}"
      @model.db.alphamap.each(all: true) do |name, x|
        v = if ndigits then beta[x].round(ndigits) else beta[x] end
        if v < 0 then
          str += " - #{-v}*c($_)[#{name.inspect}]"
        elsif v > 0 then
          str += " + #{v}*c($_)[#{name.inspect}]"
        end
      end
      str += ' end'
    end
    str
  end
  def size
    l1norm = 0.0
    @betas_set.each do |x0, _| l1norm += get_coefficient(x0).l1norm end
    l1norm
  end

  def coefficients
    betas = []
    varnames = []
    model.db.alphamap.each(all: true) do |name, i|
      beta = get_coefficient(i)
      betas[i] = beta
      varnames[i] = name
    end
    df = DataFrame.from_a([], colnames: ['varname', 'intercept'] + varnames)
    betas.each.with_index do |beta, i|
      beta = if beta then beta.to_a else Vector.new(df.ncols - 1).to_a end
      df << [model.db.alphamap[i], beta[-1]] + beta[0..-2]
    end
    df
  end
  def partial_dependence_components
    intercepts = {}
    slopes = {}
    internals = model.get_internal_representation
    x0_useds, x0_useds_map = internals[:x0_useds], internals[:x0_useds_map]
    cD = internals[:cD]
    _Z = calculate_scores_set_(cD, x0_useds)
    model.db.each.with_index do |(row, weight), i|
      x0 = model.db.decode(row, 0)
      score = _Z[i,x0_useds_map[x0]]
      x0_useds.each do |k|
        intercepts[k] = (intercepts[k] || 0.0) + weight*score
        slopes[k] = (slopes[k] || 0.0) + weight*(get_coefficient(x0)[k] - (score - get_coefficient(x0)[-1])/(model.db.J - 1))
      end
    end
    intercepts.each do |k, intercept| intercepts[k] = intercept/model.db.weight end
    slopes.each do |k, slope| slopes[k] = slope/model.db.weight end
    {:intercepts => intercepts, :slopes => slopes}
  end
  def score_deltas
    scores = {}
    deltas = {}
    internals = model.get_internal_representation
    x0_useds, x0_useds_map = internals[:x0_useds], internals[:x0_useds_map]
    cD = internals[:cD]
    _Z = calculate_scores_set_(cD, x0_useds)
    model.db.each.with_index do |(row, weight), i|
      x0 = model.db.decode(row, 0)
      score = _Z[i,x0_useds_map[x0]]
      x0_useds.each.with_index do |k, j|
        scores[k] = (scores[k] || 0.0) + weight*score
        deltas[k] = (deltas[k] || 0.0) + weight*(_Z[i,j] - score)
      end
    end
    scores.each do |k, score| scores[k] = score/model.db.weight end
    deltas.each do |k, delta| deltas[k] = delta/model.db.weight end
    {:scores => scores, :deltas => deltas}
  end

  def discard_score_cache
    @score_cache = {}
    @coeff_cache = {}
    @matrix_cache = {}
  end
  def merge!(classifier)
    discard_score_cache
    classifier.betas_set.each do |x0, betas|
      self_betas = @betas_set[x0] ||= {}
      betas.each do |order, beta| (self_betas[order] ||= Vector.new(beta.length)).add!(beta) end
    end
  end

  def get_coefficient(x0)
    return @coeff_cache[x0] if @coeff_cache[x0]
    c = @coeff_cache[x0] = Vector.new(model.db.alphamap.size + 1)
    @betas_set[x0].each do |order, beta|
      unless @matrix_cache[order] then
        _M = model.clustering.map(order)[:M]
        _M = _M.resize(_M.nrows + 1, _M.ncols + 1)
        _M[-1,-1] = 1.0
        @matrix_cache[order] = _M
      end
      c.add!(beta*@matrix_cache[order])
    end if @betas_set[x0]
    c
  end
  def calculate_scores_set_(cD, x0)
    _B = Matrix.new(model.db.alphamap.size + 1, x0.length)
    x0.each.with_index do |x, j|
      betas = get_coefficient(x)
      betas.length.times do |i| _B[i,j] = betas[i] end
    end
    cD*_B
  end
  def calculate_score(row)
    @score_cache[row] = calculate_scores(row, model.db.decode(row, 0)) unless @score_cache[row]
    @score_cache[row]
  end
  def calculate_scores(row, x0)
    c = Vector.new(model.db.alphamap.size + 1)
    c[-1] = 1.0
    1.upto(model.db.J - 1) do |j| c[model.db.decode(row, j)%model.db.alphamap.size] += 1.0 end
    calculate_scores_(c, x0)
  end
  def calculate_score_(c, x0)
    if @betas_set[x0] then get_coefficient(x0).dot(c) else 0.0 end
  end
  def calculate_scores_(c, x0)
    case x0
    when Array
      x0.collect! do |i| calculate_score_(c, i) end
    when Integer
      calculate_score_(c, x0)
    else
      raise "x0 must be Array or Integer"
    end
  end
end
