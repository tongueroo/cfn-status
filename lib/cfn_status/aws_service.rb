require "aws-sdk-cloudformation"

class CfnStatus
  module AwsService
    def cfn
      @cfn ||= Aws::CloudFormation::Client.new(aws_options)
    end

    def stack_exists?(stack_name)
      return true if ENV['TEST']
      return false if @options[:noop]

      exist = nil
      begin
        # When the stack does not exist an exception is raised. Example:
        # Aws::CloudFormation::Errors::ValidationError: Stack with id blah does not exist
        cfn.describe_stacks(stack_name: stack_name)
        exist = true
      rescue Aws::CloudFormation::Errors::ValidationError => e
        if e.message =~ /does not exist/
          exist = false
        elsif e.message.include?("'stackName' failed to satisfy constraint")
          # Example of e.message when describe_stack with invalid stack name
          # "1 validation error detected: Value 'instance_and_route53' at 'stackName' failed to satisfy constraint: Member must satisfy regular expression pattern: [a-zA-Z][-a-zA-Z0-9]*|arn:[-a-zA-Z0-9:/._+]*"
          puts "Invalid stack name: #{stack_name}"
          puts "Full error message: #{e.message}"
          exit 1
        else
          raise # re-raise exception  because unsure what other errors can happen
        end
      end
      exist
    end

    def find_stack(stack_name)
      resp = cfn.describe_stacks(stack_name: stack_name)
      resp.stacks.first
    rescue Aws::CloudFormation::Errors::ValidationError => e
      # example: Stack with id demo-web does not exist
      if e.message =~ /Stack with/ && e.message =~ /does not exist/
        nil
      else
        raise
      end
    end

    def rollback_complete?(stack)
      stack&.stack_status == 'ROLLBACK_COMPLETE'
    end

    # Override the AWS retry settings.
    #
    # The aws-sdk-core has exponential backup with this formula:
    #
    #   2 ** c.retries * c.config.retry_base_delay
    #
    # Source:
    #   https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-sdk-core/lib/aws-sdk-core/plugins/retry_errors.rb
    #
    # So the max delay will be 2 ** 7 * 0.6 = 76.8s
    #
    # Only scoping this to deploy because dont want to affect people's application that use the aws sdk.
    #
    # There is also additional rate backoff logic elsewhere, since this is only scoped to deploys.
    #
    # Useful links:
    #   https://github.com/aws/aws-sdk-ruby/blob/master/gems/aws-sdk-core/lib/aws-sdk-core/plugins/retry_errors.rb
    #   https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html
    #
    def aws_options
      options = {
        retry_limit: 7, # default: 3
        retry_base_delay: 0.6, # default: 0.3
      }
      options.merge!(
        log_level: :debug,
        logger: Logger.new($stdout),
      ) if ENV['CFN_STATUS_DEBUG_AWS_SDK']
      options
    end
  end
end
