# frozen_string_literal: true

module SealedTrail
  # One audit entry: a create, update or destroy of one record.
  #
  # Columns: item_type, item_id, event, object_changes ({"attr" => [before,
  # after]}), metadata, actor_type, actor_id, request_id, remote_ip,
  # created_at.
  #
  # Entries are append-only through Active Record: once saved they are
  # read-only, so +update+ and +destroy+ raise ActiveRecord::ReadOnlyRecord.
  # (This does not stop raw SQL; tamper evidence is a SealedTrail Pro feature.)
  class Entry < ActiveRecord::Base
    self.table_name = "sealed_trail_entries"

    belongs_to :item, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true

    validates :item_type, :item_id, :event, presence: true
    validates :event, inclusion: { in: SealedTrail::Model::EVENTS.map(&:to_s) }

    scope :chronological, -> { order(:created_at, :id) }
    scope :reverse_chronological, -> { order(created_at: :desc, id: :desc) }

    # Entries attributed to +actor+: an Active Record object or a String/Symbol
    # label passed to SealedTrail.with_actor.
    scope :for_actor, lambda { |actor|
      if actor.is_a?(ActiveRecord::Base)
        where(actor_type: actor.class.polymorphic_name, actor_id: actor.id.to_s)
      else
        where(actor_type: nil, actor_id: actor.to_s)
      end
    }

    # Entries about one record. Accepts a record, or a class (or class name)
    # and an id, which also works after the record was destroyed:
    #
    #   SealedTrail::Entry.for_item(post)
    #   SealedTrail::Entry.for_item(Post, 42)
    scope :for_item, lambda { |item_or_class, id = nil|
      if item_or_class.is_a?(ActiveRecord::Base)
        where(item_type: item_or_class.class.polymorphic_name, item_id: item_or_class.id.to_s)
      else
        klass = item_or_class.is_a?(Class) ? item_or_class : item_or_class.to_s.constantize
        where(item_type: klass.polymorphic_name, item_id: id.to_s)
      end
    }

    # Entries for any record of a model class.
    scope :for_item_type, lambda { |klass|
      klass = klass.to_s.constantize unless klass.is_a?(Class)
      where(item_type: klass.polymorphic_name)
    }

    # Entries created in a time range. Either end may be nil for an open range.
    scope :between, ->(from, to) { where(created_at: from..to) }

    # Entries for the given events: events(:update), events(:create, :destroy).
    scope :events, ->(*names) { where(event: names.flatten.map(&:to_s)) }

    scope :for_request, ->(request_id) { where(request_id: request_id) }

    def readonly?
      persisted? || super
    end

    # Names of the attributes this entry recorded.
    def changed_attribute_names
      (object_changes || {}).keys
    end

    # [before, after] for one attribute, or nil if it was not recorded.
    def change_for(attribute)
      (object_changes || {})[attribute.to_s]
    end

    def create? = event == "create"
    def update? = event == "update"
    def destroy? = event == "destroy"
  end
end
