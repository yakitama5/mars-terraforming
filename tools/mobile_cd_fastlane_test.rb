require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "fastlane"
require "fastlane/actions/create_keychain"
require "fastlane/actions/import_certificate"
require "fastlane/actions/delete_keychain"
require "fastlane/actions/update_code_signing_settings"
require "xcodeproj"
require "spaceship"
require "cocoapods"
require_relative "../fastlane/testflight_verification"

class MobileCdFastlaneTest < Minitest::Test
  def test_cocoapods_matches_the_committed_ios_lockfile
    lock = File.read(File.expand_path("../ios/Podfile.lock", __dir__))
    assert_equal lock.match(/^COCOAPODS: (.+)$/)[1], Pod::VERSION
  end

  def test_pinned_actions_accept_keychain_options_without_conflicts
    actions = Fastlane::Actions
    FastlaneCore::Configuration.create(actions::CreateKeychainAction.available_options,
                                      path: "/tmp/mars-ci.keychain-db", password: "test-only",
                                      default_keychain: false, add_to_search_list: true,
                                      unlock: true, timeout: 3600)
    FastlaneCore::Configuration.create(actions::ImportCertificateAction.available_options,
                                      certificate_path: "/tmp/test-only.p12", certificate_password: "test-only",
                                      keychain_name: "mars-ci-signing", keychain_path: "/tmp/mars-ci.keychain-db",
                                      keychain_password: "test-only")
    FastlaneCore::Configuration.create(actions::DeleteKeychainAction.available_options,
                                      keychain_path: "/tmp/mars-ci.keychain-db")
  end

  def test_manual_profile_only_changes_runner_release
    source = File.expand_path("../ios/Runner.xcodeproj/project.pbxproj", __dir__)
    Dir.mktmpdir("mars-cd-project") do |directory|
      path = File.join(directory, "Runner.xcodeproj")
      FileUtils.mkdir_p(path)
      FileUtils.cp(source, File.join(path, "project.pbxproj"))
      before = settings_by_target(path)
      Fastlane::Actions::UpdateCodeSigningSettingsAction.run(
        path: path, targets: ["Runner"], build_configurations: ["Release"],
        use_automatic_signing: false, team_id: "TESTTEAM00",
        code_sign_identity: "TEST-DISTRIBUTION", profile_uuid: "TEST-PROFILE-UUID"
      )
      after = settings_by_target(path)
      changed = after.keys.select { |key| before[key] != after[key] }
      assert_equal [["Runner", "Release"]], changed
      assert_equal "TEST-PROFILE-UUID", after.fetch(["Runner", "Release"]).fetch("PROVISIONING_PROFILE")
      assert_equal "Manual", after.fetch(["Runner", "Release"]).fetch("CODE_SIGN_STYLE")
    end
  end

  def test_pilot_group_identifier_matches_id_and_name
    group = Spaceship::ConnectAPI::BetaGroup.new("test-group-id", { "name" => "Internal", "isInternalGroup" => true })
    assert group.matches_identifiers?(["test-group-id"])
    assert group.matches_identifiers?(["Internal"])
    refute group.matches_identifiers?(["other"])
    assert group.is_internal_group
  end

  def test_distributed_build_is_accepted_after_fastlane_ready_state_has_changed
    build = testflight_build
    refute build.ready_for_internal_testing?
    assert MobileTestflight.distributed?(build, [build])
    assert MobileTestflight.distributed?(testflight_build(state: "READY_FOR_BETA_TESTING"), [build])
  end

  def test_only_a_valid_unexpired_build_in_the_requested_group_is_accepted
    build = testflight_build
    other_build = testflight_build(id: "another-build")
    refute MobileTestflight.distributed?(build, [])
    refute MobileTestflight.distributed?(build, [other_build])
    refute MobileTestflight.distributed?(nil, [build])
    refute MobileTestflight.distributed?(testflight_build(detail: false), [build])
    [true, nil].each do |expired|
      refute MobileTestflight.distributed?(testflight_build(expired: expired), [build])
    end
    %w[PROCESSING FAILED INVALID].each do |processing|
      refute MobileTestflight.distributed?(testflight_build(processing: processing), [build])
    end
    %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE IN_EXPORT_COMPLIANCE_REVIEW EXPIRED].each do |state|
      refute MobileTestflight.distributed?(testflight_build(state: state), [build])
    end
  end

  def test_distribution_poll_refreshes_build_and_group_until_both_are_ready
    build = testflight_build
    observations = [[], [testflight_build(state: "READY_FOR_BETA_TESTING")], [build]]
    memberships = [[], [build]]
    requests = []
    sleeps = []
    reports = []
    group = Object.new
    group.define_singleton_method(:fetch_builds) { memberships.shift }
    reader = lambda do |**options|
      requests << options
      observations.shift
    end
    Spaceship::ConnectAPI::Build.stub(:all, reader) do
      assert MobileTestflight.wait_for_distribution(
        app_id: "test-app", build_number: "4.1", group: group,
        attempts: 3, interval: 10, sleeper: sleeps.method(:push), report: reports.method(:push)
      )
    end
    assert_equal 3, requests.length
    assert requests.all? { |options| options == { app_id: "test-app", build_number: "4.1", platform: "IOS" } }
    assert_includes Spaceship::ConnectAPI::Build::ESSENTIAL_INCLUDES.split(","), "buildBetaDetail"
    assert_empty memberships
    assert_equal [10, 10], sleeps
    assert_includes reports.last, "internal=IN_BETA_TESTING"
    assert_includes reports.last, "group_member=true"
  end

  def test_distribution_poll_cannot_succeed_with_a_different_build_or_time_out_as_success
    build = testflight_build
    group = Object.new
    group.define_singleton_method(:fetch_builds) { [build] }
    sleeps = []
    requests = 0
    reader = lambda do |**_options|
      requests += 1
      [testflight_build(version: "another-version")]
    end
    Spaceship::ConnectAPI::Build.stub(:all, reader) do
      refute MobileTestflight.wait_for_distribution(
        app_id: "test-app", build_number: "4.1", group: group,
        attempts: 3, interval: 10, sleeper: sleeps.method(:push)
      )
    end
    assert_equal 3, requests
    assert_equal [10, 10], sleeps
  end

  private

  def testflight_build(id: "test-build", version: "4.1", state: "IN_BETA_TESTING",
                       processing: "VALID", expired: false, detail: true)
    build = Spaceship::ConnectAPI::Build.new(id, {
      "version" => version, "processingState" => processing, "expired" => expired
    })
    if detail
      build.build_beta_detail = Spaceship::ConnectAPI::BuildBetaDetail.new("test-detail", {
        "internalBuildState" => state
      })
    end
    build
  end

  def settings_by_target(path)
    Xcodeproj::Project.open(path).targets.each_with_object({}) do |target, result|
      target.build_configurations.each do |config|
        result[[target.name, config.name]] = config.build_settings.dup
      end
    end
  end
end
