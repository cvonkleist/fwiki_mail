require 'fwiki_api'

include FwikiAPI

describe Connection do
  before(:each) do
    @f = Connection.new(nil, nil, nil, nil)
  end

  def fake_response(code, body)
    response = mock('response')
    response.stub!(:code).and_return code
    response.stub!(:read_body).and_return body
    response
  end

  it 'should get list of all titles' do
    body = <<-EOF
    <html>
      <ul id="pages">
        <li><a href="/home">home</a></li>
        <li><a href="/asdf">asdf&lt;</a></li>
      </ul>
    </html>
    EOF
    @f.stub!(:get).and_return fake_response('200', body)
    (@f.all_titles - %w(home asdf<)).should == []
  end

  it 'should raise error if cannot get list of titles' do
    @f.stub!(:get).and_return fake_response('500', '')
    lambda { @f.all_titles }.should raise_error(Errno::ENOENT)
  end

  it 'should check the existence of a file' do
    @f.stub!(:sizes).and_return 'foo' => 1337
    @f.exists?('foo').should be_true
    @f.exists?('bar').should be_false
  end

  it 'should write a page' do
    @f.should_receive(:put).and_return fake_response('200', '')
    @f.write('foo', 'bar')
  end

  it 'should raise error on failure to write a page' do
    @f.should_receive(:put).and_return fake_response('500', '')
    lambda { @f.write('foo', 'bar') }.should raise_error(Errno::EAGAIN)
  end
end
