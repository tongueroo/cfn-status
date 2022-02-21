# Change Log

All notable changes to this project will be documented in this file.
This project *loosely* adheres to [Semantic Versioning](http://semver.org/), even before v1.0.

## [0.4.6] - 2022-02-21
- show took time for deletion also

## [0.4.5] - 2022-02-20
- [#5](https://github.com/tongueroo/cfn-status/pull/5) cfn-status retry options

## [0.4.4] - 2022-02-14
- more generic time took message

## [0.4.3] - 2021-05-27
- [#4](https://github.com/tongueroo/cfn-status/pull/4) fix current status message

## [0.4.2]
- #3 improve messaging when wait called directly. dont show old events.

## [0.4.1]
- fix require cfn_status/rollback_stack

## [0.4.0]
- #2 add handle_rollback! method

## [0.3.1]
- allow use of different cfn client

## [0.3.0]
- #1 Breaking change: rename Rename to CfnStatus, cfn/status to cfn_status
- Handle large templates and long stack_events via paginating the cfn.describe_stack_events until

## [0.2.0]
- allow require "cfn-status" to work also

## [0.1.0]
- Initial release
