module Clamd::Continuousd
  class Scheduler
    record Rule,
      id : Int64,
      handler : Proc(Time) | Proc(Time?) | Proc(Nil),
      next_time : Time

    @rules : Array(Rule)
    @next_rule_id = 0_i64
    @mutex = Mutex.new

    def initialize
      @rules = Array(Rule).new
    end

    def rules
      @mutex.synchronize { @rules.dup }
    end

    def add_rule(handler, next_time : Time, rule_id = nil) : Int64
      @mutex.synchronize do
        if rule_id
          rule = Rule.new(rule_id, handler, next_time)
        else
          rule = Rule.new(@next_rule_id, handler, next_time)
          @next_rule_id += 1
        end

        found_index = @rules.bsearch_index { |item| item.next_time <= rule.next_time }

        if found_index
          @rules.insert(found_index, rule)
        else
          @rules.push(rule)
        end

        rule.id
      end
    end

    def add_rule(handler, rule_id = nil)
      add_rule(handler, handler.call, rule_id)
    end

    def remove_rule(id : Int64)
      @mutex.synchronize do
        @rules.reject! { |rule| rule.id == id }
      end
    end

    def next_rule
      @mutex.synchronize { @rules[-1]? }
    end

    def process_rules
      loop do
        sleep_rule = next_rule
        if !sleep_rule
          sleep 5.milliseconds
          next
        end

        sleep_time = sleep_rule.next_time - Time.now
        Continuousd.logger.debug "Sleeping #{sleep_time}", "sched"
        sleep sleep_time if sleep_time.ticks > 0

        @mutex.synchronize do
          rule = @rules.pop?
          break unless rule
          break if rule != sleep_rule

          Continuousd.logger.debug "Running rule #{rule.id}", "sched"

          next_time = rule.handler.call
          add_rule(rule.handler, next_time, rule.id) if next_time
        end
      end
    end
  end
end
