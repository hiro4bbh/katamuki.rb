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
      [0.0,1.0,0.9972862957937585,0.0],
      [0.0,0.9972862957937585,1.0,0.0],
      [0.0,0.0,0.0,1.0],
    ], Metrics::Pairwise::Similarities.cosine(_X))
    assert_equal(Matrix[
      [0.0,1.0,1.0,1.0],
      [1.0,0.0,0.0027137042062415073,1.0],
      [1.0,0.0027137042062415073,0.0,1.0],
      [1.0,1.0,1.0,0.0]
    ], Metrics::Pairwise::similarity_to_normalized_dissimilarity(Metrics::Pairwise::Similarities::cosine(_X)))
  end
end
