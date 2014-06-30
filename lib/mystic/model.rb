#!/usr/bin/env ruby

module Mystic
  class Model
    JSON_COL = Mystic::JSON_COL
    
    def self.table_name
      to_s.downcase
    end
		
		def self.visible_cols
			["*"]
		end
		
		def self.wrapper_sql(params={})
			opts = params.symbolize!
			
			# .dup is so that input variables don't get modified.
			sql = opts[:sql].dup || "SELECT 1"
			return_rows = opts[:return_rows].dup || false
			return_json = opts[:return_json].dup || false
			return_rows = true if return_json
			
			op = sql.split(" ",2).first
			
			sql << " RETURNING #{visible_cols*','}" if return_rows && op != "SELECT"
			
			s = []
			s << "WITH res AS (#{sql})" if return_rows
			
			s << "SELECT"
			
			if return_json
				s << "row_to_json(res)" if op == "INSERT"
				s << "array_to_json(array_agg(res))" unless op == "INSERT"
				s << "AS #{JSON_COL}"
			else
				s << "*"
			end
			
			s << "FROM res"
			s*' '
		end

    def self.function_sql(funcname, *params)
			"SELECT #{funcname} (#{fnc_parameterize(params)*','})"
    end
    
    def self.select_sql(params={}, opts={})
			opts.symbolize!
      count = opts[:count] || 0
			return_json = opts[:return_json] && Mystic.adapter.name == "postgres"
			
			sql = "SELECT #{visible_cols*','} FROM #{table_name} WHERE #{params.sqlize*' AND '}"
			sql << " LIMIT #{count.to_i}" if count > 0
			
			wrapper_sql(
				:sql => sql,
				:return_rows => true,
				:return_json => opts[:return_json] && Mystic.adapter.adapter == "postgres"
			)
    end
    
    def self.update_sql(where={}, set={}, opts={})
      return "" if where.empty?
      return "" if set.empty?
			
			opts.symbolize!
			
			wrapper_sql(
				:sql => "UPDATE #{table_name} SET #{set.sqlize*','} WHERE #{where.sqlize*' AND '}",
				:return_rows => opts[:return_rows],
				:return_json => opts[:return_json] && Mystic.adapter.adapter == "postgres"
			)
    end
    
    def self.insert_sql(params={}, opts={})
			return "" if params.empty?
      
			opts.symbolize!

			wrapper_sql(
				:sql => "INSERT INTO #{table_name} (#{params.keys*','}) VALUES (#{params.values.sqlize*','})",
				:return_rows => opts[:return_rows],
				:return_json => opts[:return_json] && Mystic.adapter.adapter == "postgres"
			)
    end
    
    def self.delete_sql(params={}, opts={})
      return "" if params.empty?
			
			opts.symbolize!

			wrapper_sql(
				:sql => "DELETE FROM #{table_name} WHERE #{params.sqlize*' AND '}",
				:return_rows => opts[:return_rows],
				:return_json => opts[:return_json] && Mystic.adapter.adapter == "postgres"
			)
    end
    
    def self.select(params={}, opts={})
      Mystic.execute select_sql(params, opts)
    end
    
    def self.fetch(params={}, opts={})
      res = select(params,opts.merge({:count => 1}))
			return res if res.is_a?(String)
			res.first
    end
    
    def self.create(params={}, opts={})
      res = Mystic.execute insert_sql(params, opts)
			return res.first if res.is_a?(Array)
			res
    end
    
    def self.update(where={}, set={}, opts={})
      Mystic.execute update_sql(where, set, opts.merge({ :return_rows => true }))
    end
    
    def self.delete(params={}, opts={})
			Mystic.execute delete_sql(params, opts)
    end
		
		def self.exec_func(funcname, *params)
			Mystic.execute function_sql(funcname, *params)
		end
    
    private
    
    def self.fnc_parameterize(params)
      params.map do |param| 
        case param
        when String
          "'" + param.to_s.sanitize + "'" 
        when Integer, Float
          param.to_s.sanitize
        when Array, Hash
          # TODO: Turn into SQL params
        else
          nil
        end
      end
    end
  end
end