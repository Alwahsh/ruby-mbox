#--
# Copyleft meh. [http://meh.doesntexist.org | meh@paranoici.org]
#
# This file is part of ruby-mbox.
#
# ruby-mbox is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ruby-mbox is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with ruby-mbox. If not, see <http://www.gnu.org/licenses/>.
#++

require 'stringio'

require 'mbox/mail'

class Mbox
	def self.open (path, options = {})
		input = File.open(File.expand_path(path), 'r+:ASCII-8BIT')

		Mbox.new(input, options).tap {|mbox|
			mbox.path = path
			mbox.name = File.basename(path)

			if block_given?
				yield mbox

				mbox.close
			else
				ObjectSpace.define_finalizer mbox, finalizer(input)
			end
		}
	end

	def self.finalizer (io)
		proc { io.close }
	end
	
	def self.separator
	  return /^From [^\s]+  ?\w{3}(,| )\w{3} (\d| )\d \d{2}:\d{2}:\d{2} \d{4}/
	end
	
	include Enumerable

	attr_reader   :options
	attr_accessor :name, :path

	def initialize (what, options = {})
		@input = if what.respond_to? :to_io
			what.to_io
		elsif what.is_a? String
			StringIO.new(what)
		else
			raise ArgumentError, 'I do not know what to do.'
		end

		@options = { separator: Mbox.separator }.merge(options)
	end

	def close
		@input.close
	end

	def lock
		if @input.respond_to? :flock
			@input.flock File::LOCK_SH
		end

		if block_given?
			begin
				yield self
			ensure
				unlock
			end
		end
	end

	def unlock
		if @input.respond_to? :flock
			@input.flock File::LOCK_UN
		end
	end

	def each (opts = {})
		@input.seek 0

		lock {
			while mail = Mail.parse(@input, options.merge(opts))
				yield mail
			end
		}
	end
	
	def each_raw_message (opts = {})
		@input.seek 0

		lock {
			res = @input.readline
			while line = @input.readline rescue nil
				if line.match(options[:separator]) || @input.eof?
					yield res
					res = ""
				end
				res << line
			end
		}
	end
	
	def each_between_indeces (beginning,num,opts = {})
		seek beginning
		current = 0
		lock {
			while mail = Mail.parse(@input, options.merge(opts))
				current += 1
				if current > num
					break
				end
				yield mail
			end
		}
	end

	def until (date,opts = {})
		@input.seek 0

		lock {
			while mail = Mail.parse(@input, options.merge(opts))
				mail_date = mail.ruby_date
				unless mail_date
					yield mail
					next
				end
				if mail_date > date
					break
				end
				yield mail
			end
		}
	end
	
	def since (date, opts = {})
		@input.seek 0

		lock {
			begin_yield = false
			while mail = Mail.parse(@input, options.merge(opts))
				if begin_yield
					yield mail
					next
				end
				mail_date = mail.ruby_date
				next unless mail_date
				if mail_date >= date
				    begin_yield = true
				    yield mail
				end
			end
		}
	end

	def between (after,before, opts = {})
		@input.seek 0

		lock {
			begin_yield = false
			while mail = Mail.parse(@input, options.merge(opts))
				mail_date = mail.ruby_date
				next unless mail_date
				if mail_date > before
					break
				end
				if mail_date >= after
					yield mail
				end
			end
		}
	end
	
	def [] (index, opts = {})
		lock {
			seek index

			if @input.eof?
				raise IndexError, "#{index} is out of range"
			end

			res = @input.readline
			while line = @input.readline rescue nil
				if line.match(options[:separator]) || @input.eof?
					return res
				end
				res << line
			end
		}
	end

	def seek (to, whence = IO::SEEK_SET)
		if whence == IO::SEEK_SET
			@input.seek 0
		end

		last   = ''
		index  = -1

		while line = @input.readline rescue nil
			if line.match(options[:separator])
				index += 1

				if index >= to
					@input.seek(-line.length, IO::SEEK_CUR)

					break
				end
			end

			last = line
		end

		self
	end

	def length
		@input.seek(0)

		last   = ''
		length = 0

		lock {
			until @input.eof?
				line = @input.readline

				if line.match(options[:separator])
					length += 1
				end

				last = line
			end
		}

		length
	end

	alias size length

	def has_unread?
		each headers_only: true do |mail|
			return true if mail.unread?
		end

		false
	end

	def inspect
		"#<Mbox:#{name} length=#{length}>"
	end
	
end
