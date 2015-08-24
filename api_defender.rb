# lib/api_defender.rb
require 'rack/throttle'
# we limit daily API usage
class ApiDefender < Rack::Throttle::Daily

  def initialize(app)
    host, port, db = YAML.load_file(File.dirname(__FILE__) + '/../config/redis.yml')[Rails.env].split(':')
    options = {
      # config file here
      :cache => Redis.new(:host => host, :port => port, :thread_safe => true, :db => db),
      :key_prefix => "zubibu:#{Rails.env}:api_defender",
      # only 5000 request per day
      :max => 5000
    }
    @app, @options = app, options
  end

  # this method checks if request needs throttling. 
  # If so, it increases usage counter and compare it with maximum 
  # allowed API calls. Returns true if a request can be handled.
  def allowed?(request)
    need_defense?(request) ? cache_incr(request) <= max_per_window : true
  end

  def call(env)
    status, heders, body = super
    request = Rack::Request.new(env)
    # just to be nice for our clients we inform them how many
    # requests remaining they have.
    if need_defense?(request)
      heders['X-RateLimit-Limit']     = max_per_window.to_s
      heders['X-RateLimit-Remaining'] = ([0, max_per_window - (cache_get(cache_key(request)).to_i rescue 1)].max).to_s
    end
    [status, heders, body]
  end

  def cache_incr(request)
    key = cache_key(request)
    count = cache.incr(key)
    cache.expire(key, 1.day) if count == 1
    count
  end

  protected
    # only API calls should be throttled
    def need_defense?(request)
      request.host == API_HOST
    end

end