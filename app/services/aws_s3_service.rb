# config/initializers/aws_s3_service.rb
require 'aws-sdk-s3'
require 'logger'


class AwsS3Service
  def initialize
    @s3 = Aws::S3::Resource.new(
      region: ENV['AWS_REGION'],
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
    )
    @bucket = ENV['S3_BUCKET_NAME']
    @logger = Logger.new(STDOUT)
  end

  def generate_upload_url(file_name, expires_in = 120)
    generate_signed_url(:put_object, file_name, expires_in)
  end

  def generate_view_url(file_name, expires_in = 3600)
    generate_signed_url(:get_object, file_name, expires_in, response_content_disposition: 'inline')
  end

  def generate_download_url(file_name, expires_in = 3600)
    generate_signed_url(:get_object, file_name, expires_in, response_content_disposition: 'attachment')
  end

  def delete_file(file_name)
    object = @s3.bucket(@bucket).object(file_name)

    unless object.exists?
      @logger.info("File #{file_name} does not exist in bucket #{@bucket}")
      return false
    end

    object.delete
    @logger.info("Successfully deleted file #{file_name} from bucket #{@bucket}")
    true
  rescue Aws::S3::Errors::NoSuchBucket
    @logger.error("Bucket #{@bucket} does not exist")
    raise
  rescue Aws::S3::Errors::AccessDenied
    @logger.error("Access denied to delete file #{file_name} from bucket #{@bucket}")
    raise
  rescue Aws::S3::Errors::ServiceError => e
    @logger.error("Error deleting file #{file_name} from bucket #{@bucket}: #{e.message}")
    raise
  end

  private
  def generate_signed_url(action, file_name, expires_in, options = {})
    signer = Aws::S3::Presigner.new(client: @s3.client)
    url = signer.presigned_url(action,
                               bucket: @bucket,
                               key: file_name,
                               expires_in: expires_in,
                               **options
    )
    url
  end

end

# farmer images table -> farmer_id*, image_url, agent_id*
