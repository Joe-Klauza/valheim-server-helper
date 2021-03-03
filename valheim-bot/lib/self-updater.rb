require 'fileutils'
require 'json'
require 'net/http'
require 'open-uri'
require 'pathname'
require 'zip'

class SelfUpdater
    include Logging
    REPO_ROOT_DIR = File.join __dir__, '..', '..'
    UPDATE_ZIP =  File.join REPO_ROOT_DIR, 'update.zip'
    IGNORE_FILES = [
    ]

    def self.download(url, path)
        FileUtils.mkdir_p(File.dirname path)
        parsed = URI.parse(url)
        File.write(path, parsed.read)
    end

    def self.update_to_latest(only_files_in_dir: nil)
        logger.info("Determining latest release")
        releases = JSON.parse Net::HTTP.get(URI('https://api.github.com/repos/Joe-Klauza/valheim-server-helper/releases'))
        latest = releases.first
        version = latest['name']
        zip_download_url = latest['zipball_url']
        logger.info("Downloading #{version}: #{zip_download_url}")
        Dir.chdir REPO_ROOT_DIR do
            SelfUpdater.download(zip_download_url, UPDATE_ZIP)
            logger.info("Downloaded #{version} to update.zip")
            logger.info("Extracting update.zip")
            Zip::File.open(UPDATE_ZIP) do |zip_file|
                zip_file.select(&:file?).each do |f|
                    filename = File.join Pathname(f.name).each_filename.to_a[1..] # Ignore project dir
                    filepath = File.expand_path File.join(REPO_ROOT_DIR, filename)
                    if only_files_in_dir
                        next unless filepath.split(File::Separator).include?(only_files_in_dir)
                    end
                    next if IGNORE_FILES.include?(filename) || IGNORE_FILES.include?(filepath)
                    FileUtils.mkdir_p(File.dirname filepath)
                    logger.debug("Overwriting #{filepath} with #{f}")
                    zip_file.extract(f, filepath) { true } # Overwrite
                end
            end
        end
        logger.info("Extracted update.zip")
        logger.info("Deleting update.zip")
        FileUtils.rm(UPDATE_ZIP)
        logger.info("Deleted update.zip")
        version
    rescue => e
        logger.error(e)
        raise "Failed to update. (#{e.class}): #{e.message}"
    end
end
