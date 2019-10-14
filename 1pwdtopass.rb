#!/usr/bin/env ruby

# Original script from https://github.com/tobiasvl/1password2pass
# Extensively modified by Narcis M Pap to import everything 1Password stores, including OTPs

# Copyright (C) 2014 Tobias V. Langhoff <tobias@langhoff.no>. All Rights Reserved.
# This file is licensed under GPLv2+. Please see COPYING for more information.

require "optparse"
require "ostruct"
require 'uri'

accepted_formats = [".1pif"]
options = OpenStruct.new
options.force = false
options.name = :title
options.simulate = false
options.dns_naming = false

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{opts.program_name}.rb [options] filename"
  opts.on_tail("-h", "--help", "Display this screen") { puts opts; exit }
  opts.on("-f", "--force", "Overwrite existing passwords") do
    options.force = true
  end
  opts.on("-d", "--default [FOLDER]", "Place passwords into FOLDER") do |group|
    options.group = group
  end
  opts.on("-n", "--name [PASS-NAME]", [:title, :url],
          "Select field to use as pass-name: title (default) or URL") do |name|
    options.name = name
  end
  opts.on("-s", "--simulate", "Simulates the import, doesn't write to pass") do |simulate|
    options.simulate = true
  end
  opts.on("-j", "--dns", "Logins use dns naming convention, e.g: com.google.mail") do |dns_naming|
    options.dns_naming = true
  end


  begin
    opts.parse!
  rescue OptionParser::InvalidOption
    $stderr.puts optparse
    exit
  end
end

# Check for a valid filename
filename = ARGV.pop
unless filename
  abort optparse.to_s
end
unless accepted_formats.include?(File.extname(filename.downcase))
  abort "Supported file types: .1pif files."
end

passwords, id_map = [], {}
cnt_metadata, cnt_otp = 0, 0
cnt_cards, cnt_notes, cnt_ssn, cnt_wifi, cnt_software, cnt_login = 0, 0, 0, 0, 0, 0

def write_pass(io, pass)
  io.puts pass[:password]
  io.puts "login: #{pass[:login]}" unless pass[:login].to_s.empty?
  io.puts "url: #{pass[:url]}" unless pass[:url].to_s.empty?
  io.puts "#{pass[:otp]}" unless pass[:otp].to_s.empty?
  io.puts pass[:extra] unless pass[:extra].to_s.empty?
  io.puts pass[:notes] unless pass[:notes].to_s.empty?
end

