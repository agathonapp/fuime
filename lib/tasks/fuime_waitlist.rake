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
# WRITES, unlike everything else Fuime does with this list — the roster reader
# issues only SCARD/SMEMBERS/HGETALL. Points at the same WAITLIST_REDIS_URL the
# app reads, so run it against the environment whose list you mean to change.
namespace :fuime do
  namespace :waitlist do
    desc "Backfill waitlist signups from a CSV/text file into Upstash"
    task :import, [:path, :mode] => :environment do |_t, args|
      path = args[:path].presence or abort "usage: rake fuime:waitlist:import[path/to/file.csv]"
      dry = args[:mode].to_s.downcase.start_with?("dry")

      abort "no such file: #{path}" unless File.exist?(path)

      url = Fuime::WaitlistRoster.url
      abort "WAITLIST_REDIS_URL (or REDIS_URL) is not set" if url.blank?

      rows = parse_waitlist_file(path)
      abort "nothing to import from #{path}" if rows.empty?

      puts "#{rows.size} row(s) parsed from #{path}"
      # Host only — a Render Key Value URL carries its password inline and this
      # output belongs in a terminal scrollback and probably a screenshot.
      puts "target: #{URI.parse(url).host}#{dry ? '  (DRY RUN — nothing will be written)' : ''}"
      puts

      conn = Redis.new(**Fuime::WaitlistRoster.connection_options(url))

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

        meta = { "source" => row[:source] }
        meta["at"] = row[:at] if row[:at].present?

        if dry
          puts "  would  #{row[:email]}  source=#{row[:source]}  at=#{row[:at] || '—'}"
        else
          begin
            conn.multi do |tx|
              tx.sadd(Fuime::WaitlistRoster::LIST_KEY, row[:email])
              tx.hset("#{Fuime::WaitlistRoster::META_PREFIX}#{row[:email]}", meta)
            end
          rescue Redis::BaseError => e
            abort "  FAIL  #{row[:email]}: #{e.message}"
          end
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
  Set.new(conn.smembers(Fuime::WaitlistRoster::LIST_KEY))
rescue Redis::BaseError, SocketError => e
  abort "could not read the current list: #{e.message}"
end
