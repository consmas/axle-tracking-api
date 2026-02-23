module Api
  module V1
    class AlarmsController < BaseController
      before_action :require_admin!

      def index
        validate_range!
        return if performed?

        payload = cms_client.get("StandardApiAction_queryAlarmDetail.action",
                                 params: {
                                   devIdno: params[:dev_idno],
                                   begintime: params[:from],
                                   endtime: params[:to],
                                   armType: params[:arm_type],
                                   handle: params[:handle],
                                   currentPage: 1,
                                   pageRecords: 200,
                                   toMap: ENV.fetch("CMSV6_MAP_TYPE", "2")
                                 })
        alarms = Array(payload["infos"] || payload["alarms"] || payload["list"] || payload["data"])

        render json: {
          from: params[:from],
          to: params[:to],
          alarms: alarms.map { |alarm| normalize_alarm(alarm) }
        }
      end

      private

      def validate_range!
        return if params[:from].present? && params[:to].present?

        render_error(code: "invalid_range", message: "Both from and to are required", status: :unprocessable_entity)
      end

      def normalize_alarm(row)
        {
          id: row["guid"] || row["id"] || row["alarmId"],
          vehicle_id: row["vehiIdno"] || row["devIdno"] || row["vehicleId"],
          type: row["strType"] || row["type"] || row["armType"] || row["alarmType"],
          message: row["message"] || row["desc"] || row["alarmInfo"],
          occurred_at: row["startTime"] || row["time"] || row["gpsTime"] || row["timestamp"],
          latitude: row["lat"] || row["latitude"],
          longitude: row["lng"] || row["longitude"] || row["lon"],
          severity: row["severity"] || row["level"]
        }
      end
    end
  end
end