if File.extname(filename) =~ /.1pif/i
  require "json"
  options.name = :location if options.name == :url

  # 1PIF is almost JSON, but not quite.  Remove the ***...*** lines
  # separating records, and then remove the trailing comma
  pif = File.open(filename).read.gsub(/^\*\*\*.*\*\*\*$/, ",").chomp.chomp(",")
  pos = 0

  JSON.parse("[#{pif}]", symbolize_names: true).each do |entry|
    next if entry[:secureContents].nil?

    pos += 1
    pass = {}
    extra_d = {"created": entry[:createdAt], "updated": entry[:updatedAt]}

    pass[:name] = "#{entry[options.name]}#{pos}"
    pass[:name] = pass[:name].downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')

    # Credit Card
    if entry[:typeName] == "wallet.financial.CreditCard"
      cnt_cards += 1
      pass[:name] = "#{pass[:name]}.CC"

    # SSN 
    elsif entry[:typeName] == "wallet.government.SsnUS"
      cnt_ssn += 1
      pass[:name] = "#{pass[:name]}.SSN"
    
    # Software 
    elsif entry[:typeName] == "wallet.computer.License"
      cnt_software += 1
      pass[:name] = "#{pass[:name]}.SFT"

    # Notes
    elsif entry[:typeName] == "securenotes.SecureNote"
      cnt_notes += 1
      pass[:name] = "#{pass[:name]}.XNOTE"

      # WiFi Networks
    elsif entry[:typeName] == "wallet.computer.Router"
      cnt_wifi += 1
      pass[:name] = "#{pass[:name]}.WIFI"
    
    # Login Item
    elsif entry[:typeName] == "webforms.WebForm"
      cnt_login += 1
      
      # reverse-dns naming convention, e.g: com.google.mail
      if options.dns_naming and entry[:location]
        uri_host = URI.parse(entry[:location]).host
        if uri_host
          uri = uri_host.split('.')
          uri.delete("www")
          uri.delete("m")
          pass[:name] = uri.reverse.join(".")
        end
      end

      pass[:title] = entry[:title]
      pass[:url] = entry[:location]

      if password = entry[:secureContents][:fields]
        password = entry[:secureContents][:fields].detect do |field|
          field[:designation] == "password"
        end
        pass[:password] = password[:value] if password

        username = entry[:secureContents][:fields].detect do |field|
          field[:designation] == "username"
        end
        pass[:login] = username[:value] if username
      end

      # otpauth (requires pass-opt)
      if entry[:secureContents][:sections]
        entry[:secureContents][:sections].each do |section|
          if section[:fields]
            section[:fields].each do |s_field|
              if s_field[:v] && s_field[:v].to_s.match(/^otpauth/)
                pass[:otp] = s_field[:v]
                cnt_otp += 1
              end
            end
          end
        end
      end
    else
      next
    end

    # extra sections (used for meta on all items but Logins)
    if entry[:secureContents][:sections]
      entry[:secureContents][:sections].each do |section|
        if section[:fields]
          section[:fields].each do |fs|
              if !fs[:n].to_s.empty? and !fs[:v].to_s.empty?
                if fs[:k] == "address"
                  extra_d["Address"] = "#{fs[:v][:street]}, #{fs[:v][:city]}, #{fs[:v][:state]}, #{fs[:v][:region]}, #{fs[:v][:zip]}, #{fs[:v][:country]}"
                else
                  m_key = fs[:n]
                  if fs[:n].length == 32 # a 32-char is an ID, use the desc or type in this case
                    if fs[:t].empty?
                      m_key = fs[:k]
                    else  
                      m_key = fs[:t]
                    end
                  end
                  extra_d[m_key] = fs[:v]
                end

                cnt_metadata += 1
              end
          end
        end
      end
    end

    # any extra data stored in secureContents, usually browser data or custom form input
    if entry[:secureContents][:fields]
      entry[:secureContents][:fields].each do |fs|
        if fs[:name] != "password" && fs[:name] != "username"
          if !fs[:value].to_s.empty? and !fs[:name].to_s.empty?
            extra_d[fs[:name]] = fs[:value]
            cnt_metadata += 1
          end
        end
      end
    end

    extra = ""
    extra_d.each do |eK, eV|
      extra << "#{eK}: #{eV}\n"
    end
    
    pass[:name] = "#{(options.group + "/") if options.group}#{pass[:name]}" 
    if id_map.key?(pass[:name])
      pass[:name] = "#{pass[:name]}#{pos}" 
    end  
    id_map[pass[:name]] = true

    pass[:notes] = entry[:secureContents][:notesPlain]
    pass[:extra] = extra
    passwords << pass
  end
end

errors = []
if options.simulate
  puts "######### SIMULATED #########"
end

# Save the passwords
passwords.each do |pass|

  if options.simulate
    puts "### #{pass[:name]}"
    write_pass($stdout, pass)
    puts "-------"
  else
    IO.popen("pass insert #{"-f " if options.force}-m \"#{pass[:name]}\" > /dev/null", "w") do |io|
      write_pass(io, pass)
    end
    if $? == 0
      puts "Imported #{pass[:name]}"
    else
      $stderr.puts "ERROR: Failed to import #{pass[:name]}"
      errors << pass
    end
  end

end

puts "Discovered #{passwords.length} Records, #{cnt_metadata} meta and #{cnt_otp} OTPs."
puts "#{cnt_login} Logins, #{cnt_cards} Cards, #{cnt_notes} Notes, #{cnt_ssn} SSN, #{cnt_wifi} Wireless, #{cnt_software} License"

if errors.length > 0
  $stderr.puts "Failed to import #{errors.map {|e| e[:name]}.join ", "}"
  $stderr.puts "Check the errors. Make sure these passwords do not already "\
               "exist. If you're sure you want to overwrite them with the "\
               "new import, try again with --force."
end
