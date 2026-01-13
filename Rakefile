# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/testtask"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/**/*_spec.rb"
end

RSpec::Core::RakeTask.new("spec:unit") do |t|
  t.pattern = "spec/unit/**/*_spec.rb"
end

RSpec::Core::RakeTask.new("spec:integration") do |t|
  t.pattern = "spec/integration/**/*_spec.rb"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

begin
  require "appraisal"
rescue LoadError
end

desc "Generate RBS files from inline annotations"
task :rbs_inline do
  sh "bundle exec rbs-inline --output sig lib"
end

desc "Run Steep type check"
task :steep do
  sh "bundle exec steep check"
end

desc "Install RBS collection"
task :rbs_collection_install do
  sh "bundle exec rbs collection install"
end

desc "Run all type checks (generate RBS and run Steep)"
task typecheck: %i[rbs_inline steep]

task default: %i[spec test]

desc "Run tests against all Rails versions"
task :test_all do
  sh "bundle exec appraisal rspec"
  sh "bundle exec appraisal rake test"
end
