require 'spec_helper'

RSpec.describe Locomotive::Mounter::Reader::FileSystem::SnippetsReader do
  let(:runner) { Locomotive::Mounter::Reader::FileSystem::Runner.new(:file_system) }
  let(:path) { File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'fixtures', 'default')) }

  subject { Locomotive::Mounter::Reader::FileSystem::SnippetsReader.new(runner) }

  it "reads all snippets" do
    pending
    runner.path = path

    data = subject.read

    expect(data.items).to be false
  end
end
