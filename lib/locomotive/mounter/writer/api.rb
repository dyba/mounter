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
            # base_dir = File.join(File.dirname(__FILE__), kind.to_s)
            # require File.join(base_dir, 'base.rb')
            # Dir[File.join(base_dir, '*.rb')].each { |lib| require lib }
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

        class Base

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # A write may have to do some work before being launched.
          # By default, it displays to the output the resource being pushed.
          #
          def prepare
            self.output_title
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

        end

        class TranslationsWriter
          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point
          delegate :content_assets_writer, to: :runner
          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          def prepare
            #=============================================================================
            # CONSOLE OUTPUT RESPONSIBILITY
            #=============================================================================
            self.output_title

            # set the unique identifier to each local translation
            data = self.get(:translations, nil, true) || []
            data.each do |attributes|
              translation = self.translations[attributes['key']]

              translation._id = attributes['id'] if translation
            end
          end

          # Write all the translations to the remote destination
          def write
            self.translations.each do |key, translation|
              self.output_resource_op translation

              success = translation.persisted? ? self.update_translation(translation) : self.create_translation(translation)

              self.output_resource_op_status translation, success ? :success : :error
              self.flush_log_buffer
            end
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          #
          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              #=============================================================================
              # CONSOLE OUTPUT RESPONSIBILITY
              #=============================================================================
              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          #=============================================================================
          # FILE UTILITY RESPONSIBILITY
          #=============================================================================
          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          #=============================================================================
          # FILE UTILITY RESPONSIBILITY
          #=============================================================================
          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          def response_to_status(response)
            response ? :success : :error
          end

          #=============================================================================
          # FORMATTER RESPONSIBILITY
          #=============================================================================
          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          # Persist a translation by calling the API. The returned id
          # is then set to the translation itself.
          #
          # @param [ Object ] translation The translation to create
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def create_translation(translation)
            params = self.buffer_log { translation.to_params }

            # make a call to the API to create the translation, no need to set
            # the locale since it first happens for the default locale.
            response = self.post :translations, params, nil, true

            translation._id = response['id'] if response

            !response.nil?
          end

          # Update a translation by calling the API.
          #
          # @param [ Object ] translation The translation to persist
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def update_translation(translation)
            params = self.buffer_log { translation.to_params }

            # make a call to the API for the update
            response = self.put :translations, translation._id, params

            !response.nil?
          end

          # Shortcut to get all the local translations.
          #
          # @return [ Hash ] The hash whose key is the tr key and the value is translation itself
          #
          def translations
            self.mounting_point.translations
          end

        end

        class SnippetsWriter

          def prepare
            super

            # set the unique identifier to each local snippet
            self.get(:snippets, nil, true).each do |attributes|
              snippet = self.snippets[attributes['slug']]

              snippet._id = attributes['id'] if snippet
            end
          end

          # Write all the snippets to the remote destination
          def write
            self.each_locale do |locale|
              self.output_locale

              self.snippets.values.each { |snippet| self.write_snippet(snippet) }
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # A write may have to do some work before being launched.
          # By default, it displays to the output the resource being pushed.
          #
          def prepare
            self.output_title
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          # Write a snippet by calling the API.
          #
          # @param [ Object ] snippet The snippet
          #
          def write_snippet(snippet)
            locale = Locomotive::Mounter.locale

            return unless snippet.translated_in?(locale)

            self.output_resource_op snippet

            success = snippet.persisted? ? self.update_snippet(snippet) : self.create_snippet(snippet)

            self.output_resource_op_status snippet, success ? :success : :error
            self.flush_log_buffer
          end

          # Persist a snippet by calling the API. The returned id
          # is then set to the snippet itself.
          #
          # @param [ Object ] snippet The snippet to create
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def create_snippet(snippet)
            params = self.buffer_log { snippet_to_params(snippet) }

            # make a call to the API to create the snippet, no need to set
            # the locale since it first happens for the default locale.
            response = self.post :snippets, params, nil, true

            snippet._id = response['id'] if response

            !response.nil?
          end

          # Update a snippet by calling the API.
          #
          # @param [ Object ] snippet The snippet to persist
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def update_snippet(snippet)
            params = self.buffer_log { snippet_to_params(snippet) }

            locale = Locomotive::Mounter.locale

            # make a call to the API for the update
            response = self.put :snippets, snippet._id, params, locale

            !response.nil?
          end

          # Shortcut to get all the local snippets.
          #
          # @return [ Hash ] The hash whose key is the slug and the value is the snippet itself
          #
          def snippets
            self.mounting_point.snippets
          end

          # Return the parameters of a snippet sent by the API.
          #
          # @param [ Object ] snippet The snippet
          #
          # @return [ Hash ] The parameters of the page
          #
          def snippet_to_params(snippet)
            snippet.to_params.tap do |params|
              params[:template] = self.replace_content_assets!(params[:template])
            end
          end
        end 

        class SiteWriter
          attr_accessor :remote_site

          # Check if the site has to be created before.
          def prepare
            self.output_title
            self.fetch_site
          end

          # Create the site if it does not exist
          def write
            if self.site.persisted?
              self.check_locales! unless self.force? # requirements

              if self.force?
                self.update_site
              end
            else
              self.create_site
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          #
          # Create the current site in all the locales
          #
          def create_site
            # create it in the default locale
            Mounter.with_locale(self.default_locale) do
              self.output_locale

              self.output_resource_op self.site

              if (site = self.post(:sites, self.site.to_hash(false), Mounter.locale)).nil?
                raise Mounter::WriterException.new('Sorry, we are unable to create the site.')
              else
                self.site._id = site['id']
                self.output_resource_op_status self.site
              end
            end

            # update it in other locales
            self.update_site(true)
          end

          #=============================================================================
          # API CLIENT RESPONSIBILITY
          #=============================================================================
          #
          # Update the current site in all the locales
          #
          # @param [ Boolean ] exclude_current_locale Update the site for all the locales other than the default one.
          #
          def update_site(exclude_current_locale = false)
            self.each_locale do |locale|
              next if exclude_current_locale && locale.to_s == self.default_locale.to_s

              self.output_locale

              begin
                self.output_resource_op self.site

                self.put(:sites, self.site._id, self.site.to_hash(false), locale)

                self.output_resource_op_status self.site
              rescue Exception => e
                self.output_resource_op_status self.site, :error, e.message
              end
            end
          end

          def safe_attributes
            %w(id name locales timezone)
          end

          def fetch_site
            begin
              self.get(:current_site).tap do |_site|
                if _site
                  self.remote_site  = _site
                  self.site._id     = _site['id']
                end
              end
            rescue WriterException => e
              nil
            end
          end

          # To push all the other resources, the big requirement is to
          # have the same locales between the local site and the remote one.
          #
          def check_locales!
            default_locale  = self.mounting_point.default_locale.to_s
            locales         = self.site.locales.map(&:to_s)
            remote_locales  = self.remote_site['locales']
            message         = nil

            unless locales.all? { |l| remote_locales.include?(l) }
              message = "Your site locales (#{locales.join(', ')}) do not match exactly the ones of your target (#{remote_locales.join(', ')})"
            end

            if default_locale != remote_locales.first
              message = "Your default site locale (#{default_locale.inspect}) is not the same as the one of your target (#{remote_locales.first.inspect})"
            end

            if message
              self.output_resource_op self.site
              self.output_resource_op_status self.site, :error, message
              raise Mounter::WriterException.new('Use the force option in order to force your locale settings.')
            end
          end

          def has_admin_rights?
            self.get(:my_account, nil, true)['admin']
          end
        end

        # Push content assets to a remote LocomotiveCMS engine.
        #
        # The assets come from editable content blocks, for instance, in a
        # the text fields of content entries or within editable_***_text.
        # If an asset with the same filename already exists in the engine,
        # the local version will not pushed unless the :force_assets option is passed
        #
        class ContentAssetsWriter
          attr_accessor :remote_assets

          def prepare
            self.output_title
            self.remote_assets = {}

            # assign an _id to a local content type if possible
            self.get(:content_assets, nil, true).each do |attributes|
              self.remote_assets[attributes['full_filename']] = attributes
            end
          end

          def write(local_path)
            status    = :skipped
            asset     = self.build_asset(local_path)
            response  = self.remote_assets[asset.filename]

            asset._id = response['_id'] if response

            self.output_resource_op asset

            if !asset.exists?
              status = :error
            elsif asset.persisted?
              if asset.size != response['size'].to_i && self.force_assets?
                # update it
                response = self.put :content_assets, asset._id, asset.to_params
                status = self.response_to_status(response)
              end
            else
              # create it
              response = self.post :content_assets, asset.to_params, nil, true
              status = self.response_to_status(response)

              self.remote_assets[response['full_filename']] = response
            end

            self.output_resource_op_status asset, status

            [:success, :skipped].include?(status) ? response['url'] : nil
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          def build_asset(local_path)
            Locomotive::Mounter::Models::ContentAsset.new(filepath: self.absolute_path(local_path))
          end

          def force_assets?
            self.runner.parameters[:force_assets] || false
          end

          def resource_message(resource)
            "  #{super}"
          end
        end

        # Push content entries to a remote LocomotiveCMS engine.
        #
        # TODO: They get created or changed only if the
        # :data option has been passed.
        #
        class ContentEntriesWriter

          attr_accessor :with_relationships

          def prepare
            return unless self.data?

            self.output_title

            # initialize the list storing all the entries including relationships
            self.with_relationships = []

            # assign an _id to a local content entry if possible
            self.content_types.each do |slug, content_type|
              self.get("content_types/#{slug}/entries", nil, true).each do |attributes|
                content_entry = content_type.find_entry(attributes['_slug'])

                if content_entry
                  self.apply_response(content_entry, attributes)
                end
              end
            end
          end

          def write
            return unless self.data?

            self.each_locale do |locale|
              self.output_locale

              self.content_types.each do |slug, content_type|
                (content_type.entries || []).each do |entry|
                  next unless entry.translated_in?(locale)

                  if entry.persisted?
                    self.update_content_entry(slug, entry)
                  else
                    self.create_content_entry(slug, entry)
                  end

                  self.register_relationships(slug, entry)
                end # content entries
              end # content type
            end # locale

            self.persist_content_entries_with_relationships
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          # Persist a content entry by calling the API. It is enhanced then
          # by the response if no errors occured.
          #
          # @param [ String ] content_type The slug of the content type
          # @param [ Object ] content_entry The content entry to create
          #
          def create_content_entry(content_type, content_entry)
            # log before
            self.output_resource_op content_entry

            # get the params
            params = self.buffer_log { self.content_entry_to_params(content_entry) }

            # send the request
            response = self.post "content_types/#{content_type}/entries", params, nil, true

            self.apply_response(content_entry, response)

            status = self.response_to_status(response)

            # log after
            self.output_resource_op_status content_entry, status
            self.flush_log_buffer
          end

          # Update a content entry by calling the API.
          #
          # @param [ String ] content_type The slug of the content type
          # @param [ Object ] content_entry The content entry to update
          #
          def update_content_entry(content_type, content_entry)
            locale  = Locomotive::Mounter.locale

            # log before
            self.output_resource_op content_entry

            # get the params
            params = self.buffer_log { self.content_entry_to_params(content_entry) }

            # send the request
            response = self.put "content_types/#{content_type}/entries", content_entry._id, params, locale

            status = self.response_to_status(response)

            # log after
            self.output_resource_op_status content_entry, status
            self.flush_log_buffer
          end

          # Save to the remote engine the content entries owning
          # a relationship field. This can be done once ALL the
          # the content entries have been first created.
          #
          def persist_content_entries_with_relationships
            unless self.with_relationships.empty?
              self.log "\n    setting relationships for all the content entries\n"

              updates = self.content_entries_with_relationships_to_hash

              updates.each do |params|
                _id, slug = params.delete(:_id), params.delete(:slug)
                self.put "content_types/#{slug}/entries", _id, params
              end
            end
          end

          # Build hash storing the values of the relationships (belongs_to and has_many).
          # The key is the id of the content entry
          #
          # @return [ Hash ] The updates to process
          #
          def content_entries_with_relationships_to_hash
            [].tap do |updates|
              self.with_relationships.each do |(slug, content_entry)|
                changes = {}

                content_entry.content_type.fields.each do |field|
                  case field.type.to_sym
                  when :belongs_to
                    if target_id = content_entry.dynamic_getter(field.name).try(:_id)
                      changes["#{field.name}_id"] = target_id
                    end
                  when :many_to_many
                    target_ids = content_entry.dynamic_getter(field.name).map(&:_id).compact
                    unless target_ids.empty?
                      changes["#{field.name}_ids"] = target_ids
                    end
                  end
                end

                updates << { _id: content_entry._id, slug: slug }.merge(changes)
              end
            end
          end

          # Return the list of content types
          #
          # @return [ Array ] List of content types
          #
          def content_types
            self.mounting_point.content_types
          end

          # Take a content entry and get the params related to that content entry.
          #
          # @param [ Object ] entry The content entry
          #
          # @return [ Hash ] The params
          #
          def content_entry_to_params(entry)
            params = entry.to_params

            entry.each_dynamic_field do |field, value|
              unless field.is_relationship?
                case field.type.to_sym
                when :string, :text
                  params[field.name] = self.replace_content_assets!(value)
                when :file
                  if value =~ %r(^http://)
                    params[field.name] = value
                  elsif value && self.mounting_point.path
                    path = File.join(self.mounting_point.path, 'public', value)
                    params[field.name] = File.new(path)
                  end
                else
                  params[field.name] = value
                end
              end
            end

            params
          end

          # Keep track of both the content entries which
          # includes a relationship field and also
          # the selection options.
          #
          # @param [ String ] slug The slug of the content type
          # @param [ Object ] entry The content entry
          #
          def register_relationships(slug, entry)
            entry.each_dynamic_field do |field, value|
              if %w(belongs_to many_to_many).include?(field.type.to_s)
                self.with_relationships << [slug, entry]
                return # no need to go further and avoid duplicate entries
              end
            end
          end

          # Enhance the content entry with the information returned by an API call.
          #
          # @param [ Object ] content_entry The content entry instance
          # @param [ Hash ] response The API response
          #
          def apply_response(content_entry, response)
            return if content_entry.nil? || response.nil?

            content_entry._id = response['_id']
          end

        end

        class PagesWriter

          MAX_ATTEMPTS = 5

          attr_accessor :new_pages
          attr_accessor :remote_translations

          def prepare
            self.output_title

            self.new_pages, self.remote_translations = [], {}

            # set the unique identifier to each local page
            self.get(:pages, nil, true).each do |attributes|
              page = self.pages[attributes['fullpath'].dasherize]

              self.remote_translations[attributes['fullpath']] = attributes['translated_in']

              page._id = attributes['id'] if page
            end

            # assign the parent_id and the content_type_id to all the pages
            self.pages.values.each do |page|
              next if page.index_or_404?

              page.parent_id = page.parent._id
            end
          end

          # Write all the pages to the remote destination
          def write
            self.each_locale do |locale|
              self.output_locale

              done, attempts = {}, 0
              while done.size < pages.length - 1 && attempts < MAX_ATTEMPTS
                _write(pages['index'], done, done.size > 0)

                # keep track of the attempts because we don't want to get an infinite loop.
                attempts += 1
              end

              write_page(pages['404'])

              if done.size < pages.length - 1
                self.log %{Warning: NOT all the pages were pushed.\n\tCheck that the pages inheritance was done right OR that you translated all your pages.\n}.colorize(color: :red)
              end
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          def _write(page, done, already_done = false)
            if self.safely_translated?(page)
              write_page(page) unless already_done
            else
              self.output_resource_op page
              self.output_resource_op_status page, :not_translated
            end

            # mark it as done
            done[page.fullpath] = true

            # loop over its children
            (page.children || []).sort_by(&:depth_and_position).each do |child|
              layout = child.layout
              layout = page.fullpath if layout && layout == 'parent'

              if done[child.fullpath].nil? && (!layout || done[layout])
                _write(child, done)
              end
            end
          end

          def write_page(page)
            locale = Locomotive::Mounter.locale

            return unless page.translated_in?(locale)

            self.output_resource_op page

            success = page.persisted? ? self.update_page(page) : self.create_page(page)

            self.output_resource_op_status page, success ? :success : :error

            self.flush_log_buffer
          end

          # Persist a page by calling the API. The returned _id
          # is then set to the page itself.
          #
          # @param [ Object ] page The page to create
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def create_page(page)
            if !page.index_or_404? && page.parent_id.nil?
              raise Mounter::WriterException.new("We are unable to find the parent page for #{page.fullpath}")
            end

            params = self.buffer_log { page_to_params(page) }

            # make a call to the API to create the page, no need to set
            # the locale since it first happens for the default locale.
            response = self.post :pages, params, nil, true

            if response
              page._id = response['id']
              self.new_pages << page._id
            end

            !response.nil?
          end

          # Update a page by calling the API.
          #
          # @param [ Object ] page The page to persist
          #
          # @return [ Boolean ] True if the call to the API succeeded
          #
          def update_page(page)
            locale  = Locomotive::Mounter.locale

            # All the attributes of the page or just some of them
            params = self.buffer_log do
              self.page_to_params(page, self.data? || !self.already_translated?(page))
            end

            # make a call to the API for the update
            response = self.put :pages, page._id, params, locale

            !response.nil?
          end

          # Shortcut to get pages.
          #
          # @return [ Hash ] The hash whose key is the fullpath and the value is the page itself
          #
          def pages
            self.mounting_point.pages
          end

          # # Return the pages which are layouts for others.
          # # They are sorted by the depth.
          # #
          # # @return [ Array ] The list of layouts
          # #
          # def layouts
          #   self.pages.values.find_all do |page|
          #     self.safely_translated?(page) && self.is_layout?(page)
          #   end.sort { |a, b| a.depth <=> b.depth }
          # end

          # # Return the pages wich are not layouts for others.
          # # They are sorted by both the depth and the position.
          # #
          # # @return [ Array ] The list of non-layout pages
          # #
          # def other_than_layouts
          #   list = (self.pages.values - self.layouts)

          #   # get only the translated ones in the current locale
          #   list.delete_if do |page|
          #     # if (!page.parent.nil? && !page.translated_in?(self.mounting_point.default_locale)) ||
          #     #   !page.translated_in?(Locomotive::Mounter.locale)
          #     if !self.safely_translated?(page)
          #       self.output_resource_op page
          #       self.output_resource_op_status page, :not_translated
          #       true
          #     end
          #   end

          #   # sort them
          #   list.sort { |a, b| a.depth_and_position <=> b.depth_and_position }
          # end

          # Tell if the page passed in parameter has already been
          # translated on the remote engine for the locale passed
          # as the second parameter.
          #
          # @param [ Object ] page The page
          # @param [ String / Symbol ] locale The locale. Use the current locale by default
          #
          # @return [ Boolean] True if already translated.
          #
          def already_translated?(page, locale = nil)
            locale ||= Locomotive::Mounter.locale

            (@remote_translations[page.fullpath] || []).include?(locale.to_s)
          end

          # Tell if the page is correctly localized, meaning it is localized itself
          # as well as its parent.
          #
          # @param [ Object ] page The page
          #
          # @return [ Boolean] True if safely translated.
          #
          def safely_translated?(page)
            if page.parent.nil?
              page.translated_in?(Locomotive::Mounter.locale)
            else
              page.parent.translated_in?(Locomotive::Mounter.locale) &&
              page.translated_in?(Locomotive::Mounter.locale)
            end
          end

          # # Tell if the page is a real layout, which means no extends tag inside
          # # and that at least one of the other pages reference it as a parent template.
          # #
          # # @param [ Object ] page The page
          # #
          # # @return [ Boolean] True if it is a real layout.
          # #
          # def is_layout?(page)
          #   if page.is_layout?
          #     # has child(ren) extending the page itself ?
          #     return true if (page.children || []).any? { |child| child.layout == 'parent' }

          #     fullpath = page.fullpath_in_default_locale

          #     # among all the pages, is there a page extending the page itself ?
          #     self.pages.values.any? { |_page| _page.fullpath_in_default_locale != fullpath && _page.layout == fullpath }
          #   else
          #     false # extends not present
          #   end
          # end

          # Return the parameters of a page sent by the API.
          # It includes the editable_elements if the data option is enabled or
          # if the page is a new one.
          #
          # @param [ Object ] page The page
          # @param [ Boolean ] safe If true the to_safe_params is called, otherwise to_params is applied.
          #
          # @return [ Hash ] The parameters of the page
          #
          def page_to_params(page, safe = false)
            (safe ? page.to_safe_params : page.to_params).tap do |params|
              # raw template
              params[:raw_template] = self.replace_content_assets!(params[:raw_template])

              if self.data? || self.new_pages.include?(page._id)
                params[:editable_elements] = (page.editable_elements || []).map(&:to_params)
              else
                params.delete(:editable_elements)
              end

              # editable elements
              (params[:editable_elements] || []).each do |element|
                if element[:content] =~ /^\/samples\//
                  element[:source] = self.path_to_file(element.delete(:content))
                elsif element[:content] =~ %r($http://)
                  element[:source_url] = element.delete(:content)
                else
                  # string / text elements
                  element[:content] = self.replace_content_assets!(element[:content])
                end
              end
            end
          end
        end

        # Push content types to a remote LocomotiveCMS engine.
        #
        # In a first time, create the content types without any relationships fields.
        # Then, add the relationships one by one.
        #
        # If the :force option is passed, the remote fields not defined in the mounter version
        # of the content type will be destroyed when pushed. The options of
        # a select field will be pushed as well, otherwise they won't unless if
        # it is a brand new content type.
        #
        class ContentTypesWriter
          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point
          delegate :content_assets_writer, to: :runner
          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          def prepare
            self.output_title

            # assign an _id to a local content type if possible
            self.get(:content_types, nil, true).each do |attributes|
              content_type = self.content_types[attributes['slug']]

              self.apply_response(content_type, attributes)
            end
          end

          def write
            done = {}

            # first new content types
            self.not_persisted.each do |content_type|
              self.create_content_type(content_type)

              done[content_type.slug] = content_type.with_relationships? ? :todo : :done
            end

            # then update the others
            self.content_types.values.each do |content_type|
              next unless done[content_type.slug].nil?

              self.update_content_type(content_type)
            end

            # finally, update the newly created embedding a relationship field
            done.each do |slug, status|
              next if status == :done

              content_type = self.content_types[slug]

              self.update_content_type(content_type)
            end
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          # Persist a content type by calling the API. It is enhanced then
          # by the response if no errors occured.
          #
          # @param [ Object ] content_type The content type to create
          #
          def create_content_type(content_type)
            self.output_resource_op content_type

            response = self.post :content_types, content_type.to_params, nil, true

            self.apply_response(content_type, response)

            # status = self.response_to_status(response)

            self.output_resource_op_status content_type, :success
          rescue Exception => e
            self.output_resource_op_status content_type, :error, e.message
          end

          # Update a content type by calling the API.
          #
          # @param [ Object ] content_type The content type to update
          #
          def update_content_type(content_type)
            self.output_resource_op content_type

            params = self.content_type_to_params(content_type)

            # make a call to the API for the update
            self.put :content_types, content_type._id, params

            self.output_resource_op_status content_type, :success
          rescue Exception => e
            self.output_resource_op_status content_type, :error, e.message
          end

          def content_types
            self.mounting_point.content_types
          end

          # Return the content types not persisted yet.
          #
          # @return [ Array ] The list of non persisted content types.
          #
          def not_persisted
            self.content_types.values.find_all { |content_type| !content_type.persisted? }
          end

          # Enhance the content type with the information returned by an API call.
          #
          # @param [ Object ] content_type The content type instance
          # @param [ Hash ] response The API response
          #
          def apply_response(content_type, response)
            return if content_type.nil? || response.nil?

            content_type._id = response['id']
            content_type.klass_name = response['klass_name']

            response['entries_custom_fields'].each do |remote_field|
              field = content_type.find_field(remote_field['name'])
              _id   = remote_field['id']

              if field.nil?
                if self.force?
                  content_type.fields << Locomotive::Mounter::Models::ContentField.new(_id: _id, _destroy: true)
                end
              else
                field._id = _id
              end
            end
          end

          # Get the params of a content type for an update.
          # Delete the select_options unless the force flag is true.
          #
          # @param [ Object ] content_type The ContentType
          #
          # @return [ Hash ] The params of the ContentType ready to be used in the API
          #
          def content_type_to_params(content_type)
            content_type.to_params(all_fields: true).tap do |params|
              params[:entries_custom_fields].each do |attributes|
                attributes.delete(:select_options) unless self.force?
              end
            end
          end

        end

        # Push theme assets to a remote LocomotiveCMS engine.
        #
        # New assets are automatically pushed.
        # Existing ones are not pushed unless the :force option is
        # passed OR if the size of the asset (if not a javascript or stylesheet) has changed.
        #
        class ThemeAssetsWriter

          # Other local attributes
          attr_accessor :tmp_folder

          # store checksums of remote assets. needed to check if an asset has to be updated or not
          attr_accessor :checksums

          # the assets stored in the engine have the same base url
          attr_accessor :remote_base_url

          # cache the compiled theme assets to avoid to perform compilation more than once
          attr_accessor :cached_compiled_assets

          def prepare
            self.output_title

            self.checksums = {}

            self.cached_compiled_assets = {}

            # prepare the place where the assets will be stored temporarily.
            self.create_tmp_folder

            # assign an _id to a local content type if possible
            self.get(:theme_assets, nil, true).each do |attributes|
              remote_path = File.join(attributes['folder'], File.basename(attributes['local_path']))

              if theme_asset = self.theme_assets[remote_path]
                theme_asset._id                 = attributes['id']
                self.checksums[theme_asset._id] = attributes['checksum']
              end

              if remote_base_url.nil?
                attributes['url'] =~ /(.*\/sites\/[0-9a-f]+\/theme)/
                self.remote_base_url = $1
              end
            end
          end

          def write
            self.theme_assets_by_priority.each do |theme_asset|
              # track it in the logs
              self.output_resource_op theme_asset

              status  = :skipped
              errors  = []
              file    = self.build_temp_file(theme_asset)
              params  = theme_asset.to_params.merge(source: file, performing_plain_text: false)

              begin
                if theme_asset.persisted?
                  # we only update it if the size has changed or if the force option has been set.
                  if self.force? || self.theme_asset_changed?(theme_asset)
                    response  = self.put :theme_assets, theme_asset._id, params
                    status    = self.response_to_status(response)
                  else
                    status = :same
                  end
                else
                  response  = self.post :theme_assets, params, nil, true
                  status    = self.response_to_status(response)
                end
              rescue Exception => e
                if self.force?
                  status, errors = :error, e.message
                else
                  raise e
                end
              end

              # very important. we do not want a huge number of non-closed file descriptor.
              file.close

              # track the status
              self.output_resource_op_status theme_asset, status, errors
            end

            # make the stuff like they were before
            self.remove_tmp_folder
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          delegate :default_locale, :locales, :site, :sprockets, to: :mounting_point

          delegate :content_assets_writer, to: :runner

          delegate :force?, to: :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # By setting the data option to true, user content (content entries and
          # editable elements from page) can be pushed too.
          # By default, its value is false.
          #
          # @return [ Boolean ] True if the data option has been set to true
          #
          def data?
            self.runner.parameters[:data] || false
          end

          # Get remote resource(s) by the API
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The object or a collection of objects.
          #
          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              raise WriterException.new(data['error'])
            end
          end

          # Create a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          # @param [ Boolean ] raw True if the result has to be converted into object.
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def post(resource_name, params, locale = nil, raw = false)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.post("/#{resource_name}.json", query)
            data      = response.parsed_response

            if response.success?
              return data if raw
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # self.log "\n"
              # data.each do |attribute, errors|
              #   self.log "      #{attribute} => #{[*errors].join(', ')}\n".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          # Update a resource by the API.
          #
          # @param [ String ] resource_name The path to the resource (usually, the resource name)
          # @param [ String ] id The unique identifier of the resource
          # @param [ Hash ] params The attributes of the resource
          # @param [ String ] locale The locale for the request
          #
          # @return [ Object] The response of the API or nil if an error occurs
          #
          def put(resource_name, id, params, locale = nil)
            params_name = resource_name.to_s.split('/').last.singularize

            query = { query: { params_name => params } }

            query[:query][:locale] = locale if locale

            response  = Locomotive::Mounter::EngineApi.put("/#{resource_name}/#{id}.json", query)
            data      = response.parsed_response

            if response.success?
              self.raw_data_to_object(data)
            else
              message = data

              message = data.map do |attribute, errors|
                "      #{attribute} => #{[*errors].join(', ')}" #.colorize(color: :red)
              end.join("\n") if data.respond_to?(:keys)

              raise WriterException.new(message)

              # data.each do |attribute, errors|
              #   self.log "\t\t #{attribute} => #{[*errors].join(', ')}".colorize(color: :red)
              # end if data.respond_to?(:keys)
              # nil # DEBUG
            end
          end

          def safe_attributes
            %w(_id)
          end

          # Loop on each locale of the mounting point and
          # change the current locale at the same time.
          def each_locale(&block)
            self.mounting_point.locales.each do |locale|
              Locomotive::Mounter.with_locale(locale) do
                block.call(locale)
              end
            end
          end

          # Return the absolute path from a relative path
          # pointing to an asset within the public folder
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ String ] The absolute path
          #
          def absolute_path(path)
            File.join(self.mounting_point.path, 'public', path)
          end

          # Take a path and convert it to a File object if possible
          #
          # @param [ String ] path The path to the file within the public folder
          #
          # @return [ Object ] The file
          #
          def path_to_file(path)
            File.new(self.absolute_path(path))
          end

          # Take in the source the assets whose url begins by "/samples",
          # upload them to the engine and replace them by their remote url.
          #
          # @param [ String ] source The source text
          #
          # @return [ String ] The source with remote urls
          #
          def replace_content_assets!(source)
            return source if source.blank?

            source.to_s.gsub(/\/samples\/\S*\.[a-zA-Z0-9]+/) do |match|
              url = self.content_assets_writer.write(match)
              url || match
            end
          end

          protected

          def response_to_status(response)
            response ? :success : :error
          end

          # Convert raw data into the corresponding object (Page, Site, ...etc)
          #
          # @param [ Hash ] data The attributes of the object
          #
          # @return [ Object ] A new instance of the object
          #
          def raw_data_to_object(data)
            case data
            when Hash then data.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              data.map do |row|
                # puts "#{row.inspect}\n---" # DEBUG
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              data
            end
          end

          # Create the folder to store temporarily the files.
          #
          def create_tmp_folder
            self.tmp_folder = self.runner.parameters[:tmp_dir] || File.join(Dir.getwd, '.push-tmp')

            FileUtils.mkdir_p(self.tmp_folder)
          end

          # Clean the folder which had stored temporarily the files.
          #
          def remove_tmp_folder
            FileUtils.rm_rf(self.tmp_folder) if self.tmp_folder
          end

          # Build a temp file from a theme asset.
          #
          # @param [ Object ] theme_asset The theme asset
          #
          # @return [ File ] The file descriptor
          #
          def build_temp_file(theme_asset)
            path = File.join(self.tmp_folder, theme_asset.path)

            FileUtils.mkdir_p(File.dirname(path))

            File.open(path, 'w') do |file|
              file.write(self.content_of(theme_asset))
            end

            File.new(path)
          end

          # Shortcut to get all the theme assets.
          #
          # @return [ Hash ] The hash whose key is the slug and the value is the snippet itself
          #
          def theme_assets
            return @theme_assets if @theme_assets

            @theme_assets = {}.tap do |hash|
              self.mounting_point.theme_assets.each do |theme_asset|
                hash[theme_asset.path] = theme_asset
              end
            end
          end

          # List of theme assets sorted by their priority.
          #
          # @return [ Array ] Sorted list of the theme assets
          #
          def theme_assets_by_priority
            self.theme_assets.values.sort { |a, b| a.priority <=> b.priority }
          end

          # Tell if the theme_asset has been changed in order to update it
          # if so or simply skip it.
          #
          # @param [ Object ] theme_asset The theme asset
          #
          # @return [ Boolean ] True if the checksums of the local and remote files are different.
          #
          def theme_asset_changed?(theme_asset)
            content = self.content_of(theme_asset)

            if theme_asset.stylesheet_or_javascript?
              # we need to compare compiled contents (sass, coffeescript) with the right urls inside
              content = content.gsub(/[("'](\/(stylesheets|javascripts|fonts|images|media|others)\/(([^;.]+)\/)*([a-zA-Z_\-0-9]+)\.[a-z]{2,3})[)"']/) do |path|
                sanitized_path = path.gsub(/[("')]/, '').gsub(/^\//, '')
                sanitized_path = File.join(self.remote_base_url, sanitized_path)

                "#{path.first}#{sanitized_path}#{path.last}"
              end
            end

            # compare local checksum with the remote one
            Digest::MD5.hexdigest(content) != self.checksums[theme_asset._id]
          end

          # Return the content of a theme asset.
          # If the theme asset is either a stylesheet or javascript file,
          # it uses Sprockets to compile it.
          # Otherwise, it returns the raw content of the asset.
          #
          # @return [ String ] The content of the theme asset
          #
          def content_of(theme_asset)
            if theme_asset.stylesheet_or_javascript?
              if self.cached_compiled_assets[theme_asset.path].nil?
                self.cached_compiled_assets[theme_asset.path] = self.sprockets[theme_asset.short_path].to_s
              end

              self.cached_compiled_assets[theme_asset.path]
            else
              theme_asset.content
            end
          end

          def sprockets
            Locomotive::Mounter::Extensions::Sprockets.environment(self.mounting_point.path)
          end
        end
      end
    end
  end
end
