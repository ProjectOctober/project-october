# encoding: utf-8

class Post < ActiveRecord::Base
  attr_accessor :keywords, :images      # Only populated in Post.new_from_url()
  attr_accessor :weight                 # Only populated in Post.assign_types()
  attr_accessible :title, :url, :keywords, :images
  has_attached_file :image, :styles => {
    :featured => "749x400",
    :square => '363'
  }

  has_many :comments
  has_many :votes
  belongs_to :poster

  before_save :set_image_if_necessary

  validates_presence_of :poster_id
  validates_presence_of :title

  validates_uniqueness_of :title, :scope => :poster_id
  validates_uniqueness_of :url, :scope => :poster_id

  def image_height_as_pct
    return 0 unless image.present?
    width, height = image.image_size.split('x').map(&:to_f)
    height / width
  end

  # Class methods (i.e. Post.recommendations_for(user, n) )
  class << self
    def recommendations_for(user, n=30)
      posts = THRIFTCLIENT.recPosts(user.id, n, 0).posts.inject({}) { |a,i| a.merge(i.post_id => i.weight) }
      if posts.empty?
        return Post.order('created_at DESC').first(n).map do |p|
          [p, p.image.present? ? :square_article_primary_picture : :square_article_primary]
        end
      end

      assign_types(posts)
    end

    # Takes a hash of { post_id => weight } and assigns display types for them.
    def assign_types(post_list)
      num_primary = (0.5 * post_list.length).round

      posts = Post.
        find(post_list.keys, :include => [:poster, :comments]).
        each { |p| p.weight = post_list[p.id] }.
        sort_by { |p| p.weight }.
        reverse

      # Frontpage display algorithm:
      # 1) Find the highest weighted story that is eligible to be a featured
      #    post. It is the featured post.
      # 2) All other articles are to be displayed with an image if possible in
      #    order according to weight.
      featured = posts.detect { |p| p.image.present? }
      posts = posts - [featured]
      other_featured = posts.detect { |p| p.image.present? }
      posts = posts - [other_featured]

      post_type_list = posts.map do |p|
        primary = (num_primary -= 1) > 0 ? :primary : :secondary
        type = if p.image.present?
          "square_article_#{primary}_picture"
               else
          "square_article_#{primary}"
               end.to_sym

        [ p, type ]
      end

      # Pseudo-shuffle here:
      post_type_list = post_type_list.group_by { |p, _| p.id % 4 }.values.flatten(1)

      # Add the featured articles back in:
      post_type_list.unshift([featured, :feature_article]) if featured.present?
      post_type_list.insert(post_type_list.length / 4, [other_featured, :feature_article]) if other_featured.present?

      post_type_list
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
      post = Pismo::Document.new(url,
        # :reader => :cluster,        # Pismo error! (?!?)
        :image_extractor => true,
      )
      images = post.images || []
      leader = post.lede # This is the first couple sentences.
      keywords = post.keywords(
        :limit => 50
      ).delete_if { |keyword, occur| keyword.to_i != 0 }

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
    if image.blank? && images.present?
      images.each do |url|
        self.image = URI.parse(url)
        self.image.destroy if self.image.width < 200 || self.image.height < 50
      end
    end
  end
end
