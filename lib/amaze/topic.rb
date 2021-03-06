require File.dirname(__FILE__) + "/request"
require File.dirname(__FILE__) + "/exceptions"
require "json"

class Topic
  
  attr_accessor :topic, :arn, :attributes

  def initialize(topic, arn='')
    @topic = topic
    @arn = arn
    @attributes = {}
  end
  
  def generate_request(params)
    request = Request.new(params)
    result  = request.process
    yield result
  end
  
  
  def create
    params = {
      'Name' => "#{@topic}",
      'Action' => 'CreateTopic',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
     }
     generate_request(params) do |response|
       parsed_response = Crack::XML.parse(response.body)
       @arn = parsed_response["CreateTopicResponse"]["CreateTopicResult"]["TopicArn"]
       AmazeSNS.topics[@topic.to_s] = self # add to hash
       AmazeSNS.topics.rehash
     end
    @arn
  end
  
  # delete topic
  def delete
    parsed_response = ''
    params = {
      'TopicArn' => "#{arn}",
      'Action' => 'DeleteTopic',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
     }
     generate_request(params) do |response|
       parsed_response = Crack::XML.parse(response.body)
       AmazeSNS.topics.delete("#{@topic}")
       AmazeSNS.topics.rehash
     end
    parsed_response
  end
  
  # get attributes for topic from remote sns server
  # TopicArn -- the topic's ARN 
  # Owner -- the AWS account ID of the topic's owner 
  # Policy -- the JSON serialization of the topic's access control policy 
  # DisplayName -- the human-readable name used in the "From" field for notifications to email and email-json endpoints 
  
  def attrs
    outcome = nil
    params = {
      'TopicArn' => "#{@arn}",
      'Action' => 'GetTopicAttributes',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
     }

     generate_request(params) do |response|
       parsed_response = Crack::XML.parse(response.body) 
       res = parsed_response['GetTopicAttributesResponse']['GetTopicAttributesResult']['Attributes']["entry"]
       outcome = make_hash(res) #res["entry"] is an array of hashes - need to turn it into hash with key value
       self.attributes = outcome
     end
     outcome
  end
  
  # The SetTopicAttributes action allows a topic owner to set an attribute of the topic to a new value.
  # only following attributes can be set:
  # TopicArn -- the topic's ARN 
  # Owner -- the AWS account ID of the topic's owner 
  # Policy -- the JSON serialization of the topic's access control policy 
  # DisplayName -- the human-readable name used in the "From" field for notifications to email and email-json endpoints
  
  def set_attrs(opts)
    outcome = nil
    #TODO: check format of opts to make sure they are compilant with API
    params = {
      'AttributeName' => "#{opts[:name]}",
      'AttributeValue' => "#{opts[:value]}",
      'TopicArn' => "#{arn}",
      'Action' => 'SetTopicAttributes',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }
    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body) 
      outcome = parsed_response['SetTopicAttributesResponse']['ResponseMetadata']['RequestId']
      # update the attributes hash if request is successful ...
      self.attributes["#{opts[:name]}"] = "#{opts[:value]}" if response.code.to_s == "200"
    end
    outcome
  end
  
  # subscribe method
  def subscribe(opts)
    raise InvalidOptions unless ( !(opts.empty?) && opts.instance_of?(Hash) )
    res=''
    params = {
      'TopicArn' => "#{@arn}",
      'Endpoint' => "#{opts[:endpoint]}",
      'Protocol' => "#{opts[:protocol]}",
      'Action' => 'Subscribe',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }

    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      res = parsed_response['SubscribeResponse']['SubscribeResult']['SubscriptionArn']
    end
    res
  end
  
  def unsubscribe(id)
    raise InvalidOptions unless ( !(id.empty?) && id.instance_of?(String) )
    res=''
    params = {
      'SubscriptionArn' => "#{id}",
      'Action' => 'Unsubscribe',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }

    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      res = parsed_response['UnsubscribeResponse']['ResponseMetadata']['RequestId']
    end
    res
  end
  
  
  # grabs list of subscriptions for this topic only
  def subscriptions
    res=nil
    params = {
      'TopicArn' => "#{@arn}",
      'Action' => 'ListSubscriptionsByTopic',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }

    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      arr = parsed_response['ListSubscriptionsByTopicResponse']['ListSubscriptionsByTopicResult']['Subscriptions']['member'] unless (parsed_response['ListSubscriptionsByTopicResponse']['ListSubscriptionsByTopicResult']['Subscriptions'].nil?)

      if !(arr.nil?) && (arr.instance_of?(Array))
       res = arr
      elsif !(arr.nil?) && (arr.instance_of?(Hash))
       # to deal with one subscription issue
       nh={}
       key = arr["SubscriptionArn"]
       arr.delete("SubscriptionArn")
       nh[key.to_s] = arr
       res = nh
      else
       res = []
      end
    end
    res
  end
  
  # The AddPermission action adds a statement to a topic's access control policy, granting access for the 
  # specified AWS accounts to the specified actions.
  
  def add_permission(opts)
    raise InvalidOptions unless ( !(opts.empty?) && opts.instance_of?(Hash) )
    res=''
    params = {
      'TopicArn' => "#{@arn}",
      'Label' => "#{opts[:label]}",
      'ActionName.member.1' => "#{opts[:action_name]}",
      'AWSAccountId.member.1' => "#{opts[:account_id]}",
      'Action' => 'AddPermission',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }
    
      generate_request(params) do |response|
        parsed_response = Crack::XML.parse(response.body)
        res = parsed_response['AddPermissionResponse']['ResponseMetadata']['RequestId']
      end
    res
  end
  
  # The RemovePermission action removes a statement from a topic's access control policy. 
  def remove_permission(label)
    raise InvalidOptions unless ( !(label.empty?) && label.instance_of?(String) )
    res=''
    params = {
      'TopicArn' => "#{@arn}",
      'Label' => "#{label}",
      'Action' => 'RemovePermission',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }
    
    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      res = parsed_response['RemovePermissionResponse']['ResponseMetadata']['RequestId']
    end
    res
  end
  
  
  def publish(msg, subject='My First Message')
    raise InvalidOptions unless ( !(msg.empty?) && msg.instance_of?(String) )
    res=''
    params = {
      'Subject' => subject,
      'TopicArn' => "#{@arn}",
      "Message" => "#{msg}",
      'Action' => 'Publish',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }

    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      res = parsed_response['PublishResponse']['PublishResult']['MessageId']
    end
    res
  end
  
  def confirm_subscription(token)
    raise InvalidOptions unless ( !(token.empty?) && token.instance_of?(String) )
    arr=[]
    params = {
      'TopicArn' => "#{@arn}",
      'Token' => "#{token}",
      'Action' => 'ConfirmSubscription',
      'SignatureMethod' => 'HmacSHA256',
      'SignatureVersion' => 2,
      'Timestamp' => Time.now.iso8601,
      'AWSAccessKeyId' => AmazeSNS.akey
    }

    generate_request(params) do |response|
      parsed_response = Crack::XML.parse(response.body)
      resp = parsed_response['ConfirmSubscriptionResponse']['ConfirmSubscriptionResult']['SubscriptionArn']
      id = parsed_response['ConfirmSubscriptionResponse']['ResponseMetadata']['RequestId']
      arr = [resp,id]
    end
    arr
  end
  
  
  
  private  
    def make_hash(arr)
      hash = arr.inject({}) do |h, v|
        (v["key"] == "Policy")? value = JSON.parse(v["value"]) : value = v["value"]
        key = v["key"].to_s
        h[key] = value
        h
      end
      hash
    end
  
  
  
end