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
  end

  class Processor
    def initialize(email, connection)
      @email, @connection = email, connection
    end

    def run
      edits.collect do |edit|
        process edit
      end
    end

    def process(edit)
      case edit.operation
      when :replace
        @connection.write edit.title, edit.body 
        EditResponse.new(:success, 'created/replaced "%s"' % edit.title)
      when :append
        @connection.write edit.title, @connection.read(edit.title) + "\n" + edit.body
        EditResponse.new(:success, 'appended to "%s"' % edit.title)
      when :prepend
        @connection.write edit.title, edit.body + "\n" + @connection.read(edit.title)
        EditResponse.new(:success, 'prepended to "%s"' % edit.title)
      when :insert_alpha
        lines = @connection.read(edit.title).split("\n", -1)
        insert_before = lines.find { |l| (l <=> edit.body) == 1 }
        lines.insert lines.index(insert_before), edit.body
        @connection.write edit.title, lines.join("\n")
        EditResponse.new(:success, 'alphabetically inserted into "%s"' % edit.title)
      end
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
      mail.write runner.report
    end
  end
end
