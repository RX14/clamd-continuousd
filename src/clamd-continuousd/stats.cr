module Clamd::Continuousd
  class Stats
    alias ScanStats = {start_time: Time, duration: Time::Span}

    @@scan_stats = Array(ScanStats).new

    def self.submit_clamd_scan(start_time, duration)
      now = Time.now
      @@scan_stats << {start_time: start_time, duration: duration}
      @@scan_stats.select! { |ss| (now - ss[:start_time]) <= 5.minutes }
    end

    # Previous 10s average scans
    def self.scans_per_second_10s
      now = Time.now
      @@scan_stats.count { |ss| (now - ss[:start_time]) <= 10.seconds } / 10.0
    end

    # Previous 10s average scan duration
    def self.avg_scan_duration_10s
      now = Time.now
      scans = @@scan_stats.each.select { |ss| (now - ss[:start_time]) <= 10.seconds }

      scans.sum { |ss| ss[:duration] }.total_seconds / scans.size.to_f64
    end

    # Fraction of time spent scanning last 10s
    def self.executor_utilization_frac_10s
      now = Time.now
      scans = @@scan_stats.each.select { |ss| (now - ss[:start_time]) <= 10.seconds }

      scans.sum { |ss| ss[:duration] }.total_seconds / 10.0
    end

    # Previous 5m average scans
    def self.scans_per_second_5m
      @@scan_stats.size / (5 * 60.0)
    end

    # Previous 5m average scan duration
    def self.avg_scan_duration_5m
      @@scan_stats.sum { |ss| ss[:duration] }.total_seconds / @@scan_stats.size.to_f64
    end

    # Fraction of time spent scanning last 5m
    def self.executor_utilization_frac_5m
      @@scan_stats.sum { |ss| ss[:duration] }.total_seconds / (5 * 60.0)
    end

    def self.new_files_per_hour(files : Iterator(FileInfo))
      now = Time.now
      files.select { |info| (now - info.modified) <= 1.hour }.size
    end
  end
end
