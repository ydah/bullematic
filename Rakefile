# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

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

task default: %i[spec]
