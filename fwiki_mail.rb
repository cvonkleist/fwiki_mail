require 'fwiki_api'

module FwikiMail
  # the parser turns an e-mail message into Edit objects
  class Parser
    def initialize(email)
      @email = email
    end

    # returns the e-mail minus headers (including the "Subject: " part of the
    # subject header)
    #
    # the subject header can contain part of the message (e.g., ">foo")
    def message
      if subject && !subject.empty?
        subject + "\n" + body
      else
        body
      end
    end

    # returns all the edit segments in the message as an array
    def segments
      message.split(%r(\n\n(?=[<>])))
    end

    # returns the segments as Edit objects
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

  # an edit is an order to change a wiki page
  class Edit
    # +segment+ is a section of a message (e.g, ">foo\nbar\n")
    def initialize(segment)
      @segment = segment
    end

    # interprets the edit-operation characters and returns a symbol
    # representing the type of edit
    def operation
      case @segment[%r(^([<>]{1,2})), 1]
      when '>': :replace
      when '>>': :append
      when '<<': :prepend
      when '<': :insert_alpha
      end
    end

    # title of the page the edit should act on
    def title
      @segment[%r(^[<>]{1,2}(.*)$), 1]
    end

    # new text to apply to the page
    def body
      @segment[%r(^.*?\n(.*)$)m, 1]
    end

    # the segment originally parsed by #initialize
    def to_s
      @segment
    end
  end

  # given an e-mail message and a fwiki connection, apply all the edits in the
  # message to the wiki
  class Processor
    def initialize(email, connection)
      @email, @connection = email, connection
    end

    # perform each edit, collecting response messages
    #
    # returns an array of edit responses (summaries of success or failure)
    def run
      edits.collect do |edit|
        begin
          process edit
        rescue Exception => e
          EditResponse.new(:failure, "got error %s while processing this edit:\n%s" % [e.inspect, edit])
        end
      end
    end

    # perform the specified +edit+
    #
    # returns an edit response (summary of the successful edit)
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

  # an edit response is a message like 'success: appended to "foobar"', but as
  # an object
  class EditResponse
    def initialize(status, message)
      @status, @message = status, message
    end
    def to_s
      @status.to_s + ': ' + @message.to_s
    end
  end

  # given login parameters details and an e-mail message, Runner connects to a
  # fwiki instance and makes a new Processor to perform the edits
  class Runner
    def initialize(host, port, username, password, email)
      @connection = FwikiAPI::Connection.new(host, port, username, password)
      @email = email
    end

    # launch a processor to perform the edits specified in +@email+
    #
    # returns EditResponse objects as an array
    def run!
      processor = Processor.new(@email, @connection)
      @edit_responses = processor.run
    end

    # turns the collected +@edit_reponses+ into a printable message
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

  report_email_address ||= email[%r(([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}))i, 1]
  IO.popen('mail "%s"' % report_email_address, 'w') do |mail|
    mail.puts runner.report
  end
end
