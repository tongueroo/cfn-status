RSpec.describe CfnStatus do
  it "has a version number" do
    expect(CfnStatus::VERSION).not_to be nil
  end

  let(:status) do
    status = CfnStatus.new("test-stack")
    allow(status).to receive(:cfn).and_return(cfn)
    status
  end
  let(:cfn) do
    service = double("service").as_null_object
    allow(service).to receive(:describe_stacks).and_return(stack_status)
    allow(service).to receive(:describe_stack_events).and_return(stack_events)
    service
  end

  context "in progress" do
    let(:stack_status) { "UPDATE_IN_PROGRESS" }
    let(:stack_events) { JSON.load(IO.read("spec/fixtures/cfn/stack-events-in-progress.json")) }
    it "lists events since user initiated event" do
      status.refresh_events
      i = status.start_index
      expect(i).to eq 15
      # uncomment to view and debug
      # status.show_events
      # puts "****"
      # status.show_events # should not show anything
    end

    it "lists events since last shown event" do
      # first display
      status.refresh_events
      i = status.start_index
      expect(i).to eq 15

      # move the last event back in time 4 events, so should print 3 events
      status.instance_variable_set(:@last_shown_event_id, "TargetGroup-ec634c43-b887-4bde-a525-7c69782865a6")

      captured_events = []
      allow(status).to receive(:print_event) do |e|
        captured_events << "#{e["resource_type"]} #{e["resource_status"]}"
      end
      status.show_events
      expect(captured_events).to eq([
        "AWS::ElasticLoadBalancingV2::LoadBalancer DELETE_IN_PROGRESS",
        "AWS::ElasticLoadBalancingV2::LoadBalancer DELETE_COMPLETE",
        "AWS::EC2::SecurityGroup DELETE_IN_PROGRESS",
      ])
    end
  end

  context "complete" do
    let(:stack_status) { "UPDATE_COMPLETE" }
    let(:stack_events) { JSON.load(IO.read("spec/fixtures/cfn/stack-events-complete.json")) }
    it "lists events all the way to completion" do
      status.refresh_events
      i = status.start_index
      expect(i).to eq 17
      # uncomment to view and debug
      # status.show_events
    end
  end

  context "update_rollback" do
    let(:stack_status) { "UPDATE_ROLLBACK_COMPLETE" }
    let(:stack_events) { JSON.load(IO.read("spec/fixtures/cfn/stack-events-update-rollback-complete.json")) }
    it "lists events all the way to update rollback complete" do
      status.refresh_events
      expect(status.success?).to be false
      expect(status.update_rollback?).to be true
      expect(status.rollback_error_message).to include("STATIC_NAME")

      # i = status.start_index
      # expect(i).to eq 17
      # uncomment to view and debug
      # status.show_events
    end
  end

  context "huge template with large number of stack_events" do
    # Special mock for pagination testing
    let(:cfn) do
      service = double("service").as_null_object
      allow(service).to receive(:describe_stacks).and_return(stack_status)

      allow(service).to receive(:describe_stack_events) do |args|
        case args
        when {:stack_name=>"test-stack"}
          stack_events1
        when {:stack_name=>"test-stack", :next_token=>"2"}
          stack_events2
        else
          stack_events3 # final page
        end
      end

      service
    end
    let(:stack_status) { "UPDATE_COMPLETE" }
    let(:stack_events1) { JSON.load(IO.read("spec/fixtures/cfn/pages/status-command/describe_stack_events-1.json")) }
    let(:stack_events2) { JSON.load(IO.read("spec/fixtures/cfn/pages/status-command/describe_stack_events-2.json")) }
    let(:stack_events3) { JSON.load(IO.read("spec/fixtures/cfn/pages/status-command/describe_stack_events-3.json")) }

    it "paginates" do
      status.refresh_events
      expect(status.events.size).to eq 300 # 3 pages worth of events to find the "User Initiated"
    end
  end
end

