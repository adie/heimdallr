require 'spec_helper'

class User < ActiveRecord::Base; end

class Article < ActiveRecord::Base
  include Heimdallr::Model

  belongs_to :owner, :class_name => 'User'

  restrict do |user, record|
    if user.admin?
      # Administrator or owner can do everything
      scope :fetch
      scope :destroy
      can [:view, :create, :update]
    else
      # Other users can view only their own or non-classified articles...
      scope :fetch,  -> { where('owner_id = ? or secrecy_level < ?', user.id, 5) }
      scope :delete, -> { where('owner_id = ?', user.id) }

      # ... and see all fields except the actual security level
      # (through owners can see everything)...
      if record.try(:owner) == user
        can    :view
      else
        can    :view
        cannot :view, [:secrecy_level]
      end

      # ... and can create them with certain restrictions.
      can :create, %w(content)
      can [:create, :update], {
        owner:         user,
        secrecy_level: { inclusion: { in: 0..4 } }
      }
    end
  end
end

describe Heimdallr::Proxy do
  before(:all) do
    @john = User.create! :admin => false
    Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
    Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 3
  end

  before(:each) do
    @admin  = User.new :admin => true
    @looser = User.new :admin => false
  end

  it "should apply restrictions" do
    proxy = Article.restrict(@admin)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection

    proxy = Article.restrict(@looser)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection
  end

  it "should handle fetch scope" do
    Article.restrict(@admin).all.count.should == 2
    Article.restrict(@looser).all.count.should == 1
    Article.restrict(@john).all.count.should == 2
  end

  it "should handle destroy scope" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@looser).destroy }.should raise_error
    expect { article.restrict(@john).destroy }.should_not raise_error

    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@admin).destroy }.should raise_error
  end
end