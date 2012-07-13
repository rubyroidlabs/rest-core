
require 'rest-core'

class RestCore::ResponseFuture
  include RestCore

  class Proxy < BasicObject
    def initialize future, target
      @future, @target = future, target
    end

    def method_missing msg, *args, &block
      load.__send__(msg, *args, &block)
    end

    def load
      @future.yield[@target]
    end

    def loaded?
      !!@future.status
    end
  end

  def initialize env, k, immediate
    self.env       = env
    self.k         = k
    self.fiber     = Fiber.current
    self.response  = nil
    self.body, self.status, self.headers = nil, nil, nil
    self.immediate = immediate
  end

  def proxy_body   ; Proxy.new(self, RESPONSE_BODY   ); end
  def proxy_status ; Proxy.new(self, RESPONSE_STATUS ); end
  def proxy_headers; Proxy.new(self, RESPONSE_HEADERS); end

  def yield
    Fiber.yield until status # it might be resumed by some other futures!
    callback
  end

  def callback
    self.response ||= k.call(
      env.merge(RESPONSE_BODY    => body  ,
                RESPONSE_STATUS  => status,
                RESPONSE_HEADERS => headers))
  end

  def on_load body, status, headers
    env[TIMER].cancel if env[TIMER]
    self.body, self.status, self.headers = body, status, headers
    if immediate # no fibers are required in this case
      callback
    elsif fiber.alive?
      fiber.resume
    end
  rescue FiberError
    # whenever timeout, it would be already resumed,
    # and we have no way to tell if it's already resumed or not!
  end

  protected
  attr_accessor :env, :k, :fiber, :response, :body, :status, :headers,
                :immediate
end