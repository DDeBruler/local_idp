require 'dotenv/load'
require 'saml_idp'
require 'erb'
require 'uri'

SamlIdp.configure do |config|
  base = "http://#{ENV['IDP_HOST']}"
  config.base_saml_location = "#{base}/saml"
  config.single_logout_service_post_location = "#{base}/saml/logout"
  config.single_logout_service_redirect_location = "#{base}/saml/logout"
  config.attribute_service_location = "#{base}/saml/attributes"
  config.single_service_post_location = "#{base}/saml/auth"


  config.name_id.formats =
    {
      email_address: -> (p) { p.to_s },
      transient: -> (p) { p.to_s },
      persistent: -> (p) { p.to_s }
    }

  sp_client_issuer = "https://#{ENV['SP_HOST']}#{ENV['SP_METADATA_PATH']}"
  service_providers = {
    sp_client_issuer => {
      metadata_url: sp_client_issuer,
      response_hosts: [ENV['SP_HOST']]
    }
  }

  # `identifier` is the entity_id or issuer of the Service Provider,
  # settings is an IncomingMetadata object which has a to_h method that needs to be persisted
  config.service_provider.metadata_persister = ->(identifier, settings) {
    fname = identifier.to_s.gsub(/\/|:/,"_")
    FileUtils.mkdir_p(File.join('.', 'cache', 'saml', 'metadata').to_s)
    File.open File.join('.', 'cache', 'saml', 'metadata', fname), "r+b" do |f|
      Marshal.dump settings.to_h, f
    end
  }

  # `identifier` is the entity_id or issuer of the Service Provider,
  # `service_provider` is a ServiceProvider object. Based on the `identifier` or the
  # `service_provider` you should return the settings.to_h from above
  config.service_provider.persisted_metadata_getter = ->(identifier, service_provider){
    fname = identifier.to_s.gsub(/\/|:/,"_")
    FileUtils.mkdir_p(File.join('.', 'cache', 'saml', 'metadata').to_s)
    full_filename = File.join('.', 'cache', 'saml', 'metadata', fname)
    if File.file?(full_filename)
      File.open full_filename, "rb" do |f|
        Marshal.load f
      end
    end
  }

  puts '----- Active Service Providers:'
  puts JSON.pretty_generate(service_providers)
  puts '-----'

  # Find ServiceProvider metadata_url and fingerprint based on our settings
  config.service_provider.finder = ->(issuer_or_entity_id) do
    service_providers[issuer_or_entity_id]
  end
end

class LocalIdp
  include SamlIdp::Controller

  def call(env)
    request = Rack::Request.new(env)

    case request.path
    when '/metadata', '/saml/metadata'
      [200, { 'content-type' => 'text/xml' }, [SamlIdp.metadata.signed]]
    when '/saml/auth'
      if request.get?
        show_login_form(request)
      else
        send_response(request)
      end
    when '/saml/logout'
    else
      not_found
    end
  end

  def show_login_form(request)
    saml_request = request.params['SAMLRequest']
    content = ERB.new(File.read('./login_form.rhtml')).result(binding)
    [200, { 'content-type' => 'text/html' }, [content]]
  end

  def send_response(request)
    @saml_request = SamlIdp::Request.from_deflated_request(request.params['SAMLRequest'])
    return not_allowed unless @saml_request.valid?

    @issuer_host = URI(@saml_request.issuer).host
    @saml_response = encode_response(request.params['email'])
    response_content = ERB.new(File.read('./authn_response.rhtml')).result(binding)
    [200, { 'content-type' => 'text/html' }, [response_content]]
  end

  def not_found
    [404, { "content-type" => "text/plain" }, ['Not Found']]
  end

  def not_allowed
    [405, { "content-type" => "text/plain" }, ['Not Allowed']]
  end
end

run LocalIdp.new
