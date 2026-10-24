# frozen_string_literal: true

module SealedTrail
  class Railtie < Rails::Railtie
    initializer "sealed_trail.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend SealedTrail::Model::ClassMethods
      end
    end

    initializer "sealed_trail.action_controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include SealedTrail::Controller if SealedTrail.config.auto_include_controller
      end

      ActiveSupport.on_load(:action_controller_api) do
        include SealedTrail::Controller if SealedTrail.config.auto_include_controller
      end
    end
  end
end
