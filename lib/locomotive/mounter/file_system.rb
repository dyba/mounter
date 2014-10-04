module Locomotive::Mounter
  class LMReader
    def initialize(src, type)
      @src = src
    end

    def read
      file_path = File.join(@src, 'config', 'translations.yml')
      {}.tap do |translations|
        if File.exists?(file_path)
          file = File.open(file_path).read.force_encoding('utf-8')
          yaml = YAML::load(file) || [] # Account for the case when your yaml file is empty
          yaml.each do |translation|
            key, values = translation
            entry = Locomotive::Mounter::Models::Translation.new({ key: key, values: values })
            translations[key] = entry
          end
        end
      end
    end
  end

  class FileSystem
    class << self
      def read(src, type, **opts)
        LMReader.new(src, type).read
      end

      def write(dst, type, **opts)
      end
    end
  end

  class RemoteSite
    class << self
      def read(src, type, **opts)
        {"en" => "Hello", "fr" => "Salut" }
      end

      def write(dst, type, ** opts)
      end
    end
  end
end
