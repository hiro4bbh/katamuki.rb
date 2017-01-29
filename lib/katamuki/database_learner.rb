require 'katamuki/database_classifier'

class DatabaseLearner
  attr_reader :db, :classifier
  def initialize(db)
    @db = db
    @classifier = DatabaseClassifier.new(self, 0)
  end
  def inspect
    "DatabaseLearner<db=#{db}>"
  end
  alias to_s inspect
  def parameter_string
    "DatabaseLearner"
  end

  def learn(t)
    classifier.threshold = t
    $logger&.set_stage_data({
      :train_onestage_nnegatives => db.weight, :train_onestage_npositives => 0,
    })
    $logger&.set_stage_data({
      :train_total_nnegatives => db.weight, :train_total_npositives => 0,
      :classifier_size => classifier.size,
    })
  end
end
