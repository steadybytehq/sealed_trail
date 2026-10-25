# frozen_string_literal: true

module SealedTrail
  class Railtie < Rails::Railtie
    initializer "sealed_trail.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend SealedTrail::Model::ClassMethods
        ActiveRecord::Relation.prepend(SealedTrail::Bulk::RelationHooks)
        ActiveRecord::Relation.prepend(SealedTrail::Bulk::InsertHooks) if SealedTrail::Bulk.relation_inserts?
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

    initializer "sealed_trail.active_job" do
      ActiveSupport.on_load(:active_job) do
        require "sealed_trail/job_context"
        include SealedTrail::JobContext
      end
    end

    console do
      SealedTrail.process_actor_label ||= "console"
    end

    rake_tasks do
      SealedTrail::RakeContext.install!
    end
  end
end
