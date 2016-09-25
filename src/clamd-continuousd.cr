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
  @@clamd = ClamdQueue.new(ENV["CLAMD_HOST"], ENV["CLAMD_PORT"])

  def self.logger
    @@logger ||= begin
                   l = Logger.new(STDOUT)
                   l.level = ENV["DEBUG"]? ? Logger::DEBUG : Logger::INFO
                   l.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
                     io << "[" << datetime << "]" << severity.rjust(5) << " " << progname << ": " << message
                   end
                   l
                 end
  end

  def self.start
    dirs = ARGV
    logger.info "Starting up (dirs: #{dirs})", "main"
    dirs.each { |d| check_dir(d) }

    spawn { @@scheduler.process_rules }
    @@clamd.spawn_workers

    files = FileCache.new(dirs, ->handle_dir_change(FileOperation, FileInfo))
    spawn { files.start_watching }
    spawn do
      # Add all files, delayed
      dirs.each do |dir|
        entries = Dir.entries(dir)
        entries.shuffle!
        entries.each do |file|
          file_info = File.stat(File.join(dir, file))
          next unless file_info.file?

          scan_period = scan_period(file_info.mtime - Time.now)
          next_scan = Time::Span.new(rand(scan_period.ticks)).from_now

          @@scheduler.add_rule(->{ files.update_file(file, file_info.mtime) }, next_scan)
        end
      end

      # Keep dir up to date
      loop do
        sleep 1.hour
        files.update_directory
      end
    end

    server = HTTP::Server.new(8080) do |ctx|
      ctx.response.content_type = "application/json"
      {clamd_queue_size: @@clamd.@queue.queue_size}.to_json(ctx.response)
    end
    spawn { server.listen }

    sleep
  end

  private def self.handle_dir_change(op, info)
    case op
    when FileOperation::Update
      logger.info "File updated: #{info.path}", "main"
      if rule_id = @@path_rule_map[info.path]?
        @@scheduler.remove_rule(rule_id)
      end

      rule_id = @@scheduler.add_rule(->{
        @@clamd.scan(info.path)

        file_age = info.modified - Time.now
        scan_period(file_age).from_now
      }, Time.now)

      @@path_rule_map[info.path] = rule_id
    when FileOperation::Delete
      logger.info "File deleted: #{info.path}", "main"
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
    max_random_ticks = time_span.ticks.abs * 0.1_f64
    random_ticks = rand((-max_random_ticks)..max_random_ticks)
    Time::Span.new(time_span.ticks + random_ticks)
  end

  private def self.check_dir(dir)
    raise "Directory #{dir} does not exist" unless Dir.exists? dir
    raise "Directory #{dir} is not readable" unless File.readable? dir
    raise "Directory #{dir} is not writable" unless File.writable? dir
  end
end
