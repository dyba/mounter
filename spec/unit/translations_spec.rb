require 'spec_helper'

module Locomotive::Mounter
  RSpec.describe FileSystem do
    let(:file_system) { double("file_system") }
    let(:src) { File.expand_path(File.join(File.dirname(__FILE__), '..', 'fixtures', 'default')) }

    it "reads all translations" do
      translations = FileSystem.read(src, :translations)

      expected = { key: "powered_by", values: { "en" => "Powered by", "fr" => "Propulsé par" } }
      expect(translations["powered_by"].to_params).to eq expected
    end

    it "reads specific translations" do
      pending "Need to be able to filter translations"

      translations = FileSystem.read(src, :translations, filter: "e*")

      expected = { "en" => "Hello" }
      expect(translations).to eq expected
    end
  end

  RSpec.describe RemoteSite do
    let(:api) { double("api") }
    let(:src) { double("src") }

    it "reads all translations" do
      translations = RemoteSite.read(src, :translations)

      expected = { "en" => "Hello", "fr" => "Salut" }
      expect(translations).to eq expected
    end

    it "reads specific translations" do
      pending "Need to be able to filter translations"

      translations = RemoteSite.read(src, :translations)

      expected = { "en" => "Hello" }
      expect(translations).to eq expected
    end

    it "writes all translations" do
      RemoteSite.write(src, :translations)
    end

    it "writes specific translations" do
      RemoteSite.write(src, :translations, filter: "e*")
    end
  end
end
