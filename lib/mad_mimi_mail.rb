require 'madmimi'
require 'action_mailer'

class MadMimiMail

  attr_accessor :settings
  cattr_accessor :options
  
  def self.options
    @@options ||= {}
  end
  
  def initialize(options)
    check_api_settings

    @_mimi = MadMimi.new(api_settings[:email], api_settings[:api_key])
    self.settings = options
  end

  def deliver!(mail)
    mail_settings = { :recipients => recipients(mail) }
    
    mail_settings.merge(:raw_html => mail.html_part.body) if mail.html_part
    mail_settings.merge(:raw_plain_text => mail.text_part.body) if mail.text_part
    
    [:from, :subject, :promotion_name, :raw_yaml, :bcc].inject(mail_settings) do |hash, header_name|
      if self.class.options.has_key?(header_name)
        hash.merge!(header_name => self.class.options[header_name])
      else
        hash.merge!(header_name => extract_header(mail, header_name))
      end
    end
    
    mail_settings = mail_settings.merge(self.settings)
    
    puts mail_settings.inspect
    
    body = mail_settings.delete(:raw_yaml)
    
    mimi_response = @_mimi.send_mail(mail_settings, body)

    #FIXME: (Dirty Hack) Need access to the transaction id from the api call, so
    # we're defining a new method #transaction_id onto the mail object containing the integer value
    # DANGER, DANGER! METAPROGRAMMING!
    transaction_id = mimi_response.to_i
    add_transaction_id_attribute(mail, transaction_id)

    #if the message isn't an integer, something went wrong and we want to capture it in the mail errors
    mail.errors << mimi_response if transaction_id.zero? 
  end

  private
  
  def recipients(mail)
    if self.class.options.has_key?(:to)
      self.class.options[:to]
    else
      extract_header(mail, :to)
    end
  end

  def check_api_settings
    raise <<-ERROR_STRING.gsub(/^\s+/,'') unless has_required_api_settings?
      Please configure mad_mimi_mailer with your API settings for MadMimi:

      MadMimiMail::Configuration.api_settings = {:email => "<madmimi email>", :api_key => "<madmimi api key>"}
    ERROR_STRING
  end

  def api_settings
    Configuration.api_settings
  end

  def has_required_api_settings?
    api_settings && [:email, :api_key].all? {|k| api_settings.has_key?(k) }
  end

  def extract_header(mail, header)
    if mail[header].to_s.blank?
      nil
    else
      mail[header].to_s
    end
  end

  def add_transaction_id_attribute(object, transaction_id)
    eigenclass = class << object; self; end
    eigenclass.class_eval do
      define_method(:transaction_id) { transaction_id }
    end
  end
end

class MadMimiMail
  module Configuration
    class << self
      attr_accessor :api_settings
    end
  end
end

ActionMailer::Base.add_delivery_method :madmimi, MadMimiMail
