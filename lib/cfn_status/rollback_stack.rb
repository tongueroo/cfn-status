class CfnStatus
  class RollbackStack
    def self.handle!(stack_name, options={})
      new(stack_name, options).run
    end

    attr_reader :status, :cfn
    def initialize(stack_name, options={})
      @stack_name = stack_name
      @cfn = options[:cfn]
      @status = CfnStatus.new(@stack_name, cfn: @cfn)
    end

    def run
      @stack = find_stack(@stack_name)
      if @stack && rollback_complete?(@stack)
        puts "Existing stack in ROLLBACK_COMPLETE state. Deleting stack before continuing."
        cfn.delete_stack(stack_name: @stack_name)
        status.wait
        status.reset
        @stack = nil # at this point stack has been deleted
      end
    end

    def rollback_complete?(stack)
      stack.stack_status == 'ROLLBACK_COMPLETE'
    end

    def find_stack(stack_name)
      return if ENV['CFN_STATUS_TEST']
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
  end
end
