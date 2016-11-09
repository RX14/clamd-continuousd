module Clamd::Continuousd
  class Cloudflare
    @@zone_id_for_site = Hash(Config::Site, String).new

    def clean_cache(site, file_names)
      body = {
        files: file_names.map { |name| site.base_url + name }
      }.to_json

      cloudflare_request("DELETE", "/zones/#{zone_id_for_site(site)}/purge_cache", body: body, config: site.cloudflare) { }
    end

    private def zone_id_for_site(site)
      @@zone_id_for_site.fetch(site) do
        # Doesn't exist, calculate and add to cache
        cloudflare_request("GET", "/zones", config: site.cloudflare) do |parser|
          parser.read_array do
            id = nil
            name = nil
            parser.read_object do |key|
              case key
              when "id"
                id = parser.read_string
              when "name"
                name = parser.read_string
              else
                parser.skip
              end
            end

            if name == site.cloudflare.site_name
              @@zone_id_for_site[site] = id.not_nil!
              break
            end
          end
        end
      end
    end

    private def cloudflare_request(method, endpoint, config : Config::Cloudflare, body = nil)
      body = body.to_json if body && !body.is_a? String

      headers = HTTP::Headers{"X-Auth-Key" => config.api_key, "X-Auth-Email" => config.email}
      HTTP::Client.exec(method, "https://api.cloudflare.com/client/v4" + endpoint, body: body, headers: headers) do |response|
        raise "Cloudflare Ratelimited!" if response.status_code == 429
        raise "Error response code from CloudFlare: #{response.status_code}" if response.status_code != 200

        Continuousd.logger.debug "Response: #{response.inspect}", "cf"

        parser = JSON::PullParser.new(response)
        result_io = MemoryIO.new
        parser.read_object do |key|
          case key
          when "result"
            parser.read_raw(result_io)
          when "success"
            is_succesful = parser.read_bool
            raise "Error from cloudflare"
          when "result_info"
            parser.read_object do |key|
              if key == "total_pages"
                raise "Pagination required" if parser.read_int != 1
              else
                parser.skip
              end
            end
          else
            parser.skip
          end
        end

        yield JSON::PullParser.new(result_io)
      end
    end
  end
end
