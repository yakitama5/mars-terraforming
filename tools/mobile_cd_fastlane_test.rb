require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "fastlane"
require "fastlane/actions/create_keychain"
require "fastlane/actions/import_certificate"
require "fastlane/actions/delete_keychain"
require "fastlane/actions/update_code_signing_settings"
require "xcodeproj"
require "spaceship"

class MobileCdFastlaneTest < Minitest::Test
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

  private

  def settings_by_target(path)
    Xcodeproj::Project.open(path).targets.each_with_object({}) do |target, result|
      target.build_configurations.each do |config|
        result[[target.name, config.name]] = config.build_settings.dup
      end
    end
  end
end
