require "cfn_status/version"
require "cfn_status/rollback_stack"

class CfnStatus
  class Error < StandardError; end

  autoload :AwsService, "cfn_status/aws_service"
  include AwsService

  attr_reader :events, :stack
  def initialize(stack_name, options={})
    @stack_name = stack_name
    @options = options
    @cfn = options[:cfn] # allow use of different cfn client. can be useful multiple cfn clients and with different regions
    resp = cfn.describe_stacks(stack_name: @stack_name)
    @stack = resp.stacks.first
    reset
  end

  def run
    unless stack_exists?(@stack_name)
      puts "The stack #{@stack_name.color(:green)} does not exist."
      return true
    end

    puts "The current status for the stack #{@stack_name.color(:green)} is #{stack.stack_status.color(:green)}"
    if in_progress?
      puts "Stack events (tailing):"
      # tail all events until done
      @hide_time_took = true
      wait
    else
      puts "Stack events:"
      # show the last events that was user initiated
      refresh_events
      show_events(final: true)
    end
    success?
  end

  def in_progress?
    in_progress = stack.stack_status =~ /_IN_PROGRESS$/
    !!in_progress
  end

  def reset
    @events = [] # constantly replaced with recent events
    @last_shown_event_id = nil
    @stack_deletion_completed = nil
  end

  # check for /(_COMPLETE|_FAILED)$/ status
  def wait
    # Check for in progress again in case .wait is called from other libraries like s3-antivirus
    # Showing the event messages when will show old messages which can be confusing.
    return unless in_progress?

    puts "Waiting for stack to complete"
    start_time = Time.now

    refresh_events
    until completed || @stack_deletion_completed
      show_events(final: false)
    end
    show_events(final: true) # show the final event

    if @stack_deletion_completed
      puts "Stack #{@stack_name} deleted."
      show_took(start_time)
      return
    end

    # Never gets beyond here when deleting a stack because the describe stack returns nothing
    # once the stack is deleted. Gets here for stack create and update though.

    if last_event_status =~ /_FAILED/
      puts "Stack failed: #{last_event_status}".color(:red)
      puts "Stack reason #{@events[0]["resource_status_reason"]}".color(:red)
    elsif last_event_status =~ /_ROLLBACK_/
      puts "Stack rolled back: #{last_event_status}".color(:red)
    else # success
      puts "Stack success status: #{last_event_status}".color(:green)
    end

    return if @hide_time_took # set in run
    show_took(start_time)
    success?
  end

  def show_took(start_time)
    took = Time.now - start_time
    puts "Time took: #{pretty_time(took).color(:green)}"
  end

  def completed
    last_event_status =~ /(_COMPLETE|_FAILED)$/ &&
    @events[0]["logical_resource_id"] == @stack_name &&
    @events[0]["resource_type"] == "AWS::CloudFormation::Stack"
  end

  def last_event_status
    @events.dig(0, "resource_status")
  end

  # Only shows new events
  def show_events(final: false)
    if @last_shown_event_id.nil?
      i = start_index
      print_events(i)
    else
      i = last_shown_index
      # puts "last_shown index #{i}"
      print_events(i-1) unless i == 0
    end

    return if final
    sleep 5 unless ENV['TEST']
    refresh_events
  end

  def print_events(i)
    @events[0..i].reverse.each do |e|
      print_event(e)
    end

    @last_shown_event_id = @events[0]["event_id"]
    # puts "@last_shown_event_id #{@last_shown_event_id.inspect}"
  end

  def print_event(e)
    message = [
      event_time(e["timestamp"]),
      e["resource_status"],
      e["resource_type"],
      e["logical_resource_id"],
      e["resource_status_reason"]
    ].join(" ")
    message = message.color(:red) if e["resource_status"] =~ /_FAILED/
    puts message
  end

  # https://stackoverflow.com/questions/18000432/rails-12-hour-am-pm-range-for-a-day
  def event_time(timestamp)
    Time.parse(timestamp.to_s).localtime.strftime("%I:%M:%S%p")
  end

  # Refreshes the @events in memory.
  #
  def refresh_events
    resp = cfn.describe_stack_events(stack_name: @stack_name)
    @events = resp["stack_events"]

    # refresh_events uses add_events_pages and resp["next_token"] to load all events until:
    #
    #     1. @last_shown_event_id found - if @last_shown_event_id is set
    #     2. User Initiated Event found - fallback when @last_shown_event_id is not set
    #
    if @last_shown_event_id
      add_events_pages(resp, :last_shown_index)
    else
      add_events_pages(resp, :start_index)
    end

  rescue Aws::CloudFormation::Errors::ValidationError => e
    if e.message =~ /Stack .* does not exis/
      @stack_deletion_completed = true
    else
      raise
    end
  end

  # Examples:
  #
  #     add_events_pages(:start_index)
  #     add_events_pages(:last_shown_index)
  #
  # if index_method is start_index
  #   loops add_events_pagess through describe_stack_events until "User Initiated" is found
  #
  # if index_method is last_shown_index
  #   loops add_events_pagess through describe_stack_events until last_shown_index is found
  #
  def add_events_pages(resp, index_method)
    found = !!send(index_method)
    until found
      resp = cfn.describe_stack_events(stack_name: @stack_name, next_token: resp["next_token"])
      @events += resp["stack_events"]
      found = !!send(index_method)
    end
  end

  # Should always find a "User Initiated" stack event when @last_shown_index is not set
  def start_index
    @events.find_index do |event|
      event["resource_type"] == "AWS::CloudFormation::Stack" &&
      event["resource_status_reason"] == "User Initiated"
    end
  end

  def last_shown_index
    @events.find_index do |event|
      event["event_id"] == @last_shown_event_id
    end
  end

  def success?
    resource_status = @events[0]["resource_status"]
    %w[CREATE_COMPLETE UPDATE_COMPLETE].include?(resource_status)
  end

  def update_rollback?
    @events[0]["resource_status"] == "UPDATE_ROLLBACK_COMPLETE"
  end

  def find_update_failed_event
    i = @events.find_index do |event|
      event["resource_type"] == "AWS::CloudFormation::Stack" &&
      event["resource_status_reason"] == "User Initiated"
    end

    @events[0..i].reverse.find do |e|
      e["resource_status"] == "UPDATE_FAILED"
    end
  end

  def rollback_error_message
    return unless update_rollback?

    event = find_update_failed_event
    return unless event

    reason = event["resource_status_reason"]
    messages_map.each do |pattern, message|
      if reason =~ pattern
        return message
      end
    end

    reason # default message is original reason if not found in messages map
  end

  def messages_map
    {
      /CloudFormation cannot update a stack when a custom-named resource requires replacing/ => "A workaround is to run ufo again with STATIC_NAME=0 and to switch to dynamic names for resources. Then run ufo again with STATIC_NAME=1 to get back to statically name resources. Note, there are caveats with the workaround.",
      /cannot be associated with more than one load balancer/ => "There's was an issue updating the stack. Target groups can only be associated with one load balancer at a time. The workaround for this is to use UFO_FORCE_TARGET_GROUP=1 and run the command again. This will force the recreation of the target group resource.",
      /SetSubnets is not supported for load balancers of type/ => "Changing subnets for Network Load Balancers is currently not supported. You can try workarouding this with UFO_FORCE_ELB=1 and run the command again. This will force the recreation of the elb resource."
    }
  end

  # http://stackoverflow.com/questions/4175733/convert-duration-to-hoursminutesseconds-or-similar-in-rails-3-or-ruby
  def pretty_time(total_seconds)
    minutes = (total_seconds / 60) % 60
    seconds = total_seconds % 60
    if total_seconds < 60
      "#{seconds.to_i}s"
    else
      "#{minutes.to_i}m #{seconds.to_i}s"
    end
  end

  def handle_rollback!
    CfnStatus::RollbackStack.handle!(@stack_name, cfn: cfn)
  end
end
