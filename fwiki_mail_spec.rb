require 'fwiki_mail'

include FwikiMail

describe Parser do
  it 'should include subject in message if provided' do
    email =<<-EOF
Subject: foo
From: asdf

bar
baz
    EOF
    p = Parser.new(email)
    p.message.should == "foo\nbar\nbaz\n"
  end

  it 'should not include subject in message if not provided' do
    email =<<-EOF
Subject: 
From: asdf

bar
baz
    EOF
    p = Parser.new(email)
    p.message.should == "bar\nbaz\n"
  end

  it 'should break an e-mail into segments' do
    message =<<-EOF
>foo
foo


>>bar
bar


<<baz
baz0

baz1


baz2


<bar2
bar2
    EOF
    p = Parser.new(nil)
    p.should_receive(:message).and_return(message)
    p.segments.should == [
      ">foo\nfoo\n",
      ">>bar\nbar\n",
      "<<baz\nbaz0\n\nbaz1\n\n\nbaz2\n",
      "<bar2\nbar2\n"
    ]
  end

  it 'should turn segments into edits' do
    p = Parser.new(nil)
    p.should_receive(:segments).and_return(
      [ ">foo\nfoo\n",
        ">>bar\nbar\n",
        "<<baz\n\n\n\n\nbaz\n",
        "<bar2\nbar2"
      ]
    )
    p.edits.length.should == 4
  end
end

describe Edit do
  [
    [">foo\nfoofoo\n", :replace, 'foo', "foofoo\n"],
    [">>bar\nbarbar\n", :append, 'bar', "barbar\n"],
    ["<<baz\n\n\nbaz\n", :prepend, 'baz', "\n\nbaz\n"],
    ["<bar2\nbar2", :insert_alpha, 'bar2', 'bar2']
  ].each do |test|
    segment, operation, title, body = test
    it 'should initialize from a message segment (%s)' % operation do
      e = Edit.new(segment)
      e.operation.should == operation
      e.title.should == title
      e.body.should == body
    end
  end

  it 'should be representable as a string' do
    segment = ">foo\nfoofoo\n"
    e = Edit.new(segment)
    e.to_s.should == segment
  end
end

describe Processor do
  it 'should run' do
    mock_parser = mock 'parser'
    mock_parser.stub!(:edits).and_return [nil]
    Parser.should_receive(:new).and_return mock_parser

    edit_response = mock('edit response')

    p = Processor.new(nil, nil)
    p.should_receive(:process).with(nil).and_return(edit_response)
    responses = p.run
    responses.first.should == edit_response
  end
end

describe Processor do
  before(:each) do
    @edit = mock 'edit'
    @edit.stub!(:title).and_return 'foo'
    @edit.stub!(:body).and_return 'foo body'

    @connection = mock 'connection'
  end

  it 'should process edits: replace (page exists)' do
    @edit.stub!(:operation).and_return :replace
    @connection.should_receive(:read).with('foo').and_return('existing content')
    @connection.should_receive(:write).with('foo', 'foo body')

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: replaced "foo"'
  end

  it 'should process edits: replace (page is new)' do
    @edit.stub!(:operation).and_return :replace
    @connection.should_receive(:read).with('foo').and_raise Errno::ENOENT
    @connection.should_receive(:write).with('foo', 'foo body')

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: created "foo"'
  end

  # this also stands as a spec for the same condition with :prepend and
  # :insert_alpha
  it 'should process edits: replace (asked for append on nonexistent page)' do
    @edit.stub!(:operation).and_return :append
    @connection.should_receive(:read).with('foo').and_raise Errno::ENOENT
    @connection.should_receive(:write).with('foo', "foo body")

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: created "foo"'
  end

  it 'should process edits: append' do
    @edit.stub!(:operation).and_return :append
    @connection.should_receive(:read).with('foo').and_return('existing content')
    @connection.should_receive(:write).with('foo', "existing content\nfoo body")

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: appended to "foo"'
  end

  it 'should process edits: prepend' do
    @edit.stub!(:operation).and_return :prepend
    @connection.should_receive(:read).with('foo').and_return('existing content')
    @connection.should_receive(:write).with('foo', "foo body\nexisting content")

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: prepended to "foo"'
  end

  it 'should process edits: insert_alpha' do
    @edit.stub!(:operation).and_return :insert_alpha
    @connection.should_receive(:read).with('foo').and_return("asdf\nbar\nfoo\nmoo\n")
    @connection.should_receive(:write).with('foo', "asdf\nbar\nfoo\nfoo body\nmoo\n")

    p = Processor.new(nil, @connection)
    p.process(@edit).to_s.should == 'success: alphabetically inserted into "foo"'
  end

  it 'should give a good message on error when processing edits' do
    p = Processor.new(nil, @connection)
    p.should_receive(:edits).and_return [Edit.new(">foo\nbar\n")]
    p.should_receive(:process).and_raise Exception.new('suckage')
    p.run.first.to_s.should == "failure: got error #<Exception: suckage> while processing this edit:\n>foo\nbar\n"
  end
end

describe EditResponse do
  it 'should stringify itself' do
    er = EditResponse.new(:success, 'created page "foo"')
    er.to_s.should == 'success: created page "foo"'
  end
end

describe Runner do
  it 'should initialize' do
    FwikiAPI::Connection.should_receive(:new).with(:host, :port, :username, :password)
    r = Runner.new(:host, :port, :username, :password, :email)
  end

  it 'should run' do
    connection = mock('connection')
    FwikiAPI::Connection.stub!(:new).and_return connection

    r = Runner.new(:host, :port, :username, :password, :email)
    
    processor = mock('processor')
    Processor.should_receive(:new).with(:email, connection).and_return processor
    processor.should_receive(:run).and_return ['success: bla', 'failure: asdf']

    r.run!
    r.report.should == "- success: bla\n- failure: asdf"
  end
end
