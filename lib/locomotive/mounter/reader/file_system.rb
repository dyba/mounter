require 'singleton'

module Locomotive
  module Mounter
    module Reader
      module FileSystem

        # Build a singleton instance of the Runner class.
        #
        # @return [ Object ] A singleton instance of the Runner class
        #
        def self.instance
          @@instance ||= Runner.new(:file_system)
        end

        class Runner
          attr_accessor :path
          attr_accessor :kind, :parameters, :mounting_point

          def initialize(kind)
            self.kind = kind

             # avoid to load all the ruby files at the startup, only when we need it
             # base_dir = File.join(File.dirname(__FILE__), kind.to_s)
             # require File.join(base_dir, 'base.rb') # This is a hinderance right now
             # Dir[File.join(base_dir, '*.rb')].each { |lib| require lib } # So is this
          end

          # Compass is required
          def prepare
            self.path = parameters.delete(:path)

            if self.path.blank? || !File.exists?(self.path)
              raise Locomotive::Mounter::ReaderException.new('path is required and must exist')
            end

            # TODO: Steam should deal with that
            Locomotive::Mounter::Extensions::Compass.configure(self.path)
          end

          # Ordered list of atomic readers
          #
          # @return [ Array ] List of classes
          #
          def readers
            [SiteReader, ContentTypesReader, PagesReader, SnippetsReader, ContentEntriesReader, ContentAssetsReader, ThemeAssetsReader, TranslationsReader]
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

              # WHY ???
              #
              # We are now bound requiring our classes to be named with the Reader suffix.
              # This places unnecessary constraints in the design of our application
              #
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

        module YamlHelpers
          # Take the list of options described in the YAML file
          # and convert it into a nice array of hashes
          #
          # @params [ Array ] options The list of raw options
          #
          # @return [ Array ] The sanitized list of options
          #
          def sanitize_select_options(options)
            [].tap do |array|
              options.each_with_index do |object, position|
                array << { name: object, position: position }
              end
            end
          end

          # Open a YAML file and returns the content of the file
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ Object ] The content of the file
          #
          def read_yaml(filepath)
            file = File.open(filepath).read.force_encoding('utf-8')
            YAML::load(file)
          end
        end

        # Holds all the reader logic for every Reader class
        #
        #
        class Reader
          include Singleton
          include YamlHelpers

          def for_content_types(runner, items, mounting_point)
            # We use the runner to retrieve the path
            root_dir = File.join(runner.path, 'app', 'content_types')

            Dir.glob(File.join(root_dir, '*.yml')).each do |filepath|
              attributes = read_yaml(filepath)

              # Formerly the add method
              #
              # Add a new content type in the global hash of content types.
              # If the content type exists, it returns it.
              #
              # @param [ Hash ] attributes The attributes of the content type
              #
              # @return [ Object ] A newly created content type or the existing one
              #
              slug = attributes['slug']

              # TODO: raise an error if no fields

              attributes.delete('fields').each_with_index do |_attributes, index|
                hash = { name: _attributes.keys.first, position: index }.merge(_attributes.values.first)

                if options = hash.delete('select_options')
                  hash['select_options'] = sanitize_select_options(options)
                end

                (attributes['fields'] ||= []) << hash
              end

              attributes[:mounting_point] = mounting_point

              unless items.key?(slug)
                items[slug] = Locomotive::Mounter::Models::ContentType.new(attributes)
              end

              items[slug]
            end

            items
          end

          def for_site(runner)
            # We only use the runner to retrieve the path
            path = runner.path
            config_path = File.join(path, 'config', 'site.yml')

            site = read_yaml(config_path)

            # set the default locale first
            begin
              Locomotive::Mounter.locale = site['locales'].first.to_sym
            rescue
              Locomotive::Mounter.locale
            end

            Locomotive::Mounter::Models::Site.new(site).tap do |_site|
              # set the time zone for the next Time operations (UTC by default)
              Time.zone = ActiveSupport::TimeZone.new(_site.timezone || 'UTC')
            end
          end

          def for_snippets(runner, items)
            root_dir = File.join(runner.path, 'app', 'views', 'snippets')

            Dir.glob(File.join(root_dir, "*.{#{Locomotive::Mounter::TEMPLATE_EXTENSIONS.join(',')}}")).each do |filepath|
              fullpath = File.basename(filepath)

              slug = File.basename(filepath).split('.').first.permalink

              unless items.key?(slug)
                items[slug] = Locomotive::Mounter::Models::Snippet.new({
                  name:     slug.humanize,
                  slug:     slug,
                  template: Locomotive::Mounter::Utils::YAMLFrontMattersTemplate.new(filepath)
                })
              end

              snippet = items[slug]

              # Return the locale of a file based on its extension.
              #
              # Ex:
              #   about_us/john_doe.fr.liquid.haml => 'fr'
              #   about_us/john_doe.liquid.haml => 'en' (default locale)
              #
              # @param [ String ] filepath The path to the file
              #
              # @return [ String ] The locale (ex: fr, en, ...etc) or nil if it has no information about the locale
              #
              locale = File.basename(filepath).split('.')[1]

              if locale.nil?
                # no locale, use the default one
                current_locale = runner.mounting_point.default_locale
              elsif runner.mounting_point.locales.include?(locale)
                # the locale is registered
                current_locale = locale
              elsif locale.size == 2
                # unregistered locale
                current_locale = nil
              else
                current_locale = runner.mounting_point.default_locale
              end

              Locomotive::Mounter.with_locale(current_locale) do
                snippet.template = Locomotive::Mounter::Utils::YAMLFrontMattersTemplate.new(filepath)
              end
            end

            items.values.each do |snippet|
              default_template = snippet.template

              next if default_template.blank?

              runner.mounting_point.locales.map(&:to_sym).each do |locale|
                next if locale == runner.mounting_point.default_locale

                _template = snippet.template_translations[locale]

                if !_template.is_a?(Exception) && _template.blank?
                  snippet.template_translations[locale] = default_template
                end
              end
            end

            items
          end

          def for_translations(runner)
            # Note that we only use the runner to retrieve the path
            path = runner.path
            config_path = File.join(path, 'config', 'translations.yml')

            {}.tap do |translations|
              if File.exists?(config_path)
                yaml = read_yaml(config_path) || []
                yaml.each do |translation|
                  key, values = translation

                  entry = Locomotive::Mounter::Models::Translation.new({
                    key:    key,
                    values: values
                  })

                  translations[key] = entry
                end
              end
            end
          end
        end

        module Readable
          def read
            accept(Reader.instance)
          end
        end

        class ContentAssetsReader
          attr_accessor :runner, :items

          delegate :default_locale, :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          # Build the list of contents assets
          #
          # @return [ Array ] The list of content assets
          #
          def read
            self.items = {} # prefer an array over a hash
            # Formerly, fetch_from_pages
            self.mounting_point.pages.values.each do |page|
              page.translated_in.each do |locale|
                Locomotive::Mounter.with_locale(locale) do
                  unless page.template.blank?
                    self.add_assets_from_string(page.template.raw_source)
                  end
                end
              end
            end
            # formerly, fetch_from_content_entries
            self.mounting_point.content_entries.values.each do |content_entry|
              content_entry.translated_in.each do |locale|
                Locomotive::Mounter.with_locale(locale) do
                  # get the string, text, file fields...
                  content_entry.content_type.fields.each do |field|
                    value = content_entry.dynamic_getter(field.name)

                    case field.type.to_sym
                    when :string, :text
                      self.add_assets_from_string(value)
                    when :file
                      self.add_assets_from_string(value['url']) if value
                    end
                  end
                end
              end
            end
            self.items
          end

          protected

          # Parse the string passed in parameter in order to
          # look for content assets. If found, then add them.
          #
          # @param [ String ] source The string to parse
          #
          def add_assets_from_string(source)
            # Return the directory where all the theme assets
            # are stored in the filesystem.
            #
            # @return [ String ] The theme assets directory
            #
            root_dir = File.join(self.runner.path, 'public')
            return if source.blank?

            source.to_s.match(/\/samples\/.*\.[a-zA-Z0-9]+/) do |match|
              filepath  = File.join(root_dir, match.to_s)
              folder    = File.dirname(match.to_s)
              self.items[source] = Locomotive::Mounter::Models::ContentAsset.new(filepath: filepath, folder: folder)
            end
          end
        end # ContentAssetsReader

        # ContentEntriesReader
        #
        #
        class ContentEntriesReader
          attr_accessor :runner, :items

          delegate :default_locale, :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          # Build the list of content types from the folder on the file system.
          #
          # @return [ Array ] The un-ordered list of content types
          #
          def read
            self.fetch_from_filesystem
            self.items
          end

          def mounting_point
            self.runner.mounting_point
          end

          protected

          # Open a YAML file and returns the content of the file
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ Object ] The content of the file
          #
          def read_yaml(filepath)
            YAML::load(File.open(filepath).read.force_encoding('utf-8'))
          end

          def fetch_from_filesystem
            Dir.glob(File.join(self.root_dir, '*.yml')).each do |filepath|
              attributes = self.read_yaml(filepath)

              content_type = self.get_content_type(File.basename(filepath, '.yml'))

              content_type.entries.try(:clear)

              attributes.each_with_index do |_attributes, index|
                self.add(content_type, _attributes, index)
              end unless attributes == false
            end
          end

          # Get the content type identified by the slug from the mounting point.
          # Raise an UnknownContentTypeException exception if such a content type
          # does not exist.
          #
          # @param [ String ] slug The slug of the content type
          #
          # @return [ Object ] The instance of the content type
          #
          def get_content_type(slug)
            self.mounting_point.content_types[slug.to_s].tap do |content_type|
              if content_type.nil?
                raise UnknownContentTypeException.new("unknow content type #{slug.inspect}")
              end
            end
          end

          # Add a content entry for a content type.
          #
          # @param [ Object ] content_type The content type
          # @param [ Hash ] attributes The attributes of the content entry
          # @param [ Integer ] position The position of the entry in the list
          #
          def add(content_type, attributes, position)
            if attributes.is_a?(String)
              label, _attributes = attributes, {}
            else
              label, _attributes = attributes.keys.first, attributes.values.first || {}
            end

            # check if the label_field is localized or not
            label_field_name = content_type.label_field_name

            if content_type.label_field.localized && _attributes.key?(label_field_name) && _attributes[label_field_name].is_a?(Hash)
              _attributes[label_field_name].merge!(Locomotive::Mounter.locale => label).symbolize_keys!
            else
              _attributes[label_field_name] = label
            end

            _attributes[:_position] = position

            # build the content entry
            entry = content_type.build_entry(_attributes)

            # and store it
            key = File.join(content_type.slug, entry._slug)

            self.items[key] = entry
          end

          # Return the directory where all the entries
          # of the content types are stored.
          #
          # @return [ String ] The content entries root directory
          #
          def root_dir
            File.join(self.runner.path, 'data')
          end

        end # ContentEntriesReader

        class PagesReader

          attr_accessor :pages
          attr_accessor :runner, :items

          delegate :default_locale, :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
            self.pages = {}
          end

          # Build the tree of pages based on the filesystem structure
          #
          # @return [ Hash ] The pages organized as a Hash (using the fullpath as the key)
          #
          def read
            self.fetch

            index, not_found = self.pages['index'], self.pages['404']

            # localize the fullpath for the 2 core pages: index and 404
            [index, not_found].each { |p| p.localize_fullpath(self.locales) }

            self.build_relationships(index, self.pages_to_list)

            # Locomotive::Mounter.with_locale(:en) { self.to_s } # DEBUG

            # Locomotive::Mounter.with_locale(:fr) { self.to_s } # DEBUG

            self.pages
          end

          def mounting_point
            self.runner.mounting_point
          end

          protected

          # Return the locale of a file based on its extension.
          #
          # Ex:
          #   about_us/john_doe.fr.liquid.haml => 'fr'
          #   about_us/john_doe.liquid.haml => 'en' (default locale)
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ String ] The locale (ex: fr, en, ...etc) or nil if it has no information about the locale
          #
          def filepath_locale(filepath)
            locale = File.basename(filepath).split('.')[1]

            if locale.nil?
              # no locale, use the default one
              self.default_locale
            elsif self.locales.include?(locale)
              # the locale is registered
              locale
            elsif locale.size == 2
              # unregistered locale
              nil
            else
              self.default_locale
            end
          end

          # Open a YAML file and returns the content of the file
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ Object ] The content of the file
          #
          def read_yaml(filepath)
            YAML::load(File.open(filepath).read.force_encoding('utf-8'))
          end

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
            # do not use an empty template for other locales than the default one
            parent.set_default_template_for_each_locale(self.default_locale)

            list.dup.each do |page|
              next unless self.is_subpage_of?(page.fullpath, parent.fullpath)

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
            position, last_dirname = nil, nil

            Dir.glob(File.join(self.root_dir, '**/*')).sort.each do |filepath|
              next unless File.directory?(filepath) || filepath =~ /\.(#{Locomotive::Mounter::TEMPLATE_EXTENSIONS.join('|')})$/

              if last_dirname != File.dirname(filepath)
                position, last_dirname = 100, File.dirname(filepath)
              end

              page = self.add(filepath, position: position)

              next if File.directory?(filepath) || page.nil?

              if locale = self.filepath_locale(filepath)
                Locomotive::Mounter.with_locale(locale) do
                  self.set_attributes_from_header(page, filepath)
                end
              else
                Locomotive::Mounter.logger.warn "Unknown locale in the '#{File.basename(filepath)}' file."
              end

              position += 1
            end
          end

          # Add a new page in the global hash of pages.
          # If the page exists, override it.
          #
          # @param [ String ] filepath The path of the template
          # @param [ Hash ] attributes The attributes of the new page
          #
          # @return [ Object ] A newly created page or the existing one
          #
          def add(filepath, attributes = {})
            fullpath = self.filepath_to_fullpath(filepath)

            unless self.pages.key?(fullpath)
              attributes[:title]    = File.basename(fullpath).humanize
              attributes[:fullpath] = fullpath

              page = Locomotive::Mounter::Models::Page.new(attributes)
              page.mounting_point = self.mounting_point
              page.filepath       = File.expand_path(filepath)

              page.template = OpenStruct.new(raw_source: '') if File.directory?(filepath)

              self.pages[fullpath] = page
            end

            self.pages[fullpath]
          end

          # Set attributes of a page from the information
          # stored in the header of the template (YAML matters).
          # It also stores the template.
          #
          # @param [ Object ] page The page
          # @param [ String ] filepath The path of the template
          #
          def set_attributes_from_header(page, filepath)
            template = Locomotive::Mounter::Utils::YAMLFrontMattersTemplate.new(filepath)

            if template.attributes
              attributes = template.attributes.clone

              # set the editable elements
              page.set_editable_elements(attributes.delete('editable_elements'))

              # set the content type
              if content_type_slug = attributes.delete('content_type')
                attributes['templatized']   = true
                attributes['content_type']  = self.mounting_point.content_types.values.find { |ct| ct.slug == content_type_slug }
              end

              page.attributes = attributes
            end

            page.template = template
          end

          # Return the directory where all the templates of
          # pages are stored in the filesystem.
          #
          # @return [ String ] The root directory
          #
          def root_dir
            File.join(self.runner.path, 'app', 'views', 'pages')
          end

          # Take the path to a file on the filesystem
          # and return its matching value for a Page.
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ String ] The fullpath of the page
          #
          def filepath_to_fullpath(filepath)
            fullpath = filepath.gsub(File.join(self.root_dir, '/'), '')

            fullpath.gsub!(/^\.\//, '')

            fullpath.split('.').first.dasherize
          end

          # Tell is a page described by its fullpath is a sub page of a parent page
          # also described by its fullpath
          #
          # @param [ String ] fullpath The full path of the page to test
          # @param [ String ] parent_fullpath The full path of the parent page
          #
          # @return [ Boolean] True if the page is a sub page of the parent one
          #
          def is_subpage_of?(fullpath, parent_fullpath)
            return false if %w(index 404).include?(fullpath)

            if parent_fullpath == 'index' && fullpath.split('/').size == 1
              return true
            end

            File.dirname(fullpath.dasherize) == parent_fullpath.dasherize
          end

          # Output simply the tree structure of the pages.
          #
          # Note: only for debug purpose
          #
          def to_s(page = nil)
            page ||= self.pages['index']

            puts "#{"  " * (page.try(:depth) + 1)} #{page.fullpath.inspect} (#{page.title}, position=#{page.position}, template=#{page.template_translations.keys.inspect})"

            (page.children || []).each { |child| self.to_s(child) }
          end

        end # PagesReader


        # ThemeAssetsReader
        #
        #
        class ThemeAssetsReader
          attr_accessor :runner, :items

          delegate :default_locale, :locales, to: :mounting_point

          def initialize(runner)
            self.runner  = runner
            self.items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          # Build the list of theme assets from the public folder with eager loading.
          #
          # @return [ Array ] The cached list of theme assets
          #
          def read
            root_dir = File.join(self.runner.path, 'public')
            ThemeAssetsArray.new(root_dir)
          end

          protected

          # Return the locale of a file based on its extension.
          #
          # Ex:
          #   about_us/john_doe.fr.liquid.haml => 'fr'
          #   about_us/john_doe.liquid.haml => 'en' (default locale)
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ String ] The locale (ex: fr, en, ...etc) or nil if it has no information about the locale
          #
          def filepath_locale(filepath)
            locale = File.basename(filepath).split('.')[1]

            if locale.nil?
              # no locale, use the default one
              self.default_locale
            elsif self.locales.include?(locale)
              # the locale is registered
              locale
            elsif locale.size == 2
              # unregistered locale
              nil
            else
              self.default_locale
            end
          end

          # Open a YAML file and returns the content of the file
          #
          # @param [ String ] filepath The path to the file
          #
          # @return [ Object ] The content of the file
          #
          def read_yaml(filepath)
            YAML::load(File.open(filepath).read.force_encoding('utf-8'))
          end
        end

        class ThemeAssetsArray

          attr_accessor :root_dir

          def initialize(root_dir)
            self.root_dir = root_dir
          end

          def list
            return @list unless @list.nil?

            # Follows symlinks and makes sure subdirectories are handled
            glob_pattern = '**/*/**/*'

            @list = [].tap do |list|
              Dir.glob(File.join(self.root_dir, glob_pattern)).each do |file|
                next if self.exclude?(file)

                folder = File.dirname(file.gsub("#{self.root_dir}/", ''))

                asset = Locomotive::Mounter::Models::ThemeAsset.new(folder: folder, filepath: file)

                list << asset
              end
            end
          end

          alias :values :list

          # Tell if the file has to be excluded from the array
          # of theme assets. It does not have to be a folder
          # or be in the samples folder or owns a name starting with
          # the underscore character.
          #
          # @param [ String ] file The full path to the file
          #
          # @return [ Boolean ] True if it does not have to be included in the list.
          #
          def exclude?(file)
            File.directory?(file) ||
            file.starts_with?(File.join(self.root_dir, 'samples')) ||
            File.basename(file).starts_with?('_')
          end

          # This class acts a proxy of an array
          def method_missing(name, *args, &block)
            self.list.send(name.to_sym, *args, &block)
          end
        end # ThemeAssetsArray

        class SnippetsReader
          include Readable

          attr_accessor :runner, :items

          def initialize(runner)
            @runner  = runner
            @items   = {}
          end

          def accept(ask)
            ask.for_snippets(@runner, @items)
          end
        end # SnippetsReader

        class SiteReader
          include Readable

          attr_accessor :runner

          def initialize(runner)
            self.runner  = runner
          end

          def accept(ask)
            ask.for_site(@runner)
          end
        end # SiteReader

        # ContentTypesReader
        #
        #
        class ContentTypesReader
          include Readable

          attr_accessor :runner, :items

          delegate :default_locale, :locales, to: :mounting_point

          def initialize(runner)
            @runner  = runner
            @items   = {}
          end

          def mounting_point
            self.runner.mounting_point
          end

          def accept(ask)
            ask.for_content_types(@runner, @items, mounting_point)
          end
        end # ContentTypesReader

        # TranslationsReader
        #
        #
        class TranslationsReader
          include Readable

          attr_accessor :runner

          def initialize(runner)
            @runner  = runner
          end

          def accept(ask)
            ask.for_translations(@runner)
          end
        end # TranslationsReader
      end # FileSystem
    end # Reader
  end # Mounter
end # Locomotive
