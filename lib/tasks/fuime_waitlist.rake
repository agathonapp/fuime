# frozen_string_literal: true

# One-off backfill for waitlist signups that were never stored.
#
# Why this exists: `site/api/waitlist.js` accepts a Resend-only configuration —
# it runs happily with no Upstash at all, emailing each signup and storing
# nothing. That is how fuime-site was actually deployed, so the earliest
# signups exist only as mail in the WAITLIST_NOTIFY_TO inbox. Wiring Upstash
# stores everything from that moment on but does not reach backwards. This
# task reaches backwards.
#
#   rake fuime:waitlist:import[tmp/waitlist-backfill.csv]
#   rake fuime:waitlist:import[tmp/waitlist-backfill.csv,dry]   # print, write nothing
#
# Input: one signup per line, either
#
#   someone@example.com
#   someone@example.com,home-hero,2026-08-01T12:00:00Z
#
# A bare email gets source "imported" and no timestamp, which is honest: the
# roster then shows it as undated rather than inventing a signup time. Blank
# lines, "#" comments and a leading "email,..." header row are skipped.
#
# Idempotent by construction: an address already in the set is left completely
# alone — never re-added, never has its metadata overwritten. Re-running after
# a partial failure is safe, and running it against a live list cannot damage
# a real capture with a reconstructed one.
#
# WRITES, unlike everything else Fuime does with this list. Rails' normal
# credential is meant to be read-only (see render.yaml), so this task looks for
# UPSTASH_REDIS_REST_WRITE_TOKEN first and only falls back to the read token if
# that is unset. Set the write token for the run, then remove it.
namespace :fuime do
  namespace :waitlist do
    desc "Backfill waitlist signups from a CSV/text file into Upstash"
    task :import, [:path, :mode] => :environment do |_t, args|
      path = args[:path].presence or abort "usage: rake fuime:waitlist:import[path/to/file.csv]"
      dry = args[:mode].to_s.downcase.start_with?("dry")

      abort "no such file: #{path}" unless File.exist?(path)

      base = Fuime::WaitlistRoster.base_url
      token = ENV["UPSTASH_REDIS_REST_WRITE_TOKEN"].presence || Fuime::WaitlistRoster.token
      abort "UPSTASH_REDIS_REST_URL is not set" if base.blank?
      abort "no Upstash token (set UPSTASH_REDIS_REST_WRITE_TOKEN)" if token.blank?

      rows = parse_waitlist_file(path)
      abort "nothing to import from #{path}" if rows.empty?

      puts "#{rows.size} row(s) parsed from #{path}"
      puts "target: #{base}#{dry ? '  (DRY RUN — nothing will be written)' : ''}"
      puts

      conn = Faraday.new(url: base) do |f|
        f.headers["Authorization"] = "Bearer #{token}"
        f.headers["Content-Type"] = "application/json"
        f.options.timeout = 10
      end

      existing = fetch_waitlist_members(conn)
      puts "#{existing.size} address(es) already stored"
      puts

      added = 0
      skipped = 0

      rows.each do |row|
        if existing.include?(row[:email])
          skipped += 1
          puts "  skip  #{row[:email]} (already stored)"
          next
        end

        cmds = [["SADD", Fuime::WaitlistRoster::LIST_KEY, row[:email]]]
        meta = { "source" => row[:source] }
        meta["at"] = row[:at] if row[:at].present?
        cmds << ["HSET", "#{Fuime::WaitlistRoster::META_PREFIX}#{row[:email]}", *meta.to_a.flatten]

        if dry
          puts "  would  #{row[:email]}  source=#{row[:source]}  at=#{row[:at] || '—'}"
        else
          res = conn.post("/pipeline", cmds.to_json)
          abort "  FAIL  #{row[:email]}: upstash #{res.status} #{res.body.to_s[0, 200]}" unless res.success?
          puts "  added  #{row[:email]}  source=#{row[:source]}  at=#{row[:at] || '—'}"
        end

        existing << row[:email]
        added += 1
      end

      puts
      puts "#{dry ? 'would add' : 'added'}: #{added}   skipped (already present): #{skipped}"
      puts "roster now: #{fetch_waitlist_members(conn).size} unique address(es)" unless dry
    end

  end
end

def parse_waitlist_file(path)
  email_re = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  File.readlines(path).filter_map do |line|
    line = line.strip
    next if line.blank? || line.start_with?("#")

    email, source, at = line.split(",", 3).map { |v| v.to_s.strip.delete_prefix('"').delete_suffix('"') }
    email = email.to_s.downcase
    next if email == "email" # header row

    unless email.match?(email_re)
      warn "  ignoring unparseable line: #{line[0, 80]}"
      next
    end

    # A reconstructed row says so. Inventing "home-hero" for a signup we only
    # know about because it landed in an inbox would put a guess in the source
    # breakdown and make it wrong.
    { email:, source: source.presence || "imported", at: normalize_waitlist_time(at) }
  end
end

# Stored as the ISO8601 string the site writes, so the admin page parses both
# the same way. An unparseable date is dropped rather than guessed at.
def normalize_waitlist_time(value)
  return nil if value.blank?

  Time.parse(value).utc.iso8601
rescue ArgumentError
  warn "  ignoring unparseable date: #{value}"
  nil
end

def fetch_waitlist_members(conn)
  res = conn.post("/pipeline", [["SMEMBERS", Fuime::WaitlistRoster::LIST_KEY]].to_json)
  abort "could not read the current list: upstash #{res.status}" unless res.success?

  result = JSON.parse(res.body).first["result"]
  Set.new(result.is_a?(Array) ? result : [])
end
