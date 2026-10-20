module MobileTestflight
  INTERNAL_TESTING_STATES = %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].freeze

  def self.distributed?(build, group_builds)
    build && build.processing_state == "VALID" && build.expired == false &&
      INTERNAL_TESTING_STATES.include?(build.build_beta_detail&.internal_build_state) &&
      group_builds.any? { |item| item.id == build.id }
  end

  def self.wait_for_distribution(app_id:, build_number:, group:, attempts: 12, interval: 10,
                                 sleeper: Kernel.method(:sleep), report: nil)
    attempts.times do |index|
      # Both calls read fresh API data, including every page of group membership.
      build = Spaceship::ConnectAPI::Build.all(
        app_id: app_id, build_number: build_number, platform: "IOS"
      ).find { |item| item.version == build_number }
      group_builds = build ? group.fetch_builds : []
      if report
        report.call("TestFlight 確認 #{index + 1}/#{attempts}: " \
                    "processing=#{build&.processing_state || 'missing'}, " \
                    "internal=#{build&.build_beta_detail&.internal_build_state || 'missing'}, " \
                    "expired=#{build&.expired.inspect}, " \
                    "group_member=#{build ? group_builds.any? { |item| item.id == build.id } : false}")
      end
      return true if distributed?(build, group_builds)

      sleeper.call(interval) if index + 1 < attempts
    end
    false
  end
end
