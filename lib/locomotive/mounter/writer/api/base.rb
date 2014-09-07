module Locomotive
  module Mounter
    module Writer
      module Api

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
            (self.get(:translations, nil, true) || []).each do |attributes|
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
      end # Api
    end # Writer
  end # Mounter
end # Locomotive
