# frozen_string_literal: true

module SealedTrail
  # One audit entry: a create, update, destroy or touch of one record, or a
  # summary of one bulk operation (bulk_update, bulk_delete, bulk_insert,
  # bulk_upsert) on a model.
  #
  # Columns: item_type, item_id ("*" for bulk entries), event, object_changes
  # ({"attr" => [before, after]}), metadata, actor_type, actor_id, request_id,
  # remote_ip, created_at.
  #
  # Entries are append-only through Active Record: once saved they are
  # read-only, so +update+ and +destroy+ raise ActiveRecord::ReadOnlyRecord.
  # (This does not stop raw SQL; tamper evidence is a SealedTrail Pro feature.)
  class Entry < ActiveRecord::Base
    self.table_name = "sealed_trail_entries"

    belongs_to :item, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true

    validates :item_type, :item_id, :event, presence: true
    validates :event, inclusion: { in: SealedTrail::Model::ALL_EVENTS }

    scope :chronological, -> { order(:created_at, :id) }
    scope :reverse_chronological, -> { order(created_at: :desc, id: :desc) }

    # Entries attributed to +actor+: an Active Record object or a label such
    # as "system", "console", "rake:db:seed" or "job:ImportJob".
    scope :for_actor, lambda { |actor|
      if actor.is_a?(ActiveRecord::Base)
        where(actor_type: actor.class.polymorphic_name, actor_id: actor.id.to_s)
      else
        where(actor_type: nil, actor_id: actor.to_s)
      end
    }

    # Per-record entries about one record. Accepts a record, or a class (or
    # class name) and an id, which also works after the record was destroyed:
    #
    #   SealedTrail::Entry.for_item(post)
    #   SealedTrail::Entry.for_item(Post, 42)
    scope :for_item, lambda { |item_or_class, id = nil|
      type, id = item_key(item_or_class, id)
      where(item_type: type, item_id: id)
    }

    # Per-record entries plus bulk entries whose stored ids include the record.
    # Bulk matching searches the JSON text, so it misses ids beyond
    # config.bulk_id_limit and operations without ids (e.g. inserts on MySQL).
    scope :affecting, lambda { |item_or_class, id = nil|
      type, id = item_key(item_or_class, id)
      bulk_matches = where(item_type: type, event: SealedTrail::Model::BULK_EVENTS)
        .where("#{json_text_sql(:metadata)} LIKE ?", "%#{sanitize_sql_like(id.to_json)}%")
      where(item_type: type, item_id: id).or(bulk_matches)
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

    # Bulk operation summaries.
    scope :bulk, -> { where(event: SealedTrail::Model::BULK_EVENTS) }

    scope :for_request, ->(request_id) { where(request_id: request_id) }

    # Entries that stored +value+ with the :fingerprint strategy.
    scope :with_fingerprint, lambda { |value|
      where("#{json_text_sql(:object_changes)} LIKE ?", "%#{sanitize_sql_like(SealedTrail.fingerprint(value))}%")
    }

    def self.item_key(item_or_class, id)
      if item_or_class.is_a?(ActiveRecord::Base)
        [ item_or_class.class.polymorphic_name, item_or_class.id.to_s ]
      else
        klass = item_or_class.is_a?(Class) ? item_or_class : item_or_class.to_s.constantize
        [ klass.polymorphic_name, id.to_s ]
      end
    end

    # SQL for a JSON column as text, for LIKE searches.
    def self.json_text_sql(column)
      quoted = "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(column)}"
      case connection.adapter_name
      when /postg/i then "CAST(#{quoted} AS text)"
      when /mysql|trilogy/i then "CAST(#{quoted} AS CHAR)"
      else quoted
      end
    end

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
    def bulk? = event.to_s.start_with?("bulk_")

    # The bulk summary hash ("operation", "row_count", "ids", ...), or nil.
    def bulk_summary
      (metadata || {})["bulk"] if bulk?
    end

    # Affected ids stored for a bulk entry (strings), or nil.
    def bulk_ids
      bulk_summary&.fetch("ids", nil)
    end
  end
end
