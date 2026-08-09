# frozen_string_literal: true

require "erb"

class Renderer
  TEMPLATE_PATH = File.expand_path("../views/greeting.html.erb", __dir__)

  # define_method (not `def`) on purpose: DDCov's frame-path resolution
  # for the eval inside ERB#result does not attribute back to the .erb
  # file when the call is nested under a plain `def` method frame, but it
  # does when nested under a block-based method (define_method) or a
  # block/lambda — matching how Rails compiles templates via module_eval.
  define_method(:render_greeting) do |name|
    erb = ERB.new(File.read(TEMPLATE_PATH))
    erb.filename = TEMPLATE_PATH
    erb.result(binding)
  end
end
