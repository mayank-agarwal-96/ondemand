class FilesMinController < ApplicationController

  def fs
    request.format = 'json' if request.headers['HTTP_ACCEPT'].split(',').include?('application/json')

    @path = normalized_path

    Files.raise_if_cant_access_directory_contents(@path)

    respond_to do |format|
      Rails.logger.info("FORMAT: #{format.inspect}")
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

    if params.include?(:dir)
      Dir.mkdir path
    elsif params.include?(:file)
      FileUtils.mv params[:file].tempfile, path
    elsif params.include?(:touch)
      FileUtils.touch path
    else
      content = request.body.read

      # forcing utf-8 because File.write seems to require it. request bodies are
      # in ASCII-8BIT and need to be re encoded otherwise errors are thrown.
      # see test cases for plain text, utf-8 text, images and binary files
      content.force_encoding('UTF-8')

      File.write(path, content)
    end

    render json: {}
  rescue => e
    render json: { error_message: e.message }
  end

  private

  def normalized_path
    Pathname.new("/#{params[:filepath].chomp('/')}")
  end
end
