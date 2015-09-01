require 'httparty'
class Request
  
  attr_accessor :params, :httpresponse
  
  def initialize(params)
    @params = essential_params.merge(params)
  end
  
  def process
    query_string = canonical_querystring(@params)
    
string_to_sign = "GET
#{AmazeSNS.host}
/
#{query_string}"
                
      hmac = HMAC::SHA256.new(AmazeSNS.skey)
      hmac.update( string_to_sign )
      signature = Base64.encode64(hmac.digest).chomp
      
      params['Signature'] = signature
      querystring2 = params.collect { |key, value| [url_encode(key), url_encode(value)].join("=") }.join('&') # order doesn't matter for the actual request

      @httpresponse =  http_class.get("http://#{AmazeSNS.host}/?"+querystring2)
      success_callback
  end

  def http_class
    HTTParty
  end
  
  
  def success_callback
    puts "RESPONSE:"
    puts @httpresponse.body
    if @httpresponse.code == 200
      @httpresponse
    else
      {response: @httpresponse.body, status: @httpresponse.code}
    end
  end

  def error_callback
    raise AmazeSNSRuntimeError.new("A runtime error has occured: status code: #{@httpresponse.response_header.status}")
  end
  
  private
  
    def essential_params
      {
        'SignatureMethod' => AmazeSNS.signature_method,
        'SignatureVersion' => AmazeSNS.signature_version,
        'Timestamp' => Time.now.iso8601, #Time.now.iso8601 makes tests fail
        'AWSAccessKeyId' => AmazeSNS.akey,
        'Version' => AmazeSNS.api_version
      }
    end
  
end