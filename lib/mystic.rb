#!/usr/bin/env ruby

require "mystic/migration"
require "mystic/extensions"
require "mystic/sql"
require "mystic/adapter"
require "mystic/model"

module Mystic
	MIGNAME_REGEX = /(?<num>\d+)_(?<name>[a-z]+)\.rb$/i # matches migration files (ex '1_MigrationClassName.rb')
	MysticError = Class.new(StandardError)
	
	def self.adapter
		@@adapter
	end
  
	def self.connect(env="")
		# Load database.yml
		env = env.to_s
		path = File.join(File.app_root, "/config/database.yml")
		db_conf = YAML.load_file(path)
		db_conf["dbname"] = db_conf.delete("database")
		raise MysticError, "Invalid database.yml config." if db_conf.member?(env)
		
		# get adapter name
		adapter = db_conf.delete("adapter").to_s.downcase
		adapter = "postgres" if adapter =~ /^postgr.*$/ # Intentionally includes PostGIS
		adapter = "mysql" if adapter =~ /^mysql.*$/
		
		# setup our adapter
		require "mystic/adapters/" + adapter
		
		adapter_class = "Mystic::#{adapter.capitalize}Adapter"
		@@adapter = Object.const_get(adapter_class).new
		@@adapter.pool_size = db_conf.delete("pool").to_i
		@@adapter.pool_timeout = db_conf.delete("timeout").to_i
		@@adapter.connect(db_conf)
	end
	
	def self.disconnect
		@@adapter.disconnect
		@@adapter = nil
	end

  def self.execute(sql)
		return [] if @@adapter.nil?
    @@adapter.exec(sql)
  end
  
  def self.sanitize(str)
		return str if @@adapter.nil?
    @@adapter.sanitize(str)
  end
	
	#
	# Command line
	#
	
	def self.migrate
		execute("CREATE TABLE IF NOT EXISTS mystic_migrations (mig_number integer, filename TEXT)")
	  migrated_filenames = Mystic.execute("SELECT filename FROM mystic_migrations").map{ |r| r["filename"] }
	  mp = File.join(File.app_root,"/mystic/migrations/")
		
	  Dir.entries(mp)
			.reject{ |e| MIG_REGEX.match(e).nil? && migrated_filenames.include?(e) }
			.sort{ |a,b| MIG_REGEX.match(a)[:num].to_i <=> MIG_REGEX.match(b)[:num].to_i.to_i }
			.each{ |fname| 
		    require File.join(mp,fname)
    
				mig_num,mig_name = MIG_REGEX.match(fname).captures
		
		    Object.const_get(mig_name).new.up
		    execute("INSERT INTO mystic_migrations (mig_number, filename) VALUES(#{mig_num},'#{fname}')")
			}
	end
	
	def self.rollback
		execute("CREATE TABLE IF NOT EXISTS mystic_migrations (mig_number integer, filename TEXT)")
		fname = Mystic.execute("SELECT filename FROM mystic_migrations ORDER BY mig_number DESC LIMIT 1").first.to_hash.fetch("filename")
		return if fname.nil?

	  require File.join(File.app_root,"/mystic/migrations/",fname)
		
		mig_num,mig_name = MIG_REGEX.match(fname).captures

	  Object.const_get(mig_name).new.down
	  Mystic.execute("DELETE FROM mystic_migrations WHERE filename='#{fname}' and mig_number=#{mig_num}")
	end
	
	def self.create_migration
    mig_name = ARGV[2].strip.capitalize
    
    Kernel.abort if mig_name.empty?
    
    mig_path = File.join(File.app_root,"/mystic/migrations/")
    
    mig_num = Dir.entries(mig_path).map { |fname| MIG_REGEX.match(fname)[:num].to_i }.max.to_i+1
		mig_fname = mig_num.to_s + "_" + mig_name + ".rb"

		File.open(File.join(mig_path,mig_fname), 'w') { |f| f.write(template(mig_name)) }
	end
	
	def self.template(name=nil)
		raise ArgumentError, "Migrations must have a name" if name.nil?
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