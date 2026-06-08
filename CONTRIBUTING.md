
# Contributing to activerecord-tenanted

## Getting up and running

- clone this repository
- `bundle install`
- `bin/test`, which will run:
  - rubocop checks
  - unit tests
  - integration tests


## Test scenarios

Most tests rely on one or more "scenarios" being loaded. A "scenario" is a combination of:

- database configuration
- model configuration

and the `database.yml` and model files are all located under `test/scenarios/`.

In the unit testing suite, there are some scenario helpers (e.g., `for_each_scenario`) in `test/test_helper.rb` that allow us to run the tests under one or more scenarios using nested `describe` blocks.


## Running unit tests

Isolate the unit tests with `bin/test-unit`. The test files are all under `test/unit/`.


## Running integration tests

Isolate the integration testing suite with `bin/test-integration`, which:

- for each scenario
  - makes a copy of the `test/smarty/` app
  - write the scenario files: database.yml, models, and migrations
  - copy the config and test files from `test/integration/`
  - setup the databases
  - run the integration tests


## Testing against multiple Rails versions

The matrix is defined in `Appraisals` ([Appraisal](https://github.com/thoughtbot/appraisal)).

### Setup

```bash
bundle exec appraisal generate
bundle exec appraisal install
```

### Running tests

Against a specific single version of Rails:

```bash
bundle exec appraisal rails-8-1 bin/test-unit
bundle exec appraisal rails-8-1 bin/test-integration
```

Against the entire matrix of Rails versions:

```bash
bundle exec appraisal bin/test-unit
bundle exec appraisal bin/test-integration
```


## Making a release

A quick checklist for releasing activerecord-tenanted

- Prechecks
  - [ ] make sure CI is green!
  - [ ] update `CHANGELOG.md` and `lib/active_record/tenanted/version.rb`
  - [ ] commit and create a git tag
- Release
  - [ ] `bundle exec rake build`
  - [ ] `git push && git push --tags`
  - [ ] `gem push pkg/activerecord-tenanted*.gem`
  - [ ] create a release at https://github.com/basecamp/activerecord-tenanted/releases
- Post-release
  - [ ] bump `lib/active_record/tenanted/version.rb` to a prerelease version like `1.2.3.dev`
