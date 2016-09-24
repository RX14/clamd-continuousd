require "../spec_helper"

describe Clamd::Continuousd::Scheduler do
  it "orders rules properly" do
    sched = Clamd::Continuousd::Scheduler.new
    sched.rules.size.should eq(0)

    sched.add_rule(->{ 2.seconds.from_now })
    sched.add_rule(->{ 1.second.from_now })
    sched.add_rule(->{ 3.seconds.from_now })
    sched.add_rule(->{ 1.second.from_now })

    times = sched.rules.map &.next_time
    times[0].should be_close(3.seconds.from_now, 1.millisecond)
    times[1].should be_close(2.seconds.from_now, 1.millisecond)
    times[2].should be_close(1.second.from_now, 1.millisecond)
    times[3].should be_close(1.second.from_now, 1.millisecond)

    sched.next_rule.not_nil!.next_time.should be_close(1.second.from_now, 1.millisecond)
  end
end
