# frozen_string_literal: true

require 'minitest/autorun'

# some comment
module MathClass
  module_function

  def plus(a:, b:)
    a + b
  end
end

# some comment
class BugReportTest < Minitest::Test
  def test_it_works
    a = 1
    b = 2
    result = MathClass.plus(a:,
                            b:)

    assert_equal 3, result
  end
end
