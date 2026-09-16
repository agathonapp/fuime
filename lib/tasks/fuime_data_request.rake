# frozen_string_literal: true

# Fuime: carry out a parent's COPPA deletion request.
#
# A rake task rather than an admin button, deliberately: the work is
# irreversible, it cannot be undone by a restore without restoring everybody
# else's data with it, and the person running it should have read the request
# first. See Fuime::DataErasureService.
namespace :fuime do
  namespace :data_request do
    desc "Show what a deletion request would do, without doing it. ID=<id>"
    task :preview, [:id] => :environment do |_t, args|
      request = fetch_request(args)
      service = Fuime::DataErasureService.new(request:, performed_by: nil)

      puts "Request ##{request.id} — #{request.kind}, #{request.status}"
      puts "  About:     #{request.subject.name || request.subject.email} (user #{request.subject.id})"
      puts "  Asked by:  #{request.requested_by.name || request.requested_by.email}"
      puts "  Requested: #{request.requested_at}"
      puts "  Due:       #{request.due_at}"
      puts "  Reason:    #{request.reason.presence || '—'}"
      puts

      blockers = service.blockers
      if blockers.any?
        puts "BLOCKED — do not fulfil yet:"
        blockers.each { |b| puts "  * #{b}" }
        puts
        puts "Both blockers are temporary. Reply to the parent with a date rather than a refusal."
      else
        puts "No blockers. `rake fuime:data_request:fulfil[#{request.id}]` will:"
        puts "  * overwrite every identifier on user #{request.subject.id} and lock the account"
        puts "  * purge their profile picture, sessions and login codes"
        puts "  * KEEP the sales and ledger records of their business(es), with the person severed"
      end
    end

    desc "Carry out a deletion request. ID=<id> BY=<admin user id>"
    task :fulfil, [:id] => :environment do |_t, args|
      request = fetch_request(args)
      performed_by = ENV["BY"].presence && User.find(ENV["BY"])

      # Who did it is part of the record. A fulfilment with no name on it is the
      # sort of thing that is impossible to explain a year later.
      abort "Set BY=<admin user id> — the record has to say who carried this out." if performed_by.nil?
      abort "Request #{request.id} is #{request.status}, not open." unless request.status_open?
      abort "Request #{request.id} is an export, which was already served." unless request.kind_deletion?

      service = Fuime::DataErasureService.new(request:, performed_by:)
      blockers = service.blockers
      if blockers.any?
        puts "BLOCKED:"
        blockers.each { |b| puts "  * #{b}" }
        abort "Resolve these first, and tell the parent when to expect it."
      end

      service.perform!
      puts "Request ##{request.id} fulfilled. User #{request.subject_id} is erased and locked."
      puts "Reply to #{request.requested_by.email} to tell them it is done."
    end

    def fetch_request(args)
      id = args[:id].presence || ENV["ID"].presence
      abort "Usage: rake fuime:data_request:preview[<id>]" if id.blank?

      Fuime::DataRequest.find(id)
    end
  end
end
