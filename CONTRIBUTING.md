# Contributing to Rails Markup

Thanks for your interest in contributing.

## Development

```bash
cd packages/rails-markup
bundle install
bundle exec rake test
```

## Running tests

```bash
bundle exec rake test
```

## Submitting changes

1. Fork the repository
2. Create a feature branch (`git checkout -b my-feature`)
3. Write tests for your changes
4. Make your changes
5. Run `bundle exec rake test` and ensure all tests pass
6. Commit your changes
7. Push to your fork and submit a pull request

## Code style

- Follow Ruby community conventions
- Keep it simple — this is a small, focused tool
- No external dependencies beyond WEBrick
- Tests for all new functionality

## Reporting bugs

Open an issue at https://github.com/nauman/rails-markup/issues with:

- Ruby version
- Steps to reproduce
- Expected vs actual behavior
