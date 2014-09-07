require 'spec_helper'

RSpec.describe Locomotive::Mounter::Reader::FileSystem::SiteReader do
  let(:runner) { Locomotive::Mounter::Reader::FileSystem::Runner.new(:file_system) }
  let(:path) { File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'fixtures', 'default')) }

  subject { Locomotive::Mounter::Reader::FileSystem::SiteReader.new(runner) }

  before(:each) do
    runner.path = path
  end

  it "reads the site's name" do
    site = subject.read

    expect(site.name).to eq "Sample website"
  end

  it "reads the site's subdomain" do
    site = subject.read

    expect(site.subdomain).to eq "sample"
  end

  it "reads the site's timezone" do
    site = subject.read

    expect(site.timezone).to eq "Paris"
  end

  it "reads the locales" do
    site = subject.read

    expect(site.locales).to eq ['en', 'fr', 'nb']
  end

  it "reads the seo titles" do
    site = subject.read

    expect(site.seo_title).to eq "A simple LocomotiveCMS website"
  end

  it "reads the meta keywords" do
    site = subject.read

    expect(site.meta_keywords).to eq "some meta keywords"
  end
end
