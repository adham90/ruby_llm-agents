# Contributing

Thank you for considering contributing to RubyLLM::Agents!

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build something great together.

## Getting Started

### 1. Fork the Repository

```bash
git clone https://github.com/YOUR_USERNAME/ruby_llm-agents.git
cd ruby_llm-agents
```

### 2. Install Dependencies

```bash
bin/setup
```

This installs:
- Ruby dependencies (Bundler)
- JavaScript dependencies (if any)
- Sets up the test database

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

## Development Workflow

### Running Tests

```bash
# All tests
bundle exec rake spec

# Specific file
bundle exec rspec spec/models/execution_spec.rb

# With coverage
COVERAGE=true bundle exec rake spec
```

### Linting

```bash
# Check style
bundle exec standardrb

# Auto-fix issues
bundle exec standardrb --fix
```

### Running the Example App

```bash
cd example
bin/rails db:setup
bin/rails server
```

Visit `http://localhost:3000/agents` to see the dashboard.

### Console

```bash
bin/rails console
```

## Making Changes

### Code Style

We use StandardRB for Ruby code style:

```bash
bundle exec standardrb --fix
```

Key conventions:
- 2-space indentation
- No trailing whitespace
- Meaningful variable/method names
- Comments for complex logic

### Commit Messages

Use clear, descriptive commit messages:

```
Add retry backoff configuration option

- Add `backoff` parameter to `retries` DSL
- Support :exponential and :constant strategies
- Add jitter to prevent thundering herd
- Update documentation

Fixes #123
```

### Documentation

Update documentation for any user-facing changes:

- README.md for high-level features
- Wiki pages for detailed guides
- YARD comments for public APIs

### Tests

All changes should include tests:

```ruby
RSpec.describe MyNewFeature do
  describe ".method" do
    it "does the expected thing" do
      expect(MyNewFeature.method).to eq(expected)
    end

    context "with edge case" do
      it "handles it correctly" do
        # ...
      end
    end
  end
end
```

## Types of Contributions

### Bug Reports

1. Check existing issues first
2. Include:
   - Ruby/Rails versions
   - Gem version
   - Minimal reproduction steps
   - Expected vs actual behavior
   - Error messages/backtraces

### Feature Requests

1. Describe the use case
2. Explain why existing features don't solve it
3. Propose a solution (optional)
4. Consider backward compatibility

### Pull Requests

1. Reference any related issues
2. Include tests
3. Update documentation
4. Follow code style
5. Keep changes focused (one feature/fix per PR)

## Pull Request Process

### Before Submitting

- [ ] Tests pass: `bundle exec rake spec`
- [ ] Linting passes: `bundle exec standardrb`
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated (if applicable)

### Submitting

1. Push to your fork:
   ```bash
   git push origin feature/your-feature
   ```

2. Open a Pull Request on GitHub

3. Fill out the PR template:
   - What does this PR do?
   - Why is it needed?
   - How was it tested?
   - Any breaking changes?

### After Submitting

- Respond to review feedback
- Make requested changes
- Squash/rebase if requested
- Be patient - maintainers are volunteers

## Project Structure

```
ruby_llm-agents/
├── app/
│   ├── controllers/      # Dashboard controllers
│   ├── models/           # Execution model
│   ├── views/            # Dashboard views
│   └── jobs/             # Background jobs
├── lib/
│   └── ruby_llm/
│       └── agents/
│           ├── base.rb          # Agent base class
│           ├── configuration.rb # Configuration
│           ├── result.rb        # Result object
│           ├── workflow.rb      # Workflow orchestration
│           └── ...
├── spec/                 # Tests
├── example/             # Example Rails application
└── wiki/                # Documentation
```

## Key Classes

| Class | Purpose |
|-------|---------|
| `Base` | Agent base class with DSL |
| `Configuration` | Global settings |
| `Execution` | Database model |
| `Result` | Response wrapper |
| `Workflow` | Orchestration |
| `BudgetTracker` | Cost management |
| `CircuitBreaker` | Reliability |

## Release Process

Maintainers handle releases:

1. Update version in `version.rb`
2. Update CHANGELOG.md
3. Create release PR
4. After merge, tag release
5. Push to RubyGems

## Getting Help

- **Questions:** GitHub Discussions
- **Bugs:** GitHub Issues
- **Chat:** (coming soon)

## Recognition

Contributors are recognized in:
- CHANGELOG.md (for significant contributions)
- GitHub contributors page

Thank you for contributing!

## Related Pages

- [FAQ](FAQ) - Common questions
- [Troubleshooting](Troubleshooting) - Development issues
- [API Reference](API-Reference) - Code documentation
