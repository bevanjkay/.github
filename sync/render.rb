#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders .github/dependabot.yml for one target repository.
#
#   ruby sync/render.rb <owner> <repo> <output-path>
#
# Shared entries live in sync/defaults.yml. A repository that needs to differ
# gets sync/repos/<owner>/<repo>.yml; anything absent there falls back to the
# defaults, so most repositories need no file at all.

require "erb"
require "yaml"

class RenderError < StandardError; end

ROOT = File.expand_path("..", __dir__)
ZIZMOR_MIN_COOLDOWN_DAYS = 7

def load_yaml(path)
  YAML.safe_load_file(path, aliases: true, permitted_classes: [])
rescue Psych::Exception => e
  raise RenderError, "#{path}: #{e.message}"
end

# A repository-level `schedule` or `cooldown` merges key by key over the
# defaults and applies to every ecosystem, so a repository names only what
# differs. Only keys the template renders are accepted; anything else would be
# silently dropped from the output.
def merge_setting(defaults, overrides, key, allowed, path)
  override = overrides.fetch(key, {})
  unknown = override.keys - allowed
  raise RenderError, "#{path}: unknown #{key} keys: #{unknown.join(", ")}" unless unknown.empty?

  defaults.fetch(key).merge(override)
end

GROUP_NAME = /\A[a-z0-9][a-z0-9-]*\z/

def validate_groups(groups)
  raise RenderError, "groups must map a name to its patterns" unless groups.is_a?(Hash) && !groups.empty?

  groups.each do |name, group|
    raise RenderError, "group name #{name.inspect} must be lowercase letters, digits and hyphens" unless name.to_s.match?(GROUP_NAME)
    raise RenderError, "group #{name} must be a mapping" unless group.is_a?(Hash)

    unknown = group.keys - %w[patterns reason]
    raise RenderError, "group #{name}: unknown keys: #{unknown.join(", ")}" unless unknown.empty?

    patterns = group["patterns"]
    unless patterns.is_a?(Array) && !patterns.empty? && patterns.all? { |p| p.is_a?(String) && !p.empty? }
      raise RenderError, "group #{name} needs a non-empty list of patterns"
    end
  end
  groups
end

# Repository overrides are keyed by ecosystem so a repository names only the
# entry it cares about. `ignore` appends to the shared holds rather than
# replacing them: a repository-specific pin is an extra reason to hold a
# dependency, never a licence to drop a fleet-wide one.
def merge_entry(entry, override, schedule, cooldown)
  merged = entry.dup
  merged["schedule"] = schedule
  merged["cooldown"] = cooldown
  return merged if override.nil?

  unknown = override.keys - %w[ignore directory directories skip grouped groups]
  raise RenderError, "unknown override keys: #{unknown.join(", ")}" unless unknown.empty?

  # Dependabot groups across every listed directory, never per directory, so
  # a repository that wants one pull request per directory opts out of
  # grouping entirely and gets one per dependency instead.
  if override.key?("grouped")
    raise RenderError, "grouped must be true or false" unless [true, false].include?(override["grouped"])

    merged["grouped"] = override["grouped"]
  end

  # Named groups keep dependencies that must move together in one pull request,
  # even when `grouped: false` splits everything else. They render ahead of the
  # catch-all group because Dependabot files a dependency under the first group
  # it matches.
  if override.key?("groups")
    merged["named_groups"] = validate_groups(override["groups"])
    reserved = [entry.fetch("group"), "#{entry.fetch("group")}-security"] & merged["named_groups"].keys.map(&:to_s)
    raise RenderError, "group #{reserved.first} clashes with the shared group" unless reserved.empty?
  end

  if override["directory"] || override["directories"]
    merged.delete("directory")
    merged.delete("directories")
    merged.merge!(override.slice("directory", "directories"))
  end

  merged["ignore"] = entry.fetch("ignore", []) + override.fetch("ignore", [])
  merged
end

def render(owner, repo)
  defaults = load_yaml(File.join(ROOT, "sync", "defaults.yml"))

  overrides_path = File.join(ROOT, "sync", "repos", owner, "#{repo}.yml")
  overrides = File.exist?(overrides_path) ? load_yaml(overrides_path) : {}
  by_ecosystem = overrides.fetch("dependabot", {})

  known = defaults.fetch("ecosystems").map { |e| e.fetch("package-ecosystem") }
  stray = by_ecosystem.keys - known
  raise RenderError, "#{overrides_path}: no such ecosystem: #{stray.join(", ")}" unless stray.empty?

  schedule = merge_setting(defaults, overrides, "schedule", %w[interval time timezone], overrides_path)
  cooldown = merge_setting(defaults, overrides, "cooldown", %w[default-days reason], overrides_path)
  # zizmor's dependabot-cooldown audit fails anything under seven days, so a
  # shorter cooldown is rendered with an inline ignore and must say why.
  if cooldown.fetch("default-days") < ZIZMOR_MIN_COOLDOWN_DAYS && cooldown.fetch("reason", "").to_s.strip.empty?
    raise RenderError, "#{overrides_path}: cooldown under #{ZIZMOR_MIN_COOLDOWN_DAYS} days needs a reason"
  end

  entries = defaults.fetch("ecosystems").filter_map do |entry|
    override = by_ecosystem[entry.fetch("package-ecosystem")]
    next if override&.fetch("skip", false)

    merge_entry(entry, override, schedule, cooldown)
  end
  raise RenderError, "every ecosystem skipped for #{owner}/#{repo}" if entries.empty?

  template = File.read(File.join(ROOT, "sync", "templates", "dependabot.yml.erb"))
  ERB.new(template, trim_mode: "-").result_with_hash(entries: entries)
end

owner, repo, output = ARGV
abort("usage: render.rb <owner> <repo> <output-path>") unless owner && repo && output

begin
  rendered = render(owner, repo)
  # A template typo can still produce valid-looking text, so the output is
  # parsed before it is written. A broken dependabot.yml is silent in the
  # target repository: Dependabot simply stops opening pull requests.
  parsed = YAML.safe_load(rendered, permitted_classes: [])
  raise RenderError, "rendered output is not a dependabot config" unless parsed.is_a?(Hash) && parsed["updates"].is_a?(Array)

  File.write(output, rendered)
rescue RenderError => e
  warn("::error::#{e.message}")
  exit 1
end
