require 'net/http'
require 'nokogiri'
require 'cgi'

class String
  def title_to_path
    '/' + self
  end
end

module FwikiAPI
  class Connection
    def initialize(host, port, username, password)
      @host, @port, @username, @password = host, port, username, password
      @http = Net::HTTP.new(@host, @port)
      @http.set_debug_output STDERR
    end

    def read(title)
      response = get(title.title_to_path, 'raw' => 'fishsticks')
      puts response.inspect
      raise Errno::ENOENT unless response.code == '200'
      response.read_body
    end

    def write(title, contents)
      response = put(title.title_to_path, contents)
      raise Errno::EAGAIN unless response.code == '200'
    end

    def all_titles
      sizes.keys
    end

    def exists?(title)
      all_titles.include?(title)
    end

    private

    def get(path, params = {})
      request = Net::HTTP::Get.new(escape(path))
      request.form_data = params
      request.basic_auth @username, @password
      @http.request(request)
    end

    def put(path, contents)
      request = Net::HTTP::Put.new(escape(path))
      request.set_form_data(:contents => contents)
      request.basic_auth @username, @password
      @http.request(request)
    end

    def sizes
      response = get('/', :long => 'wangs')
      raise Errno::ENOENT unless response.code == '200'
      doc = Nokogiri::XML(response.read_body)
      doc.search('//ul[@id = "pages"]/li').inject({}) do |sum, li|
        sum.merge CGI.unescapeHTML(li.at('a').inner_html) => li.inner_html[%r((\d+) bytes), 1].to_i
      end
    end

    private

    def escape(path)
      CGI.escape(path).gsub('%2F', '/')
    end
  end
end
