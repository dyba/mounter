require 'spec_helper'

module Locomotive::Mounter
  RSpec.describe FileSystem do
    let(:file_system) { double("file_system") }
    let(:src) { double("dir") }

    it "reads all translations" do
      translations = FileSystem.read(src, :translations)

      expected = { "en" => "Hello", "fr" => "Salut" }
      expect(translations).to eq expected
    end

    it "reads specific translations" do
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
