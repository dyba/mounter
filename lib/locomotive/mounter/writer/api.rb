module Locomotive
  module Mounter
    module Writer
      module Api

        # Build a singleton instance of the Runner class.
        #
        # @return [ Object ] A singleton instance of the Runner class
        #
        def self.instance
          @@instance ||= Runner.new(:api)
        end

        def self.teardown
          @@instance = nil
        end

        class Runner

          attr_accessor :uri

          # Call the LocomotiveCMS engine to get a token for
          # the next API calls
          def prepare
            # by default, do not push data (content entries and editable elements)
            self.parameters[:data] ||= false

            credentials = self.parameters.select { |k, _| %w(uri email password api_key).include?(k.to_s) }
            self.uri    = credentials[:uri]

            begin
              Locomotive::Mounter::EngineApi.set_token(credentials)
            rescue Exception => e
              raise Locomotive::Mounter::WriterException.new("unable to get an API token: #{e.message}")
            end
          end

          # Ordered list of atomic writers
          #
          # @return [ Array ] List of classes
          #
          def writers
            [SiteWriter, SnippetsWriter, ContentTypesWriter, ContentEntriesWriter, TranslationsWriter, PagesWriter, ThemeAssetsWriter].tap do |_writers|
              # modify the list depending on the parameters
              if self.parameters
                if self.parameters[:data] == false && !(self.parameters[:only].try(:include?, 'content_entries'))
                  _writers.delete(ContentEntriesWriter)
                end

                if self.parameters[:translations] == false && !(self.parameters[:only].try(:include?, 'translations'))
                  _writers.delete(TranslationsWriter)
                end
              end
            end
          end

          # Get the writer to push content assets
          #
          # @return [ Object ] A memoized instance of the content assets writer
          #
          def content_assets_writer
            @content_assets_writer ||= ContentAssetsWriter.new(self.mounting_point, self).tap do |writer|
              writer.prepare
            end
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
