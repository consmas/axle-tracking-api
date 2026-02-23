module CmsV6
  module ActionCatalog
    ALL_ACTIONS = [
      "addDevice",
      "addDownloadTask",
      "addMediaInformation",
      "addVehicle",
      "alarmEvidence",
      "callDetail",
      "capturePicture",
      "catalogDetailApi",
      "catalogSummaryApi",
      "controllDownLoad",
      "dataDownlinkTransparent",
      "delDevRule",
      "delDownloadTasklist",
      "delGroupMember",
      "delMediaInformation",
      "delRule",
      "delUserSession",
      "deleteCompany",
      "deleteDevice",
      "deleteGroup",
      "deleteSIMInfo",
      "deleteUserAccount",
      "deleteUserRole",
      "deleteVehicle",
      "devRulePermit",
      "downloadTasklist",
      "editDevice",
      "editRule",
      "findCompany",
      "findDriverInfoByDeviceId",
      "findSIMInfo",
      "findUserAccount",
      "findUserRole",
      "findVehicleInfoByDeviceId",
      "findVehicleInfoByDeviceJn",
      "ftpUpload",
      "getDeviceByVehicle",
      "getDeviceOlStatus",
      "getDeviceStatus",
      "getFlowInfo",
      "getLoadDeviceInfo",
      "getOilTrackDetail",
      "getUserMarkers",
      "getVideoFileInfo",
      "getVideoHistoryFile",
      "installVehicle",
      "loadDevRuleByRuleId",
      "loadRules",
      "loadSIMInfos",
      "login",
      "loginEx",
      "logout",
      "marginGroup",
      "mergeCompany",
      "mergeRule",
      "mergeSIMInfo",
      "mergeUserAccount",
      "mergeUserRole",
      "parkDetail",
      "performanceReportPhotoListSafe",
      "queryAccessAreaInfo",
      "queryAlarmDetail",
      "queryAudioOrVideo",
      "queryDownLoadReplayEx",
      "queryDriverList",
      "queryFtpStatus",
      "queryIdentifyAlarm",
      "queryPhoto",
      "queryPunchCardRecode",
      "queryRuleList",
      "queryTrackDetail",
      "queryUserVehicle",
      "realTimeVedio",
      "runMileage",
      "savaUser",
      "saveFlowConfig",
      "saveUserSessionEx",
      "sendPTZControl",
      "unbindingSIM",
      "uninstallDevice",
      "updVehicle",
      "userMediaRateOfFlow",
      "vehicleAlarm",
      "vehicleControlGPSReport",
      "vehicleControlOthers",
      "vehicleStatus",
      "vehicleTTS",
      "zipAlarmEvidence"
    ].freeze

    WRITE_ACTION_PREFIXES = %w[
      add del delete edit merge save install uninstall unbinding send vehicleControl
    ].freeze

    WRITE_ACTION_NAMES = %w[
      addDownloadTask
      addMediaInformation
      capturePicture
      controllDownLoad
      dataDownlinkTransparent
      devRulePermit
      ftpUpload
      marginGroup
      realTimeVedio
      savaUser
      vehicleTTS
      zipAlarmEvidence
    ].freeze

    module_function

    def include?(action_name)
      ALL_ACTIONS.include?(action_name.to_s)
    end

    def admin_required?(action_name)
      action = action_name.to_s
      return true if WRITE_ACTION_NAMES.include?(action)

      WRITE_ACTION_PREFIXES.any? { |prefix| action.start_with?(prefix) }
    end

    def endpoint(action_name)
      "StandardApiAction_#{action_name}.action"
    end

    def summary
      ALL_ACTIONS.map do |name|
        {
          name: name,
          endpoint: endpoint(name),
          methods: [ "GET", "POST" ],
          admin_required: admin_required?(name)
        }
      end
    end
  end
end
