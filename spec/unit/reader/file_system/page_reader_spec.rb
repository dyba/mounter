require 'spec_helper'

describe 'Locomotive::Mounter::Reader::FileSystem::PagesReader' do

  before(:each) do
    Locomotive::Mounter::Reader::FileSystem.instance # force the load of the pages_reader class
    @reader = Locomotive::Mounter::Reader::FileSystem::PagesReader.new(nil)
  end

  describe '#filepath_locale' do

    before(:each) do
      @reader.stub(locales: ['en', 'fr'])
      @reader.stub(default_locale: 'en')
    end

    it 'returns the default locale if no locale information in the filepath' do
      @reader.send(:filepath_locale, 'app/views/pages/index.liquid.haml').should == 'en'
    end

    it 'returns nil if the locale in the filepath is not registered' do
      @reader.send(:filepath_locale, 'app/views/pages/index.de.liquid.haml').should be_nil
    end

    context 'the locale in the filepath is registered' do

      it 'returns the locale' do
        @reader.send(:filepath_locale, 'app/views/pages/index.fr.liquid.haml').should == 'fr'
      end

      it 'returns the locale even if the filepath contains multiple dots' do
        @reader.send(:filepath_locale, 'app/./views/../views/pages/index.fr.liquid.haml').should == 'fr'
      end

    end

  end

  describe '#is_subpage_of?' do

    %w(index 404).each do |page|
      it "returns false for the '#{page}'" do
        expect(@reader.send(:is_subpage_of?, page, 'index')).to be false
      end
    end

    it 'returns true for pages under index' do
      expect(@reader.send(:is_subpage_of?, 'about_us', 'index')).to be true
    end

    it "returns true for pages under 'about_us'" do
      expect(@reader.send(:is_subpage_of?, 'about_us/my_team', 'about_us')).to be true
    end

    it "returns true for pages under 'about-us'" do
      expect(@reader.send(:is_subpage_of?, 'about-us/my_team', 'about_us')).to be true
    end

  end

end
