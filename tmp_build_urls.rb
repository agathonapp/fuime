# Build the crawl list: every GET route, with :params filled from real records.
# Routes we cannot fill (no such record exists) are written to unfillable.txt so
# the gap is visible rather than silently "passing".

def first_id(klass, &blk)
  k = klass.safe_constantize
  return nil unless k
  rec = blk ? k.find_by(&blk) : k.first
  rec&.id
rescue StandardError
  nil
end

biz  = Event.find_by(slug: "mayas-cookies") || Event.first
teen = User.find_by(email: "teen@fuime.test")
# Value for each :param name the router uses.
V = {}
V["event_slug"]  = biz&.slug
V["event_name"]  = biz&.slug
V["slug"]        = biz&.slug
V["event_id"]    = biz&.id
V["user_id"]     = teen&.id
V["id"]          = nil  # resolved per-route below

def sub_id_for(path, controller)
  case path
  when %r{^/guardian/}                    then (Guardianship.first&.invite_token || Guardianship.first&.id)
  when %r{^/users/}                       then User.find_by(email: "teen@fuime.test")&.id
  when %r{^/events/|^/\(?:event}          then Event.first&.id
  end
end

# Map controller -> model, so `:id` resolves to a record that actually exists.
CONTROLLER_MODEL = {
  "users" => "User", "events" => "Event", "comments" => "Comment",
  "receipts" => "Receipt", "guardianships" => "Guardianship",
  "organizer_positions" => "OrganizerPosition", "invoices" => "Invoice",
  "transactions" => "CanonicalTransaction", "hcb_codes" => "HcbCode",
  "stripe_cards" => "StripeCard", "sponsors" => "Sponsor",
  "tags" => "Tag", "announcements" => "Announcement",
}

rows = STDIN.read.lines.map(&:chomp).reject(&:empty?)
urls = []
unfillable = []

rows.each do |line|
  verb, path, ca = line.split("\t")
  next unless verb == "GET"
  controller, _action = ca.to_s.split("#")

  # Skip engines/asset/infra paths that aren't app pages.
  next if path.start_with?("/rails/", "/letter_opener", "/__crash_test", "/cable")
  next if path.include?("*")   # globs need a real subpath; handled separately

  filled = path.dup
  ok = true
  filled.scan(/:([a-z_]+)/).flatten.uniq.each do |param|
    val =
      case param
      when "event_slug", "event_name", "slug" then V["slug"]
      when "event_id"    then V["event_id"]
      when "user_id"     then V["user_id"]
      when "id"
        if controller.to_s.include?("guardianship")
          Guardianship.first&.invite_token
        else
          model = CONTROLLER_MODEL[controller.to_s.split("/").last]
          model ? first_id(model) : nil
        end
      else
        # Heuristic: :foo_id -> Foo
        if param.end_with?("_id")
          first_id(param.sub(/_id$/, "").camelize)
        end
      end
    if val.nil?
      ok = false
    else
      filled = filled.gsub(":#{param}", val.to_s)
    end
  end

  if ok
    urls << filled
  else
    unfillable << "#{path}\t#{ca}"
  end
end

File.write("/usr/src/app/tmp_urls.txt", urls.uniq.join("\n"))
File.write("/usr/src/app/tmp_unfillable.txt", unfillable.uniq.join("\n"))
puts "fillable=#{urls.uniq.size} unfillable=#{unfillable.uniq.size}"
