require 'fwiki_api'

module FwikiMail
  class Parser
    def initialize(email)
      @email = email
    end

    def message
      if subject && !subject.empty?
        subject + "\n" + body
      else
        body
      end
    end

    def segments
      message.split(%r(\n\n(?=[<>])))
    end

    def edits
      segments.collect do |segment|
        Edit.new(segment)
      end
    end

    private
    def body
      @email[%r(\n\n(.*$))m, 1]
    end

    def subject
      @email[%r(^Subject: (.*)$), 1]
    end
  end

  class Edit
    def initialize(segment)
      @segment = segment
    end

    def operation
      case @segment[%r(^([<>]{1,2})), 1]
      when '>': :replace
      when '>>': :append
      when '<<': :prepend
      when '<': :insert_alpha
      end
    end

    def title
      @segment[%r(^[<>]{1,2}(.*)$), 1]
    end

    def body
      @segment[%r(^.*?\n(.*)$)m, 1]
    end

    def inspect
      '#<Edit: operation = %s / title = %s / body = %s>' % [operation.inspect, title.inspect, body.inspect]
    end

    def to_s
      @segment
    end
  end

  class Processor
    def initialize(email, connection)
      @email, @connection = email, connection
    end

    def run
      edits.collect do |edit|
        begin
          process edit
        rescue Exception => e
          EditResponse.new(:failure, "got error %s while processing this edit:\n%s" % [e.inspect, edit])
        end
      end
    end

    def process(edit)
      body = @connection.read(edit.title) rescue nil

      new_body, verb =
        if edit.operation == :replace || body.nil?
          [edit.body, body.nil? ? 'created' : 'replaced']
        else
          case edit.operation
          when :append
            [body + "\n" + edit.body, 'appended to']
          when :prepend
            [edit.body + "\n" + body, 'prepended to']
          when :insert_alpha
            lines = body.split("\n", -1)
            insert_before = lines.find { |l| (l <=> edit.body) == 1 }
            lines.insert lines.index(insert_before), edit.body
            [lines.join("\n"), 'alphabetically inserted into']
          end
        end

      @connection.write(edit.title, new_body)
      EditResponse.new(:success, '%s "%s"' % [verb, edit.title])
    end

    private

    def edits
      Parser.new(@email).edits
    end
  end

  class EditResponse
    def initialize(status, message)
      @status, @message = status, message
    end
    def to_s
      @status.to_s + ': ' + @message.to_s
    end
  end

  class Runner
    def initialize(host, port, username, password, email)
      @connection = FwikiAPI::Connection.new(host, port, username, password)
      @email = email
    end

    def run!
      processor = Processor.new(@email, @connection)
      @edit_responses = processor.run
    end

    def report
      @edit_responses.collect { |er| '- ' + er.to_s }.join("\n")
    end
  end
end

if $0 == __FILE__
  if ARGV.length < 4
    puts 'usage: %s host port username password < email.txt' % File.basename($0)
    exit 1
  end
  host, port, username, password, report_email_address = ARGV
  email = STDIN.read
  runner = FwikiMail::Runner.new(host, port, username, password, email)
  runner.run!
  puts runner.report
  if report_email_address
    IO.popen('mail ' + report_email_address, 'w') do |mail|
      mail.puts runner.report
    end
  end
end
