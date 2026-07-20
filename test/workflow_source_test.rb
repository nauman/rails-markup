# frozen_string_literal: true

require_relative "test_helper"

class WorkflowSourceTest < Minitest::Test
  CI_WORKFLOW = File.expand_path("../.github/workflows/ci.yml", __dir__)

  def test_system_job_installs_pinned_javascript_dependencies_before_browser_tests
    match = File.read(CI_WORKFLOW).match(/^  system:\s*$\n(?<body>.*)\z/m)

    refute_nil match, "ci.yml must define the system job"
    system_job = match[:body]
    node_setup = system_job.index("uses: actions/setup-node@v4")
    npm_install = system_job.index("run: npm ci")
    system_tests = system_job.index("run: bundle exec rake test:system")

    refute_nil node_setup, "system job must set up Node"
    assert_match(/node-version:\s*["']?22["']?/, system_job)
    assert_match(/cache:\s*npm/, system_job)
    refute_nil npm_install, "system job must install package-lock dependencies"
    refute_nil system_tests, "system job must run the browser tests"
    assert_operator node_setup, :<, npm_install
    assert_operator npm_install, :<, system_tests
  end
end
