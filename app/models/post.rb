# encoding: utf-8

class Post < ActiveRecord::Base
  attr_accessor :keywords, :images      # Only populated in Post.new_from_url()
  attr_accessible :title, :url, :keywords, :images
  has_attached_file :image, :styles => {
    :featured => "749x400",
    :square => '363'
  }

  belongs_to :user

  has_many :comments
  has_many :votes

  before_validation :set_image_if_necessary

  validates_presence_of :user

  def type
    # Everything is square for now.
    :square_article
  end

  def image_height_as_pct
    return 0 unless image.present?
    width, height = image.image_size.split('x').map(&:to_f)
    height / width
  end

  # Class methods (i.e. Post.recommendations_for(user, n) )
  class << self
    def recommendations_for(user, n=10)
      posts = THRIFTCLIENT.recPosts(user.id).posts
      return Post.order('created_at DESC').first(n) if posts.empty?

      posts.map do |p|
        Post.where(:id => p.post_id).first
      end
    end

    def new_from_url(url)
      images, title, leader, keywords = fetch_from_url(url)

      oct_vec = keywords.map do |pair|
        Backend::Token.new(:t => pair[0], :f => pair[1])
      end

      Post.new(
        :title     => title,
        :url       => url,
        :keywords  => oct_vec,
        :images    => images,
      )
    end

    def fetch_from_url(url)
      post = Pismo::Document.new(url)
      images = post.images || []
      leader = post.lede # This is the first couple sentences.
      keywords = post.keywords(
        :minimum_score => 1,
        :stem_at => 2,
        :word_length_limit => 30,
        :limit => 500
      )
      return [
        post.images || [],
        post.title,
        post.lede,
        keywords
      ]
    end
  end

private

  def set_image_if_necessary
    self.image = open(images.first) if image.blank? && images.present?
  end

end
