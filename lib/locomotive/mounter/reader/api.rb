module Locomotive
  module Mounter
    module Reader
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
            credentials = self.parameters.select { |k, _| %w(uri email password api_key).include?(k.to_s) }
            self.uri    = credentials[:uri]

            begin
              Locomotive::Mounter::EngineApi.set_token(credentials)
            rescue Exception => e
              raise Locomotive::Mounter::ReaderException.new("unable to get an API token: #{e.message}")
            end
          end

          # Ordered list of atomic readers
          #
          # @return [ Array ] List of classes
          #
          def readers
            [SiteReader, ContentAssetsReader, SnippetsReader, ContentTypesReader, ContentEntriesReader, PagesReader, ThemeAssetsReader, TranslationsReader]
          end

          # Return the uri with the scheme (http:// or https://)
          #
          # @return [ String ] The uri starting by http:// or https://
          #
          def uri_with_scheme
            self.uri =~ /^http/ ? self.uri : "http://#{self.uri}"
          end

          # Return the base uri with the scheme ((http:// or https://)) and without the path (/locomotive/...)
          #
          # @return [ String ] The uri starting by http:// or https:// and without the path
          #
          def base_uri_with_scheme
            self.uri_with_scheme.to_s[/^https?:\/\/[^\/]+/] || self.uri_with_scheme
          end

          attr_accessor :kind, :parameters, :mounting_point

          def initialize(kind)
            self.kind = kind

             # avoid to load all the ruby files at the startup, only when we need it
             # base_dir = File.join(File.dirname(__FILE__), kind.to_s)
             # require File.join(base_dir, 'base.rb') # This is a hinderance right now
             # Dir[File.join(base_dir, '*.rb')].each { |lib| require lib } # So is this
          end

          # Read the content of a site (pages, snippets, ...etc) and create the corresponding mounting point.
          #
          # @param [ Hash ] parameters The parameters.
          #
          # @return [ Object ] The mounting point object storing all the information about the site
          #
          def run!(parameters = {})
            self.parameters = parameters.symbolize_keys

            self.prepare

            self.build_mounting_point
          end

          # Reload with the same origin parameters a part of a site from a list of
          # resources each described by a simple name (site, pages, ...etc) taken from
          # the corresponding reader class name.
          #
          # @param [ Array/ String ] list An array of resource(s) or just the resource
          #
          def reload(*list)
            Locomotive::Mounter.with_locale(self.mounting_point.default_locale) do
              [*list].flatten.each do |name|
                reader_name = "#{name.to_s.camelize}Reader"

                reader = self.readers.detect do |_reader|
                  _reader.name.demodulize == reader_name
                end

                if reader
                  self.mounting_point.register_resource(name, reader.new(self).read)
                end
              end
            end
          end

          protected

          def build_mounting_point
            Locomotive::Mounter::MountingPoint.new.tap do |mounting_point|
              self.mounting_point = mounting_point

              self.readers.each do |reader|
                name = reader.name.gsub(/(Reader)$/, '').demodulize.underscore

                self.mounting_point.register_resource(name, reader.new(self).read)
              end

              if self.respond_to?(:path)
                self.mounting_point.path = self.path
              end
            end
          end
        end

        # ContentAssetsReader
        #
        #
        class ContentAssetsReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            # Why do we worry about the locale here?
            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            # Formatting responsibilities
            #
            # TODO: delegate to another class to handle formatting
            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build a new content asset from an url and a folder and add it
          # to the global list of the content assets.
          #
          # @param [ String ] url The url of the content asset.
          # @param [ String ] folder The folder of the content asset (optional).
          #
          # @return [ String ] The local path (not absolute) of the content asset.
          #
          def add_content_asset(url, folder = nil)
            content_assets = self.mounting_point.resources[:content_assets]

            if (url =~ /^https?:\/\//).nil?
              url = URI.join(self.uri_with_scheme, url)
            else
              url = URI(url)
            end

            asset = Locomotive::Mounter::Models::ContentAsset.new(uri: url, folder: folder)

            content_assets[url.path] = asset

            asset.local_filepath
          end

          # Build the list of content assets from the public folder with eager loading.
          #
          # @return [ Array ] The cached list of theme assets
          #
          def read
            self.output_title(:pulling)

            self.get(:content_assets).each do |attributes|
              url = attributes.delete('url')

              attributes['folder']  = 'samples/assets'
              attributes['uri']     = URI(url =~ /^https?:\/\// ? url : "#{self.base_uri_with_scheme}#{url}")

              self.items[url] = Locomotive::Mounter::Models::ContentAsset.new(attributes)
            end

            self.items
          end

          protected

          def safe_attributes
            %w(_id url created_at updated_at)
          end

        end # ContentAssetsReader

        # ContentEntriesReader
        #
        #
        class ContentEntriesReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items
          attr_accessor :ids, :relationships

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
            self.ids, self.relationships = {}, []
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            # Why do we worry about the locale here?
            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            # Formatting responsibilities
            #
            # TODO: delegate to another class to handle formatting
            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          def add_content_asset(url, folder = nil)
            content_assets = self.mounting_point.resources[:content_assets]

            if (url =~ /^https?:\/\//).nil?
              url = URI.join(self.uri_with_scheme, url)
            else
              url = URI(url)
            end

            asset = Locomotive::Mounter::Models::ContentAsset.new(uri: url, folder: folder)

            content_assets[url.path] = asset

            asset.local_filepath
          end

          # Build the list of content types from the folder on the file system.
          #
          # @return [ Array ] The un-ordered list of content types
          #
          def read
            self.output_title(:pulling)

            self.fetch

            self.items
          end

          protected

          def fetch
            self.mounting_point.content_types.each do |slug, content_type|
              entries = self.get("content_types/#{slug}/entries", nil, true)

              entries.each do |attributes|
                locales = attributes.delete('translated_in') || []

                entry = self.add(content_type, attributes)

                # get all the translated versions
                locales.each do |locale|
                  _attributes = self.get("content_types/#{slug}/entries/#{entry._id}", locale, true)

                  Locomotive::Mounter.with_locale(locale) do
                    self.filter_attributes(content_type, _attributes).each do |key, value|
                      entry.send(:"#{key}=", value)
                    end
                  end
                end
              end
            end
          end

          # Add a content entry for a content type.
          #
          # @param [ Object ] content_type The content type
          # @param [ Hash ] attributes The attributes of the content entry
          #
          # @return [ Object] The newly created content entry
          #
          def add(content_type, attributes)
            _attributes = self.filter_attributes(content_type, attributes)

            entry = content_type.build_entry(_attributes)

            key = File.join(content_type.slug, entry._slug)

            self.items[key] = self.ids[entry._id] = entry
          end

          # Filter the attributes coming directly from an API call.
          #
          # @param [ Object ] content_type The content type
          # @param [ Hash ] attributes The attributes of the content entry
          #
          # @return [ Object] The attributes understandable by the content entry
          #
          def filter_attributes(content_type, original_attributes)
            attributes = original_attributes.clone.keep_if { |k, v| %w(_id _slug seo_title meta_keywords meta_description _position _visible created_at updated_at).include?(k) }

            content_type.fields.each do |field|
              value = (case field.type
              when
                original_attributes[field.name]
              when :text
                replace_urls_by_content_assets(original_attributes[field.name])
              when :select
                field.find_select_option(original_attributes[field.name]).try(:name)
              when :date
                original_attributes["formatted_#{field.name}"]
              when :file
                retrieve_file_path(content_type, field, original_attributes)
              when :has_many
                nil
              else
                # :string, :boolean, :email, :integer, :float, :tags
                original_attributes[field.name]
              end)

              attributes[field.name] = value unless value.nil?
            end

            attributes
          end

          # For a given content, parse it and replace all the urls from content assets
          # by their corresponding locale ones.
          #
          # @param [ String ] content The content to parse
          #
          # @return [ String ] The content with local urls
          #
          def replace_urls_by_content_assets(content)
            return "" unless content
            self.mounting_point.content_assets.each do |path, asset|
              content.gsub!(path, asset.local_filepath)
            end
            content
          end

          def retrieve_file_path(content_type, field, attributes)
            value = attributes[field.name]

            return nil if value.blank?

            base_folder = File.join('/', 'samples', content_type.slug, attributes['_slug'])

            if value.is_a?(Hash)
              {}.tap do |translations|
                value.each do |locale, url|
                  translations[locale] = self.add_content_asset(url, File.join(base_folder, locale))
                end
              end
            else
              self.add_content_asset(value, base_folder)
            end
          end

        end # ContentEntriesReader

        class ContentTypesReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build the list of content types from the folder in the file system.
          #
          # @return [ Array ] The un-ordered list of content types
          #
          def read
            self.output_title(:pulling)

            self.fetch

            self.enable_relationships

            self.items
          end

          protected

          def fetch
            self.get(:content_types).each do |attributes|
              self.add(attributes)
            end
          end

          # Add a new content type in the global hash of content types.
          # If the content type exists, it returns it.
          #
          # @param [ Hash ] attributes The attributes of the content type
          #
          # @return [ Object ] A newly created content type or the existing one
          #
          def add(attributes)
            slug = attributes['slug']

            attributes.delete('entries_custom_fields').each do |_attributes|
              _attributes = _attributes.delete_if { |k, v| v.blank? || %w(id updated_at created_at).include?(k) }

              # TODO: select options

              (attributes['fields'] ||= []) << _attributes
            end

            unless self.items.key?(slug)
              self.items[slug] = Locomotive::Mounter::Models::ContentType.new(attributes)
            end

            self.items[slug]
          end

          # Make sure that each "relationship" field of a content type is
          # correctly connected to the target content type.
          def enable_relationships
            self.items.each do |_, content_type|
              content_type.fields.find_all(&:is_relationship?).each do |field|
                # look for the target content type from its slug
                field.class_name  = field.class_slug
                field.klass       = self.items[field.class_slug]
              end
            end
          end

          def safe_attributes
            %w(name slug description order_by order_direction label_field_name group_by_field_name public_submission_accounts entries_custom_fields klass_name created_at updated_at)
          end

        end # ContentTypesReader

        class PagesReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items
          attr_accessor :pages

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.pages = {}
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build a new content asset from an url and a folder and add it
          # to the global list of the content assets.
          #
          # @param [ String ] url The url of the content asset.
          # @param [ String ] folder The folder of the content asset (optional).
          #
          # @return [ String ] The local path (not absolute) of the content asset.
          #
          def add_content_asset(url, folder = nil)
            content_assets = self.mounting_point.resources[:content_assets]

            if (url =~ /^https?:\/\//).nil?
              url = URI.join(self.uri_with_scheme, url)
            else
              url = URI(url)
            end

            asset = Locomotive::Mounter::Models::ContentAsset.new(uri: url, folder: folder)

            content_assets[url.path] = asset

            asset.local_filepath
          end


          # Build the tree of pages based on the filesystem structure
          #
          # @return [ Hash ] The pages organized as a Hash (using the fullpath as the key)
          #
          def read
            self.output_title(:pulling)

            self.fetch

            index = self.pages['index']

            self.build_relationships(index, self.pages_to_list)

            # Locomotive::Mounter.with_locale(:en) { self.to_s } # DEBUG

            # self.to_s

            self.pages
          end

          protected

          # Create a ordered list of pages from the Hash
          #
          # @return [ Array ] An ordered list of pages
          #
          def pages_to_list
            # sort by fullpath first
            list = self.pages.values.sort { |a, b| a.fullpath <=> b.fullpath }
            # sort finally by depth
            list.sort { |a, b| a.depth <=> b.depth }
          end

          def build_relationships(parent, list)
            list.dup.each do |page|
              next unless self.is_subpage_of?(page, parent)

              # attach the page to the parent (order by position), also set the parent
              parent.add_child(page)

              # localize the fullpath in all the locales
              page.localize_fullpath

              # remove the page from the list
              list.delete(page)

              # go under
              self.build_relationships(page, list)
            end
          end

          # Record pages found in file system
          def fetch
            self.get(:pages).each do |attributes|
              page = self.add(attributes['fullpath'], attributes)

              self.mounting_point.locales[1..-1].each do |locale|
                # if not translated, no need to make an api call for that locale
                next unless page.translated_in?(locale)

                Locomotive::Mounter.with_locale(locale) do
                  localized_attributes = self.get("pages/#{page._id}", locale)

                  # remove useless non localized attributes
                  localized_attributes.delete('target_klass_slug')

                  # isolate the editable elements
                  editable_elements = self.filter_editable_elements(localized_attributes.delete('editable_elements'))

                  page.attributes = localized_attributes

                  page.set_editable_elements(editable_elements)
                end
              end
            end
          end

          # Add a new page in the global hash of pages.
          # If the page exists, then do nothing.
          #
          # @param [ String ] fullpath The fullpath used as the key for the hash
          # @param [ Hash ] attributes The attributes of the new page
          #
          # @return [ Object ] A newly created page or the existing one
          #
          def add(fullpath, attributes = {})
            unless self.pages.key?(fullpath)
              # editable elements
              editable_elements = self.filter_editable_elements(attributes.delete('editable_elements'))

              # content type
              if content_type_slug = attributes.delete('target_klass_slug')
                attributes['content_type'] = self.mounting_point.content_types[content_type_slug] #.values.find { |ct| ct._id == content_type_id }
              end

              self.pages[fullpath] = Locomotive::Mounter::Models::Page.new(attributes)

              self.pages[fullpath].set_editable_elements(editable_elements)
            end

            self.pages[fullpath]
          end

          # Tell is a page described is a sub page of a parent page
          #
          # @param [ Object ] page The full path of the page to test
          # @param [ Object ] parent The full path of the parent page
          #
          # @return [ Boolean] True if the page is a sub page of the parent one
          #
          def is_subpage_of?(page, parent)
            return false if page.index_or_404?

            if page.parent_id # only in the new version of the engine
              return page.parent_id == parent._id
            end

            if parent.fullpath == 'index' && page.fullpath.split('/').size == 1
              return true
            end

            File.dirname(page.fullpath.dasherize) == parent.fullpath.dasherize
          end

          # Only keep the minimal attributes from a list of
          # editable elements hashes. It also replaces the url to
          # content assets by their corresponding local ones.
          #
          # @param [ Array ] list The list of the editable elements with all the attributes
          #
          # @return [ Array ] The list of editable elements with the right attributes
          #
          def filter_editable_elements(list)
            list.map do |attributes|
              type = attributes['type']
              attributes.keep_if { |k, _| %w(_id block slug content).include?(k) }.tap do |hash|
                unless hash['content'].blank?
                  if type == 'EditableFile'
                    hash['content'] = self.add_content_asset(hash['content'], '/samples/pages')
                  else
                    self.mounting_point.content_assets.each do |path, asset|
                      hash['content'].gsub!(/(http:\/\/[^\/]*)?#{path}/, asset.local_filepath)
                    end
                  end
                end
              end
            end
          end

          def safe_attributes
            %w(_id title slug handle fullpath translated_in
            parent_id target_klass_slug
            published listed templatized editable_elements
            redirect_url cache_strategy response_type position
            seo_title meta_keywords meta_description raw_template
            created_at updated_at)
          end

          # Output simply the tree structure of the pages.
          #
          # Note: only for debug purpose
          #
          def to_s(page = nil)
            page ||= self.pages['index']

            return unless page.translated_in?(Locomotive::Mounter.locale)

            puts "#{"  " * (page.try(:depth) + 1)} #{page.fullpath.inspect} (#{page.title}, position=#{page.position})"

            (page.children || []).each { |child| self.to_s(child) }
          end

        end # PagesReader

        class SiteReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          def read
            self.output_title(:pulling)

            # get the site from the API
            site = self.get(:current_site)

            # set the default locale first
            Locomotive::Mounter.locale = site['locales'].first.to_sym

            Locomotive::Mounter::Models::Site.new(site).tap do |site|
              # fetch the information in other locales
              site.locales[1..-1].each do |locale|
                Locomotive::Mounter.with_locale(locale) do
                  self.get(:current_site, locale).each do |name, value|
                    next unless %w(seo_title meta_keywords meta_description).include?(name)
                    site.send(:"#{name}=", value)
                  end
                end
              end

              # set the time zone for the next Time operations (UTC by default)
              Time.zone = ActiveSupport::TimeZone.new(site.timezone || 'UTC')
            end
          end

          def safe_attributes
            %w(name locales seo_title meta_keywords meta_description domains subdomain timezone created_at updated_at)
          end

        end # SiteReader

        # SnippetsReader
        #
        #
        class SnippetsReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build the list of snippets from the folder on the file system.
          #
          # @return [ Array ] The un-ordered list of snippets
          #
          def read
            self.output_title(:pulling)

            self.fetch

            self.items
          end

          protected

          # Record snippets found in file system
          def fetch
            self.get(:snippets).each do |attributes|
              snippet = self.add(attributes.delete('slug'), attributes)

              self.mounting_point.locales[1..-1].each do |locale|
                Locomotive::Mounter.with_locale(locale) do
                  localized_attributes = self.get("snippets/#{snippet._id}", locale)
                  snippet.attributes = localized_attributes
                end
              end
            end
          end

          # Add a new snippet in the global hash of snippets.
          # If the snippet exists, it returns it.

          # @param [ String ] slug The slug of the snippet
          # @param [ Hash ] attributes The attributes of the snippet
          #
          # @return [ Object ] A newly created snippet or the existing one
          #
          def add(slug, attributes)
            unless self.items.key?(slug)
              self.items[slug] = Locomotive::Mounter::Models::Snippet.new(attributes)
            end

            self.items[slug]
          end

          def safe_attributes
            %w(_id name slug template created_at updated_at)
          end

        end # SnippetsReader

        # ThemeAssetsReader
        #
        #
        class ThemeAssetsReader
          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items = []
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build the list of theme assets from the public folder with eager loading.
          #
          # @return [ Array ] The cached list of theme assets
          #
          def read
            self.output_title(:pulling)

            self.items = self.get(:theme_assets).map do |attributes|
              url = attributes.delete('url')

              attributes['uri'] = URI(url =~ /^https?:\/\// ? url : "#{self.base_uri_with_scheme}#{url}")

              Locomotive::Mounter::Models::ThemeAsset.new(attributes)
            end
          end

          protected

          def safe_attributes
            %w(_id folder url created_at updated_at)
          end

        end # ThemeAssetsReader

        # TranslationsReader
        #
        #
        class TranslationsReader

          include Locomotive::Mounter::Utils::Output

          attr_accessor :runner, :items

          delegate :uri, :uri_with_scheme, :base_uri_with_scheme, to: :runner
          delegate :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def get(resource_name, locale = nil, raw = false)
            params = { query: {} }

            params[:query][:locale] = locale if locale

            response = Locomotive::Mounter::EngineApi.get("/#{resource_name}.json", params).parsed_response

            return response if raw

            case response
            when Hash then response.to_hash.delete_if { |k, _| !self.safe_attributes.include?(k) }
            when Array
              response.map do |row|
                row.delete_if { |k, _| !self.safe_attributes.include?(k) }
              end
            else
              response
            end
          end

          # Build the list of translations
          #
          # @return [ Array ] The cached list of theme assets
          #
          def read
            self.output_title(:pulling)

            self.items = get(:translations).each_with_object({}) do |attributes,hash|
              hash[attributes['key']] = Locomotive::Mounter::Models::Translation.new(attributes)
            end
          end

          protected

          def safe_attributes
            %w[_id key values created_at updated_at]
          end
        end # TranslationsReader
      end # Api
    end # Reader
  end # Mounter
end # Locomotive
