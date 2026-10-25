# frozen_string_literal: true

module SealedTrail
  # Carries the actor, request id, remote IP and metadata from where a job is
  # enqueued into the job, and labels entries recorded by a job without an
  # actor as "job:<JobClass>". Included into ActiveJob::Base by the Railtie.
  module JobContext
    KEY = "sealed_trail"

    extend ActiveSupport::Concern

    included do
      around_perform :with_sealed_trail_context
    end

    def serialize
      data = super
      context = SealedTrail::JobContext.capture
      data[KEY] = context if context
      data
    end

    def deserialize(job_data)
      super
      @sealed_trail_context = job_data[KEY]
    end

    def self.capture
      return unless SealedTrail.config.active_job_integration

      context = {}
      actor = SealedTrail::Current.identified_actor
      case actor
      when nil then nil
      when ActiveRecord::Base
        if actor.respond_to?(:to_global_id) && actor.persisted?
          context["actor_gid"] = actor.to_global_id.to_s
        else
          context["actor"] = "#{actor.class.polymorphic_name}##{actor.id}"
        end
      else
        context["actor"] = actor.to_s
      end
      context["request_id"] = SealedTrail::Current.request_id if SealedTrail::Current.request_id
      context["remote_ip"] = SealedTrail::Current.remote_ip if SealedTrail::Current.remote_ip
      context["metadata"] = SealedTrail::Current.metadata.as_json if SealedTrail::Current.metadata.present?
      context.presence
    end

    def self.locate_actor(context)
      if (gid = context["actor_gid"])
        GlobalID::Locator.locate(gid) || gid
      else
        context["actor"]
      end
    rescue ActiveRecord::RecordNotFound
      gid
    end

    private

    def with_sealed_trail_context(&)
      return yield unless SealedTrail.config.active_job_integration

      attributes = { context_label: "job:#{self.class.name}" }
      if (context = @sealed_trail_context)
        actor = SealedTrail::JobContext.locate_actor(context)
        attributes[:actor] = actor unless actor.nil?
        attributes[:request_id] = context["request_id"] if context["request_id"]
        attributes[:remote_ip] = context["remote_ip"] if context["remote_ip"]
        attributes[:metadata] = (SealedTrail::Current.metadata || {}).merge(context["metadata"]) if context["metadata"]
      end
      SealedTrail::Current.set(attributes, &)
    end
  end
end
