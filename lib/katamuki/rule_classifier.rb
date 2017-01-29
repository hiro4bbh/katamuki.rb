class RuleClassifier
  attr_reader :model
  def initialize(model)
    @model = model
    @table = {}
    discard_score_cache
  end
  def inspect
    "RuleClassifier<model=#{model}, size=#{size}>"
  end
  def inspect_detail
    str = "RuleClassifier<model=#{model}, size=#{size}>\n  score = 0"
    @table.each do |y, table_y|
      ysym = model.db.decode(y, 0, to_sym: true)
      str += "\nif $_[0] == #{ysym.inspect} then\n    "
      n = 0
      rules_set = []
      table_y.each do |j_xj, rules|
        score = rules[0]
        substr = "if $_[#{j_xj[0]}] == #{model.db.decode(j_xj[1], to_sym: true)[0].inspect} then"
        if rules.length == 1 then
          substr += " score += #{score}"
        else
          substr += "\n    "
          substr += rules[1..-1].collect do |clause, subscore|
            condstrs = []
            (clause.length/2).times do |i|
              condstrs << "$_[#{clause[2*i]}] #{if clause[2*i+1].length == 1 then
                "== #{model.db.decode(clause[2*i+1][0], to_sym: true)[0].inspect}"
              else
                "in [#{clause[2*i+1].collect do |x|
                  model.db.decode(x, to_sym: true)[0].inspect
                end.join(',')}]"
              end}"
            end
            "if #{condstrs.join(' and ')} then score += #{score+subscore} end"
          end.join("\n    ")
        end
        rules_set << [substr, score]
      end
      rules_set.sort_by! do |rules| -rules[1] end
      str += rules_set.collect! do |rules| rules[0] end.join("\n  els") + "\n  end\nend"
    end
    str
  end
  def to_s
    inspect
  end
  def size
    cize = 0
    @table.each do |y, table_y|
      table_y.each do |j_xj, rules|
        cize += rules.length if rules[0] != 0 or rules.length > 1
      end
    end
    cize
  end
  def each(&b)
    @table.each do |y, table_y|
      table_y.each do |j_xj, rules|
        b.call(y, j_xj[0], j_xj[1], rules)
      end
    end
  end

  def add_pattern(y, pattern, alpha)
    discard_score_cache
    table_y = @table[y] ||= {}
    j = pattern[0]
    pattern[1].each do |xj|
      table_y_j_xj = table_y[[j,xj]] ||= [0]
      if pattern.length == 2 then
        table_y_j_xj[0] += alpha
      else
        table_y_j_xj << [pattern[2..-1], alpha]
      end
    end
  end
  def discard_score_cache
    @score_cache = {}
    @UNKNOWN_score_cache = {}
  end
  def merge!(classifier, alpha)
    discard_score_cache
    classifier.each do |y, j, xj, score|
      table_y = @table[y] ||= {}
      table_y_j_xj = table_y[[j,xj]] ||= [0]
      table_y_j_xj[0] += alpha*score[0]
      if score.length > 1 then
        table_y_j_xj.concat(score[1..-1])
        for i in 1..(score.length-1) do
          table_y_j_xj[-i][1] *= alpha
        end
      end
    end
  end

  def calculate_score(row)
    unless @score_cache[row] then
      y = model.db.extract(row, 0)
      table_y = @table[y]
      score = 0
      for j in 1..(row.length/2-1) do
        xj = model.db.extract(row, j)
        score += if model.db.decode(xj)[0] == -1 then
          unless @UNKNOWN_score_cache[xj] then
            max_score = 0
            table_y.each do |j_xj, rules|
              max_score = rules[0] if j_xj[0] == j and rules[0] > max_score
            end
            @UNKNOWN_score_cache[xj] = max_score
          end
          @UNKNOWN_score_cache[xj]
        else
          table_y_j_xj = table_y[[j, xj]]
          if table_y_j_xj then
            subscore = table_y_j_xj[0]
            if table_y_j_xj.length > 1 then
              table_y_j_xj[1..-1].each do |clause, score|
                p = (clause.length/2).times do |q|
                  xj2 = model.db.extract(row, clause[2*q])
                  break -1 unless clause[2*q+1].include?(xj2)
                end
                subscore += score if p > 0
              end
            end
            subscore
          else
            0.0
          end
        end
      end if table_y
      @score_cache[row] = score
    end
    @score_cache[row]
  end
end
