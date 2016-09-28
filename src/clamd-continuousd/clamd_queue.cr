require "clamd"

module Clamd::Continuousd
  class ClamdQueue
    @queue : Channel(String)
    @workers : Int32
    @connection_info : {String, Int32} | String

    def initialize(host, port, @workers = 2)
      @connection_info = {host, port.to_i}
      @queue = Channel(String).new(20)

      begin
        connection = get_connection
        raise "Cannot connect to clamd using #{@connection_info}" unless connection.ping == "PONG"
      ensure
        connection.try &.close
      end
    end

    def scan(path)
      Continuousd.logger.debug "Queueing #{path} for scanning", "clamd"
      @queue.send(path)
    end

    def spawn_workers
      @workers.times { spawn { worker } }
    end

    private def worker
      Continuousd.logger.info "Connecting to clamd!", "clamd"
      connection = get_connection

      loop do
        begin
          path = @queue.receive

          next unless File.exists? path
          File.open(path) do |file|
            Continuousd.logger.debug "Scanning #{path}", "clamd"

            try = 1
            while try <= 3
              begin
                time_start = Time.now
                result = connection.scan_stream(file)
                time_finish = Time.now
              rescue ex
                STDERR.puts "Exception thrown while scanning (try #{try}):"
                ex.inspect_with_backtrace(STDERR)

                sleep 4**try if try < 3
              end
              try += 1
            end

            Stats.submit_clamd_scan(time_start, time_finish - time_start)
            Continuousd.logger.debug "Scanned #{path} in #{time_finish - time_start}", "clamd"

            handle_found(path, result.signature) if result.status == Status::Virus
          end
        end
      end
    ensure
      connection.try &.close
    end

    private def get_connection
      connection_info = @connection_info
      if connection_info.is_a? {String, Int32}
        Clamd::Connection.connect_tcp(*connection_info)
      else
        Clamd::Connection.connect_unix(connection_info)
      end
    end

    private def handle_found(path, signature)
      puts "Found:"
      puts "       Path: #{path}"
      puts "  Signature: #{signature}"

      File.delete(path)
      # TODO: clean cloudflare cache
    end
  end
end
