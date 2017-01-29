require 'katamuki/rule_classifier'

class RuleLearner
  module Impurity
    def Impurity::gini(m, n)
      2.0*m*(n - m)/(n*n)
    end
    def Impurity::entropy(m, n)
      if m == 0 or m == n then
        0
      else
        mf, nf = Float(m), Float(n)
        -(mf*Math.log(mf/nf) + (nf - mf)*Math.log((nf - mf)/nf))/nf
      end
    end
  end

  attr_reader :db, :impurity, :max_depth, :min_weight, :classifier
  def initialize(db, impurity, max_depth: 1, min_weight: 1e-05)
    @db = db
    @work_db = db.copy
    raise "specify impurity of #{
      (Impurity.methods - Impurity.class.methods).join(' or ')
    }" unless Impurity.respond_to? impurity
    @impurity = impurity
    @max_depth = max_depth
    @min_weight = min_weight
    @work_db.update_weights do |_, weight| (weight/@min_weight).floor end
    @alphas = []
    @classifier = RuleClassifier.new(self)
  end
  def inspect
    "RuleLearner<db=#{db}, impurity=#{impurity}, max_depth=#{max_depth}, min_weight=#{min_weight}>"
  end
  alias to_s inspect
  def parameter_string
    "RuleLearner-impurity_#{impurity}-max_depth#{max_depth}-min_weight#{min_weight}"
  end

  def learn_rule(db, response, depth=0)
    n = db.weight
    split, split_impurity_gain = nil, 0
    (1..(db.J - 1)).each do |j|
      m = db[0][response]
      candidates = db[0,j].select(response).sort_by!do |candidate|
        -Float(db[0,j][response+candidate]).divorinf(Float(db[j][candidate]))
      end
      root_impurity = Impurity.method(impurity).call(m, n)
      left_npos, left_total = 0, 0
      maxi, maximpurity_gain = 0, 0
      candidates.each.with_index do |candidate, i|
        left_npos += db[0,j][response+candidate]
        left_total += db[j][candidate]
        left_impurity, right_impurity = Impurity.method(impurity).call(left_npos, left_total), Impurity.method(impurity).call(m - left_npos, n - left_total)
        impurity_gain = root_impurity - (left_total*left_impurity + (n - left_total)*right_impurity)/Float(n)
        maxi, maximpurity_gain = i, impurity_gain if impurity_gain > maximpurity_gain
      end
      split, split_impurity_gain = [j, candidates[0..maxi]], maximpurity_gain if maximpurity_gain > split_impurity_gain
    end
    if split and depth + 1 < max_depth then
      dbclone = db.copy
      dbclone.update_weights do |row, weight|
        if split[1].include?(dbclone.extract(row, split[0])) then weight else 0 end
      end
      split2, split2_impurity_gain = learn_rule(dbclone, response, depth + 1)
      split, split_impurity_gain = split + split2, split2_impurity_gain if split2
    end
    return [split, split_impurity_gain]
  end
  def learn(t)
    classifier = RuleClassifier.new(self)
    @work_db[0].each do |response, response_count|
      pattern, _ = learn_rule(@work_db, response)
      classifier.add_pattern(response, pattern, 1.0) if pattern
    end
    w1, w0 = 0, 0
    w1orig, w0orig = 0, 0
    corrects = {}
    @work_db.each do |row, weight|
      if classifier.calculate_score(row) > 0 then
        corrects[row] = true
        w0 += weight
        w0orig += db[row]
      else
        w1 += weight
        w1orig += db[row]
      end
    end
    alpha = Math.log((Float(w0) + 1.0)/(Float(w1) + 1.0))/2.0
    $logger&.set_stage_data({
      :train_onestage_nnegatives => w0orig, :train_onestage_npositives => w1orig,
      :alpha => alpha,
    })
    @alphas << alpha
    @work_db.update_weights do |row, weight|
      (weight*Math.exp(-alpha*(if corrects[row] then 1 else -1 end))).floor
    end
    @classifier.merge!(classifier, alpha)
    w1total, w0total = 0, 0
    db.each do |row, weight|
      if @classifier.calculate_score(row) > 0 then
        w0total += weight
      else
        w1total += weight
      end
    end
    $logger&.set_stage_data({
      :train_total_nnegatives => w0total, :train_total_npositives => w1total,
      :classifier_size => @classifier.size,
    })
  end
end
