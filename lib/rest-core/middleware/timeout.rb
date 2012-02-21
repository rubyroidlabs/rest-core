
require 'rest-core/middleware'

require 'timeout'

class RestCore::Timeout
  def self.members; [:timeout]; end
  include RestCore::Middleware

  def call env
    monitor(env){ |e| app.call(e) }
  end

  def monitor env
    if root_fiber?
      if [Coolio, EmHttpRequest].include?(env[RUN])
        yield(env.merge(TIMER => timeout_with_callback(env)))
      else
        ::Timeout.timeout(timeout(env)){ yield(env) }
      end
    else
      yield(env.merge(TIMER => timeout_with_resume(env)))
    end
  end

  def root_fiber?
    RestCore.const_defined?(:RootFiber) && RootFiber == Fiber.current
  end

  def timeout_with_callback env
    case env[RUN].name
    when /Coolio$/
      timer = CoolioTimer.new(timeout(env))
      timer.error = timeout_error
      timer.attach(::Coolio::Loop.default)
      timer
    when /EmHttpRequest$/
      EventMachineTimer.new(timeout(env), timeout_error)
    else
      raise "BUG: #{env[RUN]} is not supported"
    end
  end

  def timeout_with_resume env
    case env[RUN].name
    when /CoolioFiber$/
      f = Fiber.current
      timer = CoolioTimer.new(timeout(env))
      error = timer.error = timeout_error
      timer.on_timer{ f.resume(error) if f.alive? }
      timer.attach(::Coolio::Loop.default)
      timer

    when /EmHttpRequestFiber$/
      f = Fiber.current
      EventMachineTimer.new(timeout(env), error = timeout_error){
        f.resume(error) if f.alive?
      }
    else
      raise "BUG: #{env[RUN]} is not supported"
    end
  end

  def timeout_error
    ::Timeout::Error.new('execution expired')
  end

  autoload       :CoolioTimer,
    'rest-core/middleware/timeout/coolio_timer'
  autoload :EventMachineTimer,
    'rest-core/middleware/timeout/eventmachine_timer'
end
