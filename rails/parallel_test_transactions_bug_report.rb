# frozen_string_literal: true

begin
  require 'bundler/inline'
rescue LoadError => e
  warn 'Bundler version 1.10 or later is required. Please update your Bundler'
  raise e
end

gemfile(true) do
  source 'https://rubygems.org'

  gem 'rails', '~> 7.0', require: false
  gem 'pg', require: false
  gem 'timeout', '0.3.2'

  gem 'rspec-rails', '~> 6.0.0', require: false
end

ENV['RAILS_ENV'] = 'test'

require 'logger'
require 'pg'
require 'rails'
require 'active_record/railtie'

class TestApp < Rails::Application
  config.root = __dir__
  config.hosts << 'example.org'
  secrets.secret_key_base = 'secret_key_base'

  config.logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
  Rails.logger = config.logger

  config.active_record.verbose_query_logs = true
end

database_name = ENV['DB_NAME'] || 'parallel_test_transactions_bug_report'
system "psql -c 'DROP DATABASE IF EXISTS #{database_name}'"
system "psql -c 'CREATE DATABASE #{database_name}'"
ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: database_name, pool: 10)
ActiveRecord::Base.logger = Rails.logger

ActiveRecord::Schema.define do
  create_table :request_logs, force: true do |t|
    t.integer :user_id, null: false
    t.integer :requests_count, null: false
  end

  add_index :request_logs, :user_id, unique: true
end

class RequestLog < ActiveRecord::Base
  validates :user_id, presence: true
  validates :requests_count, numericality: { integer: true, greater_than_or_equal_to: 1 }

  def self.lock_user_id!(user_id)
    sql = sanitize_sql_array ['SELECT pg_advisory_xact_lock(1, ?)', user_id]
    connection.execute(sql)
  end
end

class RequestReceived
  def self.call(user_id)
    RequestLog.transaction do
      RequestLog.lock_user_id!(user_id)
      log = RequestLog.find_by(user_id: user_id)
      if log
        log.requests_count += 1
        log.save!
      else
        RequestLog.create!(user_id: user_id, requests_count: 1)
      end
    end
  end
end

puts "Rails version is: #{Rails::VERSION}"
puts "Ruby version is: #{RUBY_VERSION}"
require 'rspec/rails'
require 'rspec/autorun'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
    c.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |c|
    c.allow_message_expectations_on_nil = false
    c.verify_partial_doubles = true
  end

  config.raise_errors_for_deprecations!
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.use_transactional_fixtures = true

  # config.around(:each) do |example|
  #   ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
  #     example.run
  #
  #     raise ActiveRecord::Rollback
  #   end
  # end
end

RSpec.describe 'parallel' do
  before(:each) do
    RequestLog.create!(user_id: 111, requests_count: 25)
  end

  it 'run in parallel' do
    threads = []
    parallel_qty = ENV.fetch('PARALLEL_QTY', 3).to_i
    user_id = 123
    old_count = RequestLog.count

    ## subject starts
    Array.new(parallel_qty) do |index|
      threads << Thread.new do
        Rails.logger.tagged("thread:#{index + 1}") do
          RequestReceived.call(user_id)
        end
      end
    end
    threads.each(&:join)
    ## subject ends

    expect(threads.size).to eq parallel_qty
    expect(RequestLog.count).to eq old_count + 1
    log = RequestLog.find_by(user_id: user_id)
    expect(log).to be_present
    expect(log.requests_count).to eq parallel_qty
  end
end
