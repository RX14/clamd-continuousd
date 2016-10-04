require "http"
require "json"
require "logger"

require "./clamd-continuousd/*"

class Channel::Buffered(T)
  def queue_size
    @queue.size
  end
end

module Clamd::Continuousd
  @@logger : Logger?
  @@path_rule_map = Hash(String, Int64).new
  @@scheduler = Scheduler.new
  @@clamd = ClamdQueue.new(CONFIG.clamd.host, CONFIG.clamd.port)
  @@files = FileCache.new(CONFIG.sites.map &.dir, ->handle_dir_change(FileOperation, FileInfo))
  @@cloudflare = Cloudflare.new
  @@startup_file_count = 0

  def self.logger
    @@logger ||= begin
                   l = Logger.new(STDOUT)
                   l.level = CONFIG.debug ? Logger::DEBUG : Logger::INFO
                   l.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
                     io << "[" << datetime << "] " << progname.rjust(7) << " " << severity.rjust(5) << ": " << message
                   end
                   l
                 end
  end

  def self.start
    dirs = CONFIG.sites.map &.dir
    logger.info "Starting up (dirs: #{dirs})", "main"
    dirs.each { |d| check_dir(d) }

    spawn { @@files.start_watching }

    # Add all existing files slowly
    dirs.each do |dir|
      entries = Dir.entries(dir)
      entries.shuffle!

      @@startup_file_count += entries.size

      ten_percent = entries.size / 10
      entries.each_with_index do |file, i|
        logger.info "Starting up (#{dir}): #{i * 100 / entries.size}%", "main" if i % ten_percent == 0

        path = File.join(dir, file)
        file_info = File.stat(path)
        next unless file_info.file?

        scan_period = scan_period(file_info.mtime - Time.now)
        # Use ticks after cr#3350 is fixed
        next_scan = Time::Span.new(rand(scan_period.total_milliseconds) * Time::Span::TicksPerMillisecond).from_now

        @@scheduler.add_rule(->{ @@files.update_file(path, file_info.mtime) }, next_scan)
      end
    end

    spawn { @@scheduler.process_rules }
    @@clamd.spawn_workers

    server = HTTP::Server.new("0.0.0.0", 8080) do |ctx|
      ctx.response.content_type = "application/json"
      {
        clamd_queue_size: @@clamd.@queue.queue_size,

        scans_per_second_5m: Stats.scans_per_second_5m,
        scans_per_second_10s: Stats.scans_per_second_10s,

        avg_scan_duration_5m: Stats.avg_scan_duration_5m,
        avg_scan_duration_10s: Stats.avg_scan_duration_10s,

        executor_utilization_frac_5m: Stats.executor_utilization_frac_5m,
        executor_utilization_frac_10s: Stats.executor_utilization_frac_10s,

        new_files_per_hour: Stats.new_files_per_hour(@@files.files.each_value),
        startup_file_count: @@startup_file_count,
        current_files: @@files.files.size
      }.to_json(ctx.response)
    end
    spawn { server.listen }

    sleep
  end

  private def self.handle_dir_change(op, info)
    case op
    when FileOperation::Update
      logger.debug "File updated: #{info.path}", "main"
      if rule_id = @@path_rule_map[info.path]?
        @@scheduler.remove_rule(rule_id)
      end

      rule_id = @@scheduler.add_rule(->{
        logger.debug "Running rule for #{info.path}", "main"
        @@clamd.scan(info.path)

        file_age = info.modified - Time.now
        scan_period(file_age).from_now
      }, Time.now)

      @@path_rule_map[info.path] = rule_id
    when FileOperation::Delete
      logger.debug "File deleted: #{info.path}", "main"
      rule_id = @@path_rule_map[info.path]?
      @@scheduler.remove_rule(rule_id) if rule_id
    end

    nil
  end

  private def self.scan_period(file_age)
    file_age = file_age.abs
    time_span = if file_age < 6.hours
                  1.hour
                elsif file_age < 12.hours
                  2.hours
                elsif file_age < 1.day
                  6.hours
                elsif file_age < 1.week
                  1.day
                else
                  1.week
                end

    # Randomise scan period by 10% either side
    max_random_ticks = time_span.ticks.abs * 0.1
    random_ticks = rand((-max_random_ticks)..max_random_ticks)
    Time::Span.new(time_span.ticks + random_ticks)
  end

  private def self.check_dir(dir)
    raise "Directory #{dir} does not exist" unless Dir.exists? dir
    raise "Directory #{dir} is not readable" unless File.readable? dir
    raise "Directory #{dir} is not writable" unless File.writable? dir
  end
end
