# frozen_string_literal: true

require_relative "lib/bullematic/version"

Gem::Specification.new do |spec|
  spec.name = "bullematic"
  spec.version = Bullematic::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Auto-fix N+1 queries detected by Bullet at runtime"
  spec.description = "Automatically adds includes/preload to fix N+1 queries detected by Bullet"
  spec.homepage = "https://github.com/ydah/bullematic"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ydah/bullematic"
  spec.metadata["changelog_uri"] = "https://github.com/ydah/bullematic/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?(*%w[exe/ lib/ sig/]) || %w[README.md CHANGELOG.md LICENSE.txt].include?(f)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bullet", ">= 6.0", "< 9.0"
  spec.add_dependency "prism", ">= 0.24.0"

  spec.add_development_dependency "appraisal", "~> 2.5"
  spec.add_development_dependency "combustion", "~> 1.4"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.1"
  spec.add_development_dependency "factory_bot", "~> 6.4"
  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rails", ">= 6.1"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-rails", "~> 6.1"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "sqlite3", ">= 1.7", "< 3.0"
end
