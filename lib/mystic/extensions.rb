#!/usr/bin/env ruby

module Kernel
	def self.silent
		v = $VERBOSE
		$VERBOSE = false
		yield
		$VERBOSE = v
		nil
	end
end

class String
  def capitalize_first!
    self[0] = self[0].upcase
  end
  
  def desnake
    downcase.split("_").map(&:capitalize)*' '
  end
	
  def escape
    Mystic.escape(self).untaint
  end
	
  alias_method :sanitize, :escape
  
	def truncate(len)
		self[0..len-1]
	end
	
	def sql_terminate
		return self + ";" unless dup.strip.end_with? ";"
		self
	end
end

class Array
  def merge_keys(*keys)
		raise ArgumentError, "No keys to merge." if keys.nil? || keys.empty?
    raise ArgumentError, "Argument array must have the same number of elements as self." if keys.count != self.count
    Hash[each_with_index.map{ |v,i| [keys[i],v] }]
  end
	
	def symbolize
		map(&:to_sym)
	end
	
	def symbolize!
		map!(&:to_sym)
	end
	
	def sqlize
		map { |o|
			case o
			when String
				"'#{o.sanitize}'"
			when Numeric
				o.to_s
			end
		}.compact
	end
end

class Hash
	def subhash *keys
		Hash[values_at(*keys).merge_keys(*keys).reject{ |k,v| v.nil? }]
	end
	
  def parify delim=" "
    map { |pair| pair * delim }
  end
	
	def compact
		reject { |k,v| v.nil? }
	end
	
	def compact!
		reject! { |k,v| v.nil? }
	end
	
	def symbolize
		Hash[map { |k,v| [k.to_sym, v]}]
	end
	
	def symbolize!
		keys.each { |key| self[key.to_sym] = delete key }
	end
  
  def sqlize
    reject { |k,v| v.nil? || (v.empty? rescue false) }.map{ |k,v| "#{k}=#{Integer === v ? v : "'#{v.to_s.sanitize}'" }" }
  end
end

class Pathname
	Kernel.silent do
		def to_s
			@path
		end
		
	  def relative?
	    @path[0] != File::SEPARATOR
	  end
	
		def join *args
			Pathname.new(File.join @path, *args.map(&:to_s))
		end
	end
end