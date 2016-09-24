module Clamd::Continuousd
  class Scheduler
    record Rule,
      handler : Proc(Time),
      next_time : Time

    @rules : Array(Rule)
    @mutex = Mutex.new

    def initialize
      @rules = Array(Rule).new
    end

    def rules
      @rules.dup
    end

    def add_rule(handler, next_time)
      rule = Rule.new(handler, next_time)

      @mutex.synchronize do
        found_index = @rules.bsearch_index { |item| item.next_time <= rule.next_time }

        if found_index
          @rules.insert(found_index, rule)
        else
          @rules.push(rule)
        end
      end

      nil
    end

    def add_rule(handler)
      add_rule(handler, handler.call)
    end

    def remove_rule(rule)
      @mutex.synchronize { @rules.delete(rule) }
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
        sleep sleep_time if sleep_time.ticks > 0

        @mutex.synchronize do
          rule = @rules.pop?
          break unless rule
          break if rule != sleep_rule
          add_rule(rule.handler) # This runs the proc
        end
      end
    end
  end
end
