module Api
  module V1
    class VehiclesController < BaseController
      require "time"
      require "uri"

      def index
        payload = fetch_vehicles_payload
        vehicles = extract_vehicle_rows(payload)
        normalized = vehicles.map { |vehicle| normalize_vehicle(vehicle) }.uniq { |row| row[:id] || row[:name] }
        normalized = enrich_live_online_states(normalized)

        response = {
          vehicles: normalized
        }
        response[:debug] = vehicle_debug(payload, vehicles) if params[:debug].to_s == "1"

        render json: response
      end

      def status
        payload = fetch_status_payload(params[:id])
        status = extract_status_row(payload)

        render json: {
          vehicle_status: normalize_status(params[:id], status)
        }
      end

      def track
        validate_range!
        return if performed?

        payload = cms_client.get("StandardApiAction_queryTrackDetail.action",
                                 params: {
                                   devIdno: params[:id],
                                   begintime: params[:from],
                                   endtime: params[:to],
                                   parkTime: 0,
                                   distance: 0,
                                   currentPage: 1,
                                   pageRecords: 500,
                                   toMap: map_type
                                 })
        points = Array(payload["infos"] || payload["tracks"] || payload["list"] || payload["data"])

        render json: {
          vehicle_id: params[:id],
          from: params[:from],
          to: params[:to],
          points: points.map { |point| normalize_track_point(point) }
        }
      end

      def live_stream
        expires_now
        payload = fetch_live_stream_payload(params[:id], channel: params[:channel], stream: params[:stream])
        urls = extract_urls(payload).map { |url| normalize_stream_url(url) }.uniq
        fallback = fallback_live_stream_url(params[:id], channel: params[:channel], stream: params[:stream])
        urls.unshift(fallback) if fallback.present?
        urls = urls.compact.uniq
        stream_url = urls.first

        response = {
          vehicle_id: params[:id],
          channel: params[:channel].presence || "0",
          stream: params[:stream].presence || "1",
          stream_url: proxied_stream_url(stream_url),
          raw_stream_url: stream_url,
          protocol: stream_protocol(stream_url),
          urls: urls
        }
        response[:debug] = live_stream_debug(payload, fallback, urls) if params[:debug].to_s == "1"

        render json: response
      end

      def map_feed
        expires_now
        payload = fetch_vehicles_payload
        vehicles = extract_vehicle_rows(payload)
        normalized = vehicles.map { |vehicle| normalize_vehicle(vehicle) }.uniq { |row| row[:id] || row[:name] }
        channel = params[:channel].presence || "0"
        stream = params[:stream].presence || "1"

        threads = normalized.map { |vehicle| Thread.new { build_map_feed_item(vehicle, channel:, stream:) } }
        feed = threads.map(&:value)

        render json: {
          fetched_at: Time.now.utc.iso8601,
          vehicles: feed
        }
      end

      def playback_files
        validate_range!
        return if performed?

        payload = fetch_playback_payload(params[:id], from: params[:from], to: params[:to], channel: params[:channel])
        files = extract_video_files(payload).map { |row| normalize_playback_file(row) }

        render json: {
          vehicle_id: params[:id],
          from: params[:from],
          to: params[:to],
          files: files
        }
      end

      private

      def validate_range!
        return if params[:from].present? && params[:to].present?

        render_error(code: "invalid_range", message: "Both from and to are required", status: :unprocessable_entity)
      end

      def fetch_vehicles_payload
        attempts = [
          -> { cms_client.post("StandardApiAction_queryUserVehicle.action", body: { language: "en" }) },
          -> { cms_client.get("StandardApiAction_queryUserVehicle.action", params: { language: "en" }) },
          -> { cms_client.get("StandardLoginAction_getUserVehicleExForIndex.action", params: legacy_vehicle_params) }
        ]

        last_error = nil
        attempts.each do |attempt|
          return attempt.call
        rescue CmsV6::Client::UnauthorizedError, CmsV6::Client::PermissionDeniedError => error
          last_error = error
        end

        raise(last_error || CmsV6::Client::UnauthorizedError.new("CMSV6 session expired"))
      end

      def legacy_vehicle_params
        {
          newv: 1,
          toMap: map_type,
          vType: ENV.fetch("CMSV6_VTYPE", "v6"),
          refresh: 1
        }
      end

      def normalize_vehicle(row)
        first_device = first_device_row(row)
        device_id = first_present(first_device&.dig("id"), first_device&.dig("devIdno"), first_device&.dig("devIDNO"), first_device&.dig("did"))
        vehicle_code = first_present(row["vehiIdno"], row["vehiIDNO"], row["vehi"], row["idno"])
        id = first_present(
          device_id,
          row["devIdno"], row["devIDNO"],
          vehicle_code,
          row["vehicleId"], row["vid"], row["id"]
        )
        name = first_present(
          row["name"], row["vehiName"], row["label"], row["nm"], row["idno"],
          row["vehi"], row["vehiIdno"], row["vehiIDNO"], row["plateNo"], row["plate"], row["vehiNum"]
        )
        plate = first_present(
          row["plate"], row["plateNo"], row["vehiNum"], row["plateNum"], row["vehicleNo"],
          row["nm"], row["vehiIdno"], row["vehiIDNO"], row["vehi"]
        )

        {
          id: id,
          name: name,
          plate_number: plate,
          online: truthy_online?(
            row["online"],
            row["onlineStatus"],
            row["ol"],
            row["isOnline"],
            row["status"]
          )
        }
      end

      def normalize_status(vehicle_id, row)
        online = truthy_online?(
          row["online"],
          row["onlineStatus"],
          row["ol"],
          row["isOnline"],
          row["status"],
          row["deviceStatus"]
        )

        # This CMS sends ol:1 only for online devices; offline devices omit ol entirely.
        # Do not fall back to position presence — stale coordinates exist for offline vehicles.
        {
          vehicle_id: row["vehiIdno"] || row["vehiIDNO"] || row["vid"] || vehicle_id,
          latitude: row["lat"] || row["latitude"] || row["weiDu"],
          longitude: row["lng"] || row["longitude"] || row["lon"] || row["jingDu"],
          speed_kmh: row["speed"] || row["gpsSpeed"] || row["velocity"],
          online: online,
          updated_at: row["time"] || row["gpsTime"] || row["timestamp"] || row["gt"] || row["rt"]
        }
      end

      def normalize_track_point(row)
        {
          latitude: row["lat"] || row["latitude"],
          longitude: row["lng"] || row["longitude"] || row["lon"],
          speed_kmh: row["speed"] || row["gpsSpeed"] || row["velocity"],
          recorded_at: row["time"] || row["gpsTime"] || row["timestamp"]
        }
      end

      def map_type
        ENV.fetch("CMSV6_MAP_TYPE", "2")
      end

      def extract_vehicle_rows(payload)
        rows = []
        collect_vehicle_rows(payload, rows)

        roots = [
          payload["vehicles"], payload["infos"], payload["list"], payload["data"], payload["vehicleList"], payload["vehiList"]
        ].compact
        roots.each { |root| collect_vehicle_rows(root, rows) }
        rows
      end

      def collect_vehicle_rows(node, rows)
        case node
        when Array
          node.each { |item| collect_vehicle_rows(item, rows) }
        when Hash
          rows << node if vehicle_like?(node)
          nested_keys = %w[vehicles infos list data vehicleList vehiList children childs childNodes subList rows]
          nested_keys.each do |key|
            next unless node[key].present?

            collect_vehicle_rows(node[key], rows)
          end
        end
      end

      def vehicle_like?(row)
        has_identity = %w[
          vehiIdno vehiIDNO vehi vid vehiName plate plateNo vehiNum devIdno devIDNO idno
          id name nm label vehicleId did vm dl
        ].any? { |key| row[key].present? }
        return false unless has_identity

        # Filter pure group nodes (e.g., "ConsMas") while keeping vehicle rows.
        has_device_or_vehicle_markers = row["dl"].present? ||
          row["did"].present? ||
          row["devIdno"].present? ||
          row["devIDNO"].present? ||
          row["vm"].present? ||
          row["vehiIdno"].present? ||
          row["vehiIDNO"].present? ||
          row["vehiNum"].present? ||
          row["plateNo"].present? ||
          row["plate"].present?

        has_device_or_vehicle_markers
      end

      def first_present(*values)
        values.find(&:present?)
      end

      def truthy_online?(*values)
        values.any? do |value|
          case value
          when true then true
          when Numeric then value.to_i.positive?
          when String
            normalized = value.strip.downcase
            %w[1 online true yes y].include?(normalized)
          else
            false
          end
        end
      end

      def first_device_row(row)
        Array(row["dl"]).find { |entry| entry.is_a?(Hash) } ||
          Array(row["devices"]).find { |entry| entry.is_a?(Hash) }
      end

      def fetch_status_payload(id)
        attempts = [
          -> { cms_client.get("StandardApiAction_getDeviceStatus.action", params: { devIdno: id, toMap: map_type, language: "en" }) },
          -> { cms_client.get("StandardApiAction_getDeviceStatus.action", params: { vehiIdno: id, toMap: map_type, language: "en" }) },
          -> { cms_client.post("StandardPositionAction_statusEx.action", body: { devIdnos: id, toMap: map_type, newv: 1 }) }
        ]

        last_error = nil
        attempts.each do |attempt|
          return attempt.call
        rescue CmsV6::Client::UnauthorizedError, CmsV6::Client::PermissionDeniedError => error
          last_error = error
        end

        raise(last_error || CmsV6::Client::UnauthorizedError.new("CMSV6 session expired"))
      end

      def fetch_live_stream_payload(id, channel:, stream:)
        chn = channel.presence || "0"
        strm = stream.presence || "1"

        attempts = [
          -> { cms_client.get("StandardApiAction_realTimeVedio.action", params: { DevIDNO: id, Chn: chn, Stream: strm }) },
          -> { cms_client.get("StandardApiAction_realTimeVedio.action", params: { devIdno: id, channel: chn, stream: strm }) },
          -> { cms_client.get("StandardApiAction_getVideoFileInfo.action", params: base_video_file_params(id:, channel: chn)) }
        ]

        last_error = nil
        attempts.each do |attempt|
          return attempt.call
        rescue CmsV6::Client::UnauthorizedError, CmsV6::Client::PermissionDeniedError => error
          last_error = error
        end

        raise(last_error || CmsV6::Client::UnauthorizedError.new("CMSV6 session expired"))
      end

      def fetch_playback_payload(id, from:, to:, channel:)
        from_time = parse_time!(from)
        to_time = parse_time!(to)
        chn = channel.presence || "0"

        cms_client.get(
          "StandardApiAction_getVideoHistoryFile.action",
          params: base_video_file_params(id:, channel: chn).merge(
            YEARE: to_time.year,
            MONE: to_time.month,
            DAYE: to_time.day
          )
        )
      rescue ArgumentError
        render_error(code: "invalid_range", message: "Invalid datetime format", status: :unprocessable_entity)
        {}
      end

      def extract_status_row(payload)
        candidates = [
          payload["status"], payload["infos"], payload["list"], payload["data"], payload["vehicleStatus"]
        ].compact
        row = candidates.find { |entry| entry.is_a?(Array) && entry.first.present? }
        return row.first if row
        return candidates.find { |entry| entry.is_a?(Hash) } if candidates.any? { |entry| entry.is_a?(Hash) }

        payload
      end

      def extract_urls(node, urls = [])
        case node
        when Hash
          node.each_value { |value| extract_urls(value, urls) }
        when Array
          node.each { |value| extract_urls(value, urls) }
        when String
          candidate = node.strip
          if candidate.match?(/\Ahttps?:\/\//i) || candidate.match?(/\Aws:\/\//i)
            urls << candidate
          end
        end
        urls
      end

      def normalize_stream_url(url)
        return url if url.blank?

        token = cms_client.current_session_token.to_s
        return url if token.blank?

        if url.include?("jsession=") && url.match?(/jsession=(?:&|$)/)
          return url.sub("jsession=", "jsession=#{token}")
        end
        if url.include?("JSESSIONID=") && url.match?(/JSESSIONID=(?:&|$)/)
          return url.sub("JSESSIONID=", "JSESSIONID=#{token}")
        end

        url
      end

      def fallback_live_stream_url(vehicle_id, channel:, stream:)
        token = cms_client.current_session_token.to_s
        return nil if token.blank?

        chn = channel.presence || "0"
        strm = stream.presence || "1"
        "#{stream_base_url}/hls/1_#{vehicle_id}_#{chn}_#{strm}.m3u8?jsession=#{token}"
      end

      def stream_base_url
        explicit = ENV["CMSV6_STREAM_BASE_URL"].to_s.strip
        return explicit.chomp("/") if explicit.present?

        cms_uri = URI.parse(ENV.fetch("CMSV6_BASE_URL"))
        "#{cms_uri.scheme}://#{cms_uri.host}:6604"
      rescue URI::InvalidURIError, KeyError
        ""
      end

      def stream_protocol(url)
        return nil if url.blank?
        return "hls" if url.include?(".m3u8")
        return "ws" if url.start_with?("ws://", "wss://")

        "http"
      end

      def live_stream_debug(payload, fallback, urls)
        {
          payload_keys: payload.is_a?(Hash) ? payload.keys.take(20) : [],
          fallback_url: fallback,
          urls_found: urls.size
        }
      end

      def extract_video_files(payload)
        candidates = [ payload["infos"], payload["list"], payload["data"], payload["files"], payload["records"] ].compact
        array = candidates.find { |entry| entry.is_a?(Array) }
        return array if array
        return [ payload ] if payload.is_a?(Hash)

        []
      end

      def normalize_playback_file(row)
        urls = extract_urls(row).map { |url| normalize_stream_url(url) }.uniq
        {
          name: first_present(row["name"], row["fileName"], row["playFile"], row["fph"]),
          start_time: first_present(row["startTime"], row["sbtm"], row["fbtm"], row["time"]),
          end_time: first_present(row["endTime"], row["setm"], row["fetm"]),
          length: first_present(row["len"], row["length"], row["FLENGTH"]),
          playback_url: urls.find { |url| url.downcase.include?("downtype=5") } || urls.first,
          download_url: urls.find { |url| url.downcase.include?("downtype=3") },
          raw: row
        }
      end

      def build_map_feed_item(vehicle, channel:, stream:)
        id = vehicle[:id]
        return vehicle.merge(status: nil, live_stream: nil) if id.blank?

        status_payload = fetch_status_payload(id)
        status_row = extract_status_row(status_payload)
        normalized_status = normalize_status(id, status_row)

        stream_payload = fetch_live_stream_payload(id, channel:, stream:)
        urls = extract_urls(stream_payload).map { |url| normalize_stream_url(url) }.uniq
        stream_url = urls.first

        vehicle.merge(
          online: normalized_status[:online],
          status: normalized_status,
          live_stream: {
            stream_url: proxied_stream_url(stream_url),
            raw_stream_url: stream_url,
            protocol: stream_protocol(stream_url),
            channel: channel,
            stream: stream,
            urls: urls
          }
        )
      rescue CmsV6::Client::Error
        vehicle.merge(status: nil, live_stream: nil)
      end

      def base_video_file_params(id:, channel:)
        now = Time.now.utc
        {
          DevIDNO: id,
          LOC: 2,
          CHN: channel,
          YEAR: now.year,
          MON: now.month,
          DAY: now.day,
          RECTYPE: -1,
          FILEATTR: 2,
          BEG: 0,
          END: 86_399,
          ARM1: 0,
          ARM2: 0,
          RES: 0,
          STREAM: 0,
          STORE: 0
        }
      end

      def proxied_stream_url(raw_url)
        return nil if raw_url.blank?

        api_v1_stream_proxy_url(url: raw_url, st: StreamProxyToken.issue(url: raw_url))
      rescue StandardError
        raw_url
      end

      def parse_time!(value)
        Time.parse(value.to_s)
      end

      def enrich_live_online_states(vehicles)
        threads = vehicles.map do |vehicle|
          Thread.new do
            id = vehicle[:id]
            next vehicle if id.blank?

            payload = fetch_status_payload(id)
            row = extract_status_row(payload)
            live_status = normalize_status(id, row)
            vehicle.merge(online: live_status[:online])
          rescue CmsV6::Client::Error
            vehicle
          end
        end
        threads.map(&:value)
      end

      def vehicle_debug(payload, rows)
        {
          top_level_keys: payload.is_a?(Hash) ? payload.keys.take(20) : [],
          extracted_row_count: rows.size,
          sample_row_keys: rows.first.is_a?(Hash) ? rows.first.keys.take(20) : [],
          sample_row: rows.first
        }
      end

    end
  end
end
