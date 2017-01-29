class DatabaseClassifier
  attr_reader :model
  attr_accessor :threshold
  def initialize(model, threshold)
    @model = model
    @threshold = threshold
    discard_score_cache
  end
  def inspect
    "DatabaseClassifier<model=#{model}, threshold=#{threshold}>"
  end
  alias inspect_detail inspect
  alias to_s inspect
  def size
    model.db.size
  end

  def discard_score_cache
    @score_cache = {}
  end

  def calculate_score(row)
    unless @score_cache[row] then
      if model.db[row] then
        @score_cache[row] = 0
      else
        cells = model.db.decode(row)
        _J = model.db.J
        min_score = _J
        model.db.each do |dbrow, _|
          score = 0
          _J.times do |j|
            score += 1 if cells[j] != model.db.decode(dbrow, j)
            break if score >= min_score
          end
          min_score = score if min_score > score
          break if min_score == 1
        end
        @score_cache[row] = min_score
      end
    end
    threshold - @score_cache[row]
  end
end
