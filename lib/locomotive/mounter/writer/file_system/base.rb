module Locomotive
  module Mounter
    module Writer
      module FileSystem
        class Base

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # It should always be called before executing the write method.
          # Writers inheriting from this class can overide it
          #
          def prepare
            self.output_title(:writing)
          end

          # Writers inheriting from this class *must* overide it
          def write
            raise 'The write method has to be overridden'
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

        end

        class ContentAssetsWriter
          include Locomotive::Mounter::Utils::Output

          # It creates the content assets folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'public'
          end

          # It writes all the content assets into files
          def write
            self.mounting_point.content_assets.each do |_, asset|
              self.output_resource_op asset

              self.open_file(self.target_asset_path(asset), 'wb') do |file|
                file.write(asset.content)
              end

              self.output_resource_op_status asset
            end
          end

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

          def target_asset_path(asset)
            File.join('public', asset.folder, asset.filename)
          end

        end # CententAssetsWriter

        class ContentEntriesWriter < Base

          # It creates the data folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'data'
          end

          # It writes all the content types into files
          def write
            self.mounting_point.content_types.each do |filename, content_type|
              self.output_resource_op content_type

              entries = (content_type.entries || []).map(&:to_hash)

              self.open_file("data/#{filename}.yml") do |file|
                file.write(entries.to_yaml)
              end

              self.output_resource_op_status content_type
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

        end # ContentEntriesWriter

        class ContentTypesWriter
          include Locomotive::Mounter::Utils::Output

          # It creates the content types folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'app/content_types'
          end

          # It writes all the content types into files
          def write
            self.mounting_point.content_types.each do |filename, content_type|
              self.output_resource_op content_type

              self.open_file("app/content_types/#{filename}.yml") do |file|
                file.write(content_type.to_yaml)
              end

              self.output_resource_op_status content_type
            end
          end

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end
        end # ContentEntriesWriter

        class PagesWriter

          # It creates the pages folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'app/views/pages'
          end

          # It writes all the pages into files
          def write
            self.write_page(self.mounting_point.pages['index'])

            self.write_page(self.mounting_point.pages['404'])
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

          # Write the information about a page into the filesystem.
          # Called itself recursively. Called at first by the write method
          #
          # @param [ Object ] page The page
          # @param [ String ] path The parent path
          #
          def write_page(page, path = '')
            self.output_resource_op page

            # Note: we assume the current locale is the default one
            page.translated_in.each do |locale|
              default_locale = locale.to_sym == self.mounting_point.default_locale.to_sym

              # we do not need the localized version of the filepath
              filepath = page.fullpath.dasherize

              Locomotive::Mounter.with_locale(locale) do
                # we assume the filepath is already localized
                self.write_page_to_fs(page, filepath, default_locale ? nil : locale)
              end
            end

            self.output_resource_op_status page

            # also write the nested pages
            (page.children || []).each do |child|
              self.write_page(child, page.depth == 0 ? '' : page.slug)
            end
          end

          # Write into the filesystem the file about the page which will store
          # information about this page + template.
          # The file is localized meaning a same page could generate a file for each translation.
          #
          # @param [ Object ] page The page
          # @param [ String ] filepath The path to the file describing the page (not localized)
          # @param [ Locale ] locale The locale, nil if default locale
          #
          #
          def write_page_to_fs(page, filepath, locale)
            # puts filepath.inspect
            _filepath = "#{filepath}.liquid"
            _filepath.gsub!(/.liquid$/, ".#{locale}.liquid") if locale

            _filepath = File.join('app', 'views', 'pages', _filepath)

            self.replace_content_asset_urls(page.source)

            self.open_file(_filepath) do |file|
              file.write(page.to_yaml)
            end
          end

          # The content assets on the remote engine follows the format: /sites/<id>/assets/<type>/<file>
          # This method replaces these urls by their local representation. <type>/<file>
          #
          # @param [ String ] content The text where the assets will be replaced.
          #
          def replace_content_asset_urls(content)
            return if content.blank?
            content.force_encoding('utf-8').gsub!(/[("']\/sites\/[0-9a-f]{24}\/assets\/(([^;.]+)\/)*([a-zA-Z_\-0-9]+)\.[a-z]{2,3}[)"']/) do |path|
              "/#{$3}"
            end
          end

        end # PagesWriter

        class SiteWriter
          include Locomotive::Mounter::Utils::Output

          # It creates the config folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'config'
          end

          # It fills the config/site.yml file
          def write
            self.open_file('config/site.yml') do |file|
              self.output_resource_op self.mounting_point.site

              file.write(self.mounting_point.site.to_yaml)

              self.output_resource_op_status self.mounting_point.site
            end
          end

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

        end # SiteWriter

        class SnippetsWriter
          include Locomotive::Mounter::Utils::Output

          # It creates the snippets folder
          def prepare
            self.output_title(:writing)
            self.create_folder 'app/views/snippets'
          end

          # It writes all the snippets into files
          def write
            self.mounting_point.snippets.each do |filepath, snippet|
              self.output_resource_op snippet

              # Note: we assume the current locale is the default one
              snippet.translated_in.each do |locale|
                default_locale = locale.to_sym == self.mounting_point.default_locale.to_sym

                Locomotive::Mounter.with_locale(locale) do
                  self.write_snippet_to_fs(snippet, filepath, default_locale ? nil : locale)
                end
              end

              self.output_resource_op_status snippet
            end
          end

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

          # Write into the filesystem the file which stores the snippet template
          # The file is localized meaning a same snippet could generate a file for each translation.
          #
          # @param [ Object ] snippet The snippet
          # @param [ String ] filepath The path to the file
          # @param [ Locale ] locale The locale, nil if default locale
          #
          def write_snippet_to_fs(snippet, filepath, locale)
            _filepath = "#{filepath}.liquid"
            _filepath.gsub!(/.liquid$/, ".#{locale}.liquid") if locale

            unless snippet.template.blank?
              _filepath = File.join('app', 'views', 'snippets', _filepath)

              self.open_file(_filepath) do |file|
                file.write(snippet.source)
              end
            end
          end

        end

        class ThemeAssetsWriter

          # Create the theme assets folders
          #
          def prepare
            self.output_title(:writing)
            self.create_folder 'public'
          end

          # Write all the snippets into files
          #
          def write
            self.theme_assets_by_priority.each do |asset|
              self.output_resource_op asset

              self.open_file(self.target_asset_path(asset), 'wb') do |file|
                content = asset.content

                if asset.stylesheet_or_javascript?
                  self.replace_asset_urls(content)
                end

                file.write(content)
              end

              self.output_resource_op_status asset
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end

          # The urls stored on the remote engine follows the format: /sites/<id>/theme/<type>/<file>
          # This method replaces these urls by their local representation. <type>/<file>
          #
          # @param [ String ] content
          #
          def replace_asset_urls(content)
            return if content.blank?
            content.force_encoding('utf-8').gsub!(/[("']([^)"';]*)\/sites\/[0-9a-f]{24}\/theme\/(([^;.]+)\/)*([a-zA-Z_\-0-9]+\.[a-z]{2,3})[)"']/) do |path|
              "#{path.first}/#{$2 + $4}#{path.last}"
            end
          end

          # Return the path where will be copied the asset
          #
          # @param [ String ] asset The asset
          #
          # @return [ String ] The relative path of the asset locally
          #
          def target_asset_path(asset)
            File.join('public', asset.folder, asset.filename)
          end

          # List of theme assets sorted by their priority.
          #
          # @return [ Array ] Sorted list of the theme assets
          #
          def theme_assets_by_priority
            self.mounting_point.theme_assets.sort { |a, b| a.priority <=> b.priority }
          end

        end

        class TranslationsWriter

          def prepare
            self.output_title(:writing)
            self.create_folder 'config'
          end

          def write
            content = self.mounting_point.translations.each_with_object({}) do |(key,translation), hash|
              hash[key] = translation.values
            end

            content = content.empty? ? '' : content.to_yaml

            self.open_file('config/translations.yml') do |file|
              file.write content
            end
          end

          include Locomotive::Mounter::Utils::Output

          attr_accessor :mounting_point, :runner

          def initialize(mounting_point, runner)
            self.mounting_point = mounting_point
            self.runner         = runner
          end

          # Helper method to create a folder from a relative path
          #
          # @param [ String ] path The relative path
          #
          def create_folder(path)
            fullpath = File.join(self.target_path, path)
            unless File.exists?(fullpath)
              FileUtils.mkdir_p(fullpath)
            end
          end

          # Open a file described by the relative path. The file will be closed after the execution of the block.
          #
          # @param [ String ] path The relative path
          # @param [ String ] mode The file mode ('w' by default)
          # @param [ Lambda ] &block The block passed to the File.open method
          #
          def open_file(path, mode = 'w', &block)
            # make sure the target folder exists
            self.create_folder(File.dirname(path))

            fullpath = File.join(self.target_path, path)

            File.open(fullpath, mode, &block)
          end

          def target_path
            self.runner.target_path
          end

          protected

          def resource_message(resource)
            "    writing #{truncate(resource.to_s)}"
          end
        end
      end
    end
  end
end
