require 'katamuki.rb'

require 'minitest/autorun'

class TestMetricsPairwise < MiniTest::Test
  def test_reorder_columns
    _X = Matrix[
      [0.0,1.0,2.0,0.0],
      [0.0,2.0,4.0,0.0],
      [0.0,3.0,6.0,0.0],
      [0.0,4.0,8.0,0.0],
      [0.0,5.0,9.0,0.0],
    ]
    assert_equal([Matrix[[2.0,1.0],[4.0,2.0],[6.0,3.0],[8.0,4.0],[9.0,5.0]], [0, 3], [2, 1]], Metrics::Pairwise::reorder_columns(_X))
    assert_equal([Matrix[[2.0,1.0,0.0,0.0],[4.0,2.0,0.0,0.0],[6.0,3.0,0.0,0.0],[8.0,4.0,0.0,0.0],[9.0,5.0,0.0,0.0]], [], [2, 1, 0, 3]], Metrics::Pairwise::reorder_columns(_X, coalesce: false))
  end
  def test_cosine_similarity
    # This tests also normalize_similarity and similarity_to_normalized_dissimilarity.
    _X = Matrix[
      [0.0,1.0,2.0,0.0],
      [0.0,2.0,4.0,0.0],
      [0.0,3.0,6.0,0.0],
      [0.0,4.0,8.0,0.0],
      [0.0,5.0,9.0,0.0],
    ]
    assert_equal(Matrix[
      [1.0,0.0,0.0,0.0],
      [0.0,1.0,0.9972862958,0.0],
      [0.0,0.9972862958,1.0,0.0],
      [0.0,0.0,0.0,1.0]
    ], Metrics::Pairwise::Similarities.cosine(_X).round(10))
    assert_equal(Matrix[
      [0.0,1.0,1.0,1.0],
      [1.0,0.0,0.0027137042,1.0],
      [1.0,0.0027137042,0.0,1.0],
      [1.0,1.0,1.0,0.0]
    ], Metrics::Pairwise::similarity_to_normalized_dissimilarity(Metrics::Pairwise::Similarities::cosine(_X)).round(10))
  end
  def test_euclidean_distance
    _X = Matrix[
      [0.0,1.0,2.0,0.0],
      [0.0,2.0,4.0,0.0],
      [0.0,3.0,6.0,0.0],
      [0.0,4.0,8.0,0.0],
      [0.0,5.0,9.0,0.0],
    ]
    assert_equal(Matrix[
      [0.0,7.4161984871,14.1774468788,0.0],
      [7.4161984871,0.0,6.7823299831,7.4161984871],
      [14.1774468788,6.7823299831,0.0,14.1774468788],
      [0.0,7.4161984871,14.1774468788,0.0]
    ], Metrics::Pairwise::Similarities::euclidean_distance(_X).round(10))
  end
end
