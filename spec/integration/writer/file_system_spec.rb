require 'spec_helper'

RSpec.describe Locomotive::Mounter::Writer::FileSystem do

  let(:target_path) { File.join(File.dirname(__FILE__), '..', '..', 'tmp', 'default') }
  let(:fs_writer)   { Locomotive::Mounter::Writer::FileSystem.instance }

  context 'from a local site' do
    let(:source_path)     { File.join(File.dirname(__FILE__), '..', '..', 'fixtures', 'default') }
    let(:_mounting_point)  { Locomotive::Mounter::Reader::FileSystem.instance.run!(path: source_path) }

    subject { fs_writer.run!(mounting_point: _mounting_point, target_path: target_path) }

    it {
      pending
      should_not be_nil
    }

  end

  context 'from a remote site', :vcr do
    let(:_mounting_point) { Locomotive::Mounter::Reader::Api.instance.run!(credentials) }

    subject { fs_writer.run!(mounting_point: _mounting_point, target_path: target_path) }

    before(:all)  { setup 'reader_api_setup' }
    after(:all)   { teardown }

    it { pending; should_not be_nil }

  end
end
