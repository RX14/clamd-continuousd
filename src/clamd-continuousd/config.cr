require "json"

module Clamd::Continuousd
  module Config
    def self.load(path) : Root
      File.open(path, "r") do |file|
        Root.from_json(file)
      end
    end

    struct Root
      JSON.mapping(
        clamd: Clamd,
        sites: Array(Site),
        debug: Bool
      )
    end

    struct Clamd
      JSON.mapping(
        host: String,
        port: String
      )
    end

    struct Site
      JSON.mapping(
        dir: String,
        base_url: String,
        cloudflare: Cloudflare
      )
    end

    struct Cloudflare
      JSON.mapping(
        email: String,
        api_key: String,
        site_name: String
      )
    end
  end

  CONFIG = Config.load(ARGV[0]? || raise "No config file specified")
end
