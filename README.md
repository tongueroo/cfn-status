# Cfn Status

[![BoltOps Badge](https://img.boltops.com/boltops/badges/boltops-badge.png)](https://www.boltops.com)

Helper library provides status of CloudFormation stack.

## Usage

Add this line to your gem's gemspec:

```ruby
  gem.add_development_dependency "cfn-status"
```

Require it to your library:

```ruby
require "cfn_status"
```

Use like so:

```ruby
status = CfnStatus.new(stack_name)
status.run # prints out stack events
```

The `status.run` will:

* print out the most recent stack events and return right away if the stack is in a completed state.
* print out the most recent stack events and poll for more events until the stack in a completed state.

To find out whether the most recent completed state of the stack was a success or a fail, you can use `status.success?`.

```ruby
status.success?
```

If you need to just wait for the stack to complete, you can also use `status.wait`.

```ruby
status.wait
status.success?
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/cfn-status.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
