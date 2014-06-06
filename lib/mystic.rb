#!/usr/bin/env ruby

require "yaml"
require "irb"
require "mystic/extensions"
require "mystic/sql"
require "mystic/adapter"
require "mystic/migration"
require "mystic/model"

module Mystic
	MIG_REGEX = /(?<num>\d+)_(?<name>[a-z]+)\.rb$/i # matches migration files (ex '1_MigrationClassName.rb')
	MysticError = Class.new(StandardError)
	EnvironmentError = Class.new(StandardError)
	@@adapter = nil
	
	def self.adapter
		@@adapter
	end
  
  # Mystic.connect
  #   Connects to a database. It's recommended you use it like ActiveRecord::Base.establish_connection
  # Arguments:
  #   env - The env from database.yml you wish to use
	def self.connect(env="")
		# Load database.yml
		env = env.to_s
		path = File.join(File.app_root, "/config/database.yml")
		db_yml = YAML.load_file(path)
		
		raise EnvironmentError, "Environment doesn't exist." unless db_yml.member?(env)
		
		db_conf = db_yml[env]
		db_conf["dbname"] = db_conf.delete("database")
		
		# get adapter name
		adapter = db_conf.delete("adapter").to_s.downcase
		adapter = "postgres" if adapter =~ /^postgr.*$/ # Intentionally includes PostGIS
		adapter = "mysql" if adapter =~ /^mysql.*$/
		
		# setup our adapter
		require "mystic/adapters/" + adapter
		
		adapter_class = "Mystic::#{adapter.capitalize}Adapter"
		@@adapter = Object.const_get(adapter_class).new(:env => env)
		@@adapter.pool_size = db_conf.delete("pool").to_i
		@@adapter.pool_timeout = db_conf.delete("timeout").to_i
		@@adapter.connect(db_conf)
		
		true
	end
	
  # Mystic.disconnect
  #   Disconnects from the connected database. Use it like ActiveRecord::Base.connection.disconnect!
	def self.disconnect
		@@adapter.disconnect
		@@adapter = nil
		true
	end

  # Mystic.execute
  #   Execute some sql. It will be densified (the densify gem) and sent to the DB
  # Arguments:
  #   sql - The SQL to execute
  # Returns: Native Ruby objects representing the response from the DB (Usually an Array of Hashes)
  def self.execute(sql="")
		return [] if @@adapter.nil?
    @@adapter.execute(sql)
  end
  
  # Mystic.sanitize
  #   Escape a string so that it can be used safely as input. Mystic does not support statement preparation, so this is a must.
  # Arguments:
  #   str - The string to sanitize
  # Returns: the sanitized string
  def self.sanitize(str="")
		return str if @@adapter.nil?
    @@adapter.sanitize(str)
  end
	
	# Mystic.root
	#   Get the app root
	# Aguments:
	#   To be ignored
	# Returns:
	#   The application's root
  def self.root(path=Dir.pwd)
    mystic_dir_path = expand_path("mystic",path)
    return path if exists?(mystic_dir_path) && directory?(mystic_dir_path)
    app_root(dirname(path)) unless path.length == 1
  end
	
	#
	# Command line
	#
	
	def self.console
		require "mystic"
		puts "Starting Mystic console"
		IRB.setup nil
		IRB.conf[:IRB_NAME] = "mystic"
		IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
		require 'irb/ext/multi-irb'
		IRB.irb nil, IRB::WorkSpace.new
		nil
	end
	
  # Runs every yet-to-be-ran migration
	def self.migrate
		execute("CREATE TABLE IF NOT EXISTS mystic_migrations (mig_number integer, filename TEXT)")
	  migrated_filenames = execute("SELECT filename FROM mystic_migrations").map{ |r| r["filename"] }
	  mp = File.join(File.app_root,"/mystic/migrations/")
		
	  Dir.entries(mp)
			.reject{ |e| MIG_REGEX.match(e).nil? || migrated_filenames.include?(e) }
			.sort{ |a,b| MIG_REGEX.match(a)[:num].to_i <=> MIG_REGEX.match(b)[:num].to_i }
			.each{ |fname| 
		    require File.join(mp,fname)
    
				mig_num,mig_name = MIG_REGEX.match(fname).captures
		
		    Object.const_get(mig_name).new.up
		    execute("INSERT INTO mystic_migrations (mig_number, filename) VALUES(#{mig_num},'#{fname}')")
			}
	end
	
  # Rolls back a single migration
	def self.rollback
		execute("CREATE TABLE IF NOT EXISTS mystic_migrations (mig_number integer, filename TEXT)")
		res = execute("SELECT filename FROM mystic_migrations ORDER BY mig_number DESC LIMIT 1")
		return if res.empty?
		fname = res.first.fetch("filename")
		return if fname.nil?

	  require File.join(File.app_root,"/mystic/migrations/",fname)
		
		mig_num,mig_name = MIG_REGEX.match(fname).captures

	  Object.const_get(mig_name).new.down
	  Mystic.execute("DELETE FROM mystic_migrations WHERE filename='#{fname}' and mig_number=#{mig_num}")
	end
	
  # Creates a blank migration in mystic/migrations
	def self.create_migration(name)
		if name.nil? || name.empty?
			puts "Migration name must not be empty."
			return
		end
		
		name.strip!
		name[0] = name[0].capitalize
    
    mig_path = File.join(File.app_root,"/mystic/migrations/")

		# 6 is the minimum length of a migration: 1_a.rb
    numbers = 
		Dir.entries(mig_path)
		.select{ |fname| fname.length >= 6 }
		.map { |fname|
			match = MIG_REGEX.match(fname)
			match.nil? ? nil : match[:num].to_i
		}
		.compact

		mig_num = numbers.count > 0 ? numbers.max.to_i+1 : 1
		mig_fname = "#{mig_num}_#{name}.rb"

		File.open(File.join(mig_path,mig_fname), 'w') { |f| f.write(template(name)) }
	end
	
  # Retuns a blank migration's code in a String
	def self.template(name=nil)
		raise ArgumentError, "Migrations must have a name." if name.nil?
		<<-mig_template
#!/usr/bin/env ruby

require "mystic"

class #{name} < Mystic::Migration
	def up
		
	end
  
	def down
		
	end
end
		mig_template
	end
end