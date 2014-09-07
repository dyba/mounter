require 'spec_helper'

RSpec.describe Locomotive::Mounter::Reader::FileSystem::TranslationsReader do
  let(:runner) { Locomotive::Mounter::Reader::FileSystem::Runner.new(:file_system) }
  let(:path) { File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'fixtures', 'default')) }

  subject { Locomotive::Mounter::Reader::FileSystem::TranslationsReader.new(runner) }

  it "reads all translations" do
    runner.path = path

    translations = { "en" => "Powered by", "fr" => "Propulsé par" }
    data = subject.read

    expect(data["powered_by"].values).to eq translations
  end
end
