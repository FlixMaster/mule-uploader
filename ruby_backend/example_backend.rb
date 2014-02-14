require 'sinatra'
require 'json'
require 'ruty'


# constants
BUCKET = "bucket"
AWS_SECRET_KEY = "aws_secret_key"
AWS_ACCESS_KEY = "aws_access_key"
MIME_TYPE = "your_mime_type"

# template load location
Loader = Ruty::Loaders::Filesystem.new(:dirname => '../templates')

# the app views
class MuleBackendApp < Sinatra::Base

  # Note: This backend does not attempt to persist or retrieve
  # information about uploads.

  # Backend endpoints, as described here:
  # https://github.com/cinely/mule-uploader#set-up
  get '/aws/chunk_loaded/' do
    # Not implemented yet.
  end

  get '/aws/get_init_signature/' do
    content_type :json
    hash = S3UploadRequest.new(:type => :init, :params => params).to_h
    hash.to_json
  end

  get '/aws/get_chunk_signature/' do
    content_type :json
    hash = S3UploadRequest.new(:type => :part, :params => params).to_h
    hash.to_json
  end

  get '/aws/get_end_signature/' do
    content_type :json
    hash = S3UploadRequest.new(:type => :complete, :params => params).to_h
    hash.to_json
  end

  get '/aws/get_list_signature/' do
    content_type :json
    hash = S3UploadRequest.new(:type => :list, :params => params).to_h
    hash.to_json
  end

  get '/aws/get_delete_signature/' do
    content_type :json
    hash = S3UploadRequest.new(:type => :delete, :params => params).to_h
    hash.to_json
  end

  get '/aws/get_all_signatures/' do
    content_type :json
    list     = S3UploadRequest.new(:type => :list, :params => params)
    complete = S3UploadRequest.new(:type => :complete, :params => params)

    chunk_signatures = {}
    params[:num_chunks].to_i.times do |chunk|
      chunk_number = chunk + 1
      params[:chunk] = chunk_number
      request = S3UploadRequest.new(:type => :part, :params => params)
      chunk_signatures[chunk_number] = [request.signature, request.date]
    end

    hash = {
      :list_signature   => [list.signature, list.date],
      :end_signature    => [complete.signature, complete.date],
      :chunk_signatures => chunk_signatures
    }
    hash.to_json
  end

  # render the index.html template, giving the needed variables
  get '/' do
    data = {}
    data[:ajax_base] = "/aws"
    data[:aws_access_key] = AWS_ACCESS_KEY
    data[:bucket] = BUCKET
    data[:mime_type] = MIME_TYPE
    data[:key] = rand(10 ** 10)
    Loader.get_template('index.html').render(data)
  end

  # serve everything else as static variables
  get %r{/(.*)} do |path|
    send_file "../" + path
  end

end

# handles request signatures
class S3UploadRequest

  require 'base64'
  require 'digest'

  attr_accessor :date, :upload_id, :key, :chunk, :mime_type,
    :bucket, :aws_access_key, :signature

  def initialize(data)
    params          = data[:params]
    type            = data[:type]
    @bucket         = BUCKET
    @aws_secret_key = AWS_SECRET_KEY
    @aws_access_key = AWS_ACCESS_KEY
    @date           = Time.now.strftime("%a, %d %b %Y %X %Z")
    @upload_id      = params[:upload_id]
    @key            = params[:key]
    @chunk          = params[:chunk]
    @mime_type      = params[:mime_type] || MIME_TYPE

    if type == :init
      @signature = upload_init_signature
    elsif type == :part
      @signature = upload_part_signature
    elsif type == :complete
      @signature = upload_complete_signature
    elsif type == :list
      @signature = upload_list_signature
    elsif type == :delete
      @signature = upload_delete_signature
    else
      @signature = nil
    end
  end

  def to_h
    {
      :date      => @date,
      :bucket    => @bucket,
      :upload_id => @upload_id,
      :chunk     => @chunk,
      :mime_type => @mime_type,
      :signature => @signature
    }
  end

  private

  def upload_init_signature
    encode("POST\n\n#{@mime_type}\n\nx-amz-acl:public-read\nx-amz-date:#{@date}\n/#{@bucket}/#{@key}?uploads")
  end

  def upload_part_signature
    encode("PUT\n\n#{@mime_type}\n\nx-amz-date:#{@date}\n/#{@bucket}/#{@key}?partNumber=#{@chunk}&uploadId=#{@upload_id}")
  end

  def upload_complete_signature
    encode("POST\n\n#{@mime_type}\n\nx-amz-date:#{@date}\n/#{@bucket}/#{@key}?uploadId=#{@upload_id}")
  end

  def upload_list_signature
    encode("GET\n\n#{@mime_type}\n\nx-amz-date:#{@date}\n/#{@bucket}/#{@key}?uploadId=#{@upload_id}")
  end

  def upload_delete_signature
    encode("DELETE\n\n#{@mime_type}\n\nx-amz-date:#{@date}\n/#{@bucket}/#{@key}?uploadId=#{@upload_id}")
  end

  def encode(data)
    sha1      = OpenSSL::Digest::Digest.new('sha1')
    hmac      = OpenSSL::HMAC.digest(sha1, @aws_secret_key, data)
    Base64.encode64(hmac).gsub("\n", "")
  end
end

if __FILE__ == $0
  MuleBackendApp.run! :port => 3000
end

