# frozen_string_literal: true

namespace :fuime do
  desc "Make a user an admin by email"
  task :make_admin, [:email] => :environment do |_t, args|
    email = args[:email]

    if email.blank?
      puts "Usage: rake fuime:make_admin[email@example.com]"
      exit 1
    end

    user = User.find_by(email: email)

    if user.nil?
      puts "User not found with email: #{email}"
      puts "Creating new admin user..."

      # Create a new user with admin access
      user = User.new(
        email: email,
        full_name: "Fuime Admin",
        access_level: :superadmin,
        verified: true
      )

      if user.save(validate: false)
        puts "Created new superadmin user: #{email}"
      else
        puts "Failed to create user: #{user.errors.full_messages.join(', ')}"
        exit 1
      end
    else
      user.update!(access_level: :superadmin, verified: true)
      puts "Made #{email} a superadmin!"
    end

    puts "User details:"
    puts "  ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Access Level: #{user.access_level}"
  end

  desc "List all admin users"
  task list_admins: :environment do
    admins = User.where(access_level: [:admin, :superadmin, :auditor])

    if admins.empty?
      puts "No admin users found."
    else
      puts "Admin users:"
      admins.each do |user|
        puts "  #{user.email} (#{user.access_level})"
      end
    end
  end
end
