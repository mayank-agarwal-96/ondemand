class FilesMinController < ApplicationController

  def fs
    request.format = 'json' if request.headers['HTTP_ACCEPT'].split(',').include?('application/json')
    Rails.logger.info("FORMAT: #{request.format.inspect}")
    @path = normalized_path

    Files.raise_if_cant_access_directory_contents(@path)

    respond_to do |format|
      format.html do
        render :index
      end

      format.json do
        @files = Files.new.ls(@path.to_s)
        render :index
      end
    end
  end

  # PUT - create or update
  def update
    path = normalized_path
    AllowlistPolicy.default.validate!(path)

    Dir.mkdir path if params.include?(:dir)

    render json: {}
  rescue => e
    render json: { error_message: e.message }
  end

  private

  def normalized_path
    Pathname.new("/#{params[:filepath].chomp('/')}")
  end
end
