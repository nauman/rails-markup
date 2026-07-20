# frozen_string_literal: true

require_relative "test_helper"

class ReleaseDocumentationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_readme_documents_authenticated_csrf_protected_browser_synchronization
    readme = File.read(File.join(ROOT, "README.md"))

    assert_match(/same host authentication.*dashboard/i, readme)
    assert_match(/CSRF/i, readme)
    assert_match(/Rails.*authoritative/i, readme)
    assert_match(/browser-owned/i, readme)
    assert_match(/server-owned/i, readme)
  end

  def test_readme_documents_the_five_canonical_thin_enum_tools_and_compatibility_deadline
    readme = File.read(File.join(ROOT, "README.md"))

    %w[read watch transition reply dismiss].each do |name|
      assert_match(/`rails_markup_#{name}`/, readme)
    end
    assert_match(/removed after 1\.3\.0/i, readme)
    assert_match(/caller-supplied.*URL.*token/i, readme)
  end

  def test_readme_documents_staged_uuid_repair_and_verification
    readme = File.read(File.join(ROOT, "README.md"))

    assert_match(/rolling UUID upgrade/i, readme)
    assert_match(/client_uuids:repair/, readme)
    assert_match(/client_uuids:verify/, readme)
    assert_match(/old.*instances.*drained/i, readme)
  end
end
