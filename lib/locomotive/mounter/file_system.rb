module Locomotive::Mounter
  class FileSystem
    class << self
      def read(src, site_object_type, **opts)
      end

      def write(dst, site_object_type, **opts)
      end
    end
  end

  class RemoteSite
    class << self
      def read(src, site_object_type, **opts)
      end

      def write(dst, site_object_type, ** opts)
      end
    end
  end
end
