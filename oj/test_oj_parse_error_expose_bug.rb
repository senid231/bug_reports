# frozen_string_literal: true

begin
  require 'bundler/inline'
rescue LoadError => e
  warn 'Bundler version 1.10 or later is required. Please update your Bundler'
  raise e
end

puts "Ruby #{RUBY_VERSION}"
gemfile(true) do
  source 'https://rubygems.org'

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem 'activesupport'
  gem 'oj', '3.15.0'
end

require 'active_support'
require 'json'
require 'oj'

Oj.mimic_JSON()
# Oj::Rails.mimic_JSON()

require 'minitest/autorun'

# Ensure backward compatibility with Minitest 4
Minitest::Test = MiniTest::Unit::TestCase unless defined?(Minitest::Test)

class BugTest < Minitest::Test
  def test_invalid_float_short
    error = assert_raises(::JSON::ParserError) do
      ::JSON.parse('{ "foo": 84e }')
    end
    assert_equal "unexpected token at '{ \"foo\": 84e }'", error.message
  end

  def test_invalid_float_long
    error = assert_raises(::JSON::ParserError) do
      ::JSON.parse('{ "foo": 84eb234 }')
    end
    assert_equal "unexpected token at '{ \"foo\": 84eb234 }'", error.message
  end
end
