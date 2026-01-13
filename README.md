<p align="center">
  <img src="assets/logo-header.svg" alt="Bullematic header logo">
  <span>Auto-fix N+1 queries detected by Bullet at runtime</span>
</p>

<p align="center">
  <a href="https://badge.fury.io/rb/bullematic"><img src="https://badge.fury.io/rb/bullematic.svg" alt="Gem Version"></a>
  <a href="https://github.com/ydah/bullematic/actions/workflows/main.yml"><img src="https://github.com/ydah/bullematic/actions/workflows/main.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#integrations">Integrations</a>
</p>

---

Bullematic hooks into [Bullet](https://github.com/flyerhzm/bullet) notifications, captures N+1 detections, and rewrites your Ruby code with `includes`, `preload`, or `eager_load` using [Prism](https://github.com/ruby/prism) AST parsing. It is designed to run in development and test environments where Bullet already runs.

## Features

- Automatic N+1 fixes for Rails scopes and queries
- Runtime capture via Bullet notifications
- AST-based rewrites powered by Prism
- Dry-run mode and optional backups
- RSpec, Minitest, and Rails integrations

## Installation

Add to your Gemfile:

```ruby
gem 'bullematic', group: [:development, :test]
```

Then install:

```bash
bundle install
```

## Requirements

- Ruby 3.1+
- Bullet 6.0+

## Quick Start

1. Configure Bullematic in your Rails initializer or test setup:

```ruby
# config/initializers/bullematic.rb (for Rails)
# or in your test setup

Bullematic.configure do |config|
  config.enabled = true
  config.auto_fix = true
  config.target_paths = %w[app/controllers app/models app/services]
  config.skip_paths = %w[app/controllers/admin]
  config.dry_run = false  # Set to true to preview changes without applying
  config.fix_strategy = :includes  # :includes, :preload, or :eager_load
  config.backup = true  # Create backup files before modifying
end
```

2. Enable Bullematic at runtime:

```bash
BULLEMATIC=1 bundle exec rspec
```

## Integrations

### RSpec

```ruby
# spec/spec_helper.rb or spec/rails_helper.rb
require 'bullematic/integrations/rspec'

RSpec.configure do |config|
  # ... your existing config
end

Bullematic::Integrations::RSpec.setup
```

### Minitest

```ruby
# test/test_helper.rb
require 'bullematic/integrations/minitest'

Bullematic::Integrations::Minitest.setup

class ActiveSupport::TestCase
  include Bullematic::Integrations::Minitest::TestHelper
end
```

### Rails

Bullematic auto-loads via Railtie in development and test environments when the gem is loaded.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | Boolean | `true` | Enable or disable Bullematic |
| `auto_fix` | Boolean | `true` | Automatically apply fixes |
| `target_paths` | Array | `['app/controllers', 'app/models', 'app/services']` | Paths to consider for fixes |
| `skip_paths` | Array | `[]` | Paths to skip |
| `dry_run` | Boolean | `false` | Preview changes without applying |
| `backup` | Boolean | `false` | Create `.bullematic.bak` backup files |
| `fix_strategy` | Symbol | `:includes` | Strategy: `:includes`, `:preload`, or `:eager_load` |
| `logger` | Logger | Auto-configured | Custom logger instance |
| `debug` | Boolean | `false` | Enable debug mode (raises errors) |

## How It Works

1. Bullet detects an N+1 query during request or test execution
2. Bullematic captures the notification and stack trace
3. At the end of the run, Bullematic parses the file with Prism
4. The AST finder locates the query that triggered the N+1
5. The AST rewriter inserts the appropriate `includes` call
6. The file is written back (or logged in dry-run mode)

### Example Transformation

Before:

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.all  # N+1 when accessing @posts.each { |p| p.comments }
  end
end
```

After:

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.includes(:comments).all
  end
end
```

## Limitations

- Dynamic queries built with `send` or metaprogramming may not be fixable
- Complex conditional branches can be hard to rewrite
- Already-optimized queries are skipped

## Development

```bash
git clone https://github.com/ydah/bullematic.git
cd bullematic
bin/setup
bundle exec rake spec
```

## Contributing

Bug reports and pull requests are welcome at https://github.com/ydah/bullematic.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgements

- [Bullet](https://github.com/flyerhzm/bullet) - N+1 query detection
- [bulletmark_repairer](https://github.com/makicamel/bulletmark_repairer) - Similar concept, inspiration for this gem
- [Prism](https://github.com/ruby/prism) - Ruby parser used for AST manipulation
