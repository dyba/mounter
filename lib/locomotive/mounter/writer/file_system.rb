module Locomotive
  module Mounter
    module Writer

      module FileSystem

        # Build a singleton instance of the Runner class.
        #
        # @return [ Object ] A singleton instance of the Runner class
        #
        def self.instance
          @@instance ||= Runner.new(:file_system)
        end

        class Runner

          attr_accessor :target_path

          # Check the existence of the target_path parameter
          #
          def prepare
            self.target_path = parameters[:target_path]

            if self.target_path.blank?
             raise Locomotive::Mounter::WriterException.new('target_path is required')
           end
          end

          # List of all the writers
          #
          # @return [ Array ] List of the writer classes
          #
          def writers
            [SiteWriter, SnippetsWriter, ContentTypesWriter, ContentEntriesWriter, PagesWriter, ThemeAssetsWriter, ContentAssetsWriter, TranslationsWriter]
          end

          attr_accessor :kind, :parameters, :mounting_point

          def initialize(kind)
            self.kind = kind

            # avoid to load all the ruby files at the startup, only when we need it
            base_dir = File.join(File.dirname(__FILE__), kind.to_s)
            require File.join(base_dir, 'base.rb')
            Dir[File.join(base_dir, '*.rb')].each { |lib| require lib }
          end

          # Write the data of a mounting point instance to a target folder
          #
          # @param [ Hash ] parameters The parameters. It should contain the mounting_point and target_path keys.
          #
          def run!(parameters = {})
            self.parameters = parameters.symbolize_keys

            self.mounting_point = self.parameters.delete(:mounting_point)

            self.prepare

            self.write_all
          end

          # Execute all the writers
          def write_all
            only = parameters[:only].try(:map) do |name|
              "#{name}_writer".camelize
            end.try(:insert, 0, 'SiteWriter')

            self.writers.each do |klass|
              next if only && !only.include?(klass.name.demodulize)
              writer = klass.new(self.mounting_point, self)
              writer.prepare
              writer.write
            end
          end

          # By setting the force option to true, some resources (site, content assets, ...etc)
          # may overide the content of the remote engine during the push operation.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the force option has been set to true
          #
          def force?
            self.parameters[:force] || false
          end

        end


      end

    end
  end
end
