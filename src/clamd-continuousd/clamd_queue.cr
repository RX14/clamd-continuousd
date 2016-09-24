require "clamd"

module Clamd::Continuousd
  class ClamdQueue
    @queue : Channel(String)
    @workers : Int32
    @connection_info : {String, Int32} | String

    def initialize(host, port, @workers = 2)
      @connection_info = {host, port.to_i}
      @queue = Channel(String).new(20)
    end

    def scan(path)
      @queue.send(path)
    end

    def spawn_workers
      @workers.times { spawn { worker } }
    end

    private def worker
      connection_info = @connection_info
      if connection_info.is_a? {String, Int32}
        connection = Clamd::Connection.connect_tcp(*connection_info)
      else
        connection = Clamd::Connection.connect_unix(connection_info)
      end

      loop do
        begin
          path = @queue.receive

          next unless File.exists? path
          File.open(path) do |file|
            result = connection.scan_stream(file)

            handle_found(path, result.signature) if result.status == Status::Virus
          end
        rescue ex
          ex.inspect_with_backtrace(STDERR)
        end
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
