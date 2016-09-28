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
      # TODO: remove temp var after cr#3359 is fixed.
      scans = @@scan_stats.count { |ss| (now - ss[:start_time]) <= 10.seconds }
      scans / 10.0
    end

    # Previous 10s average scan duration
    def self.avg_scan_duration_10s
      now = Time.now
      scans = @@scan_stats.select { |ss| (now - ss[:start_time]) <= 10.seconds }
      # TODO: remove temp var after cr#3359 is fixed.
      total_time = scans.sum { |ss| ss[:duration] }
      total_time.total_seconds / scans.size.to_f64
    end

    # Fraction of time spent scanning last 10s
    def self.executor_utilization_frac_10s
      now = Time.now
      scans = @@scan_stats.select { |ss| (now - ss[:start_time]) <= 10.seconds }

      # TODO: remove temp var after cr#3359 is fixed.
      scan_time = scans.sum { |ss| ss[:duration] }
      scan_time.total_seconds / 10.0
    end

    # Previous 5m average scans
    def self.scans_per_second_5m
      @@scan_stats.size / (5 * 60.0)
    end

    # Previous 5m average scan duration
    def self.avg_scan_duration_5m
      # TODO: remove temp var after cr#3359 is fixed.
      total_time = @@scan_stats.sum { |ss| ss[:duration] }
      total_time.total_seconds / @@scan_stats.size.to_f64
    end

    # Fraction of time spent scanning last 5m
    def self.executor_utilization_frac_5m
      # TODO: remove temp var after cr#3359 is fixed.
      scan_time = @@scan_stats.sum { |ss| ss[:duration] }
      scan_time.total_seconds / (5 * 60.0)
    end

    def self.new_files_per_hour(files : Iterator(FileInfo))
      now = Time.now
      files.select { |info| (now - info.modified) <= 1.hour }.size
    end
  end
end
