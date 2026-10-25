# frozen_string_literal: true

module SealedTrail
  # Records one summary entry per bulk operation (update_all, delete_all,
  # insert_all, insert_all!, upsert_all) on tracked models.
  #
  # The summary is stored in the entry's metadata under "bulk":
  #
  #   "operation"     => "update_all"
  #   "row_count"     => rows affected (nil when the database does not say)
  #   "ids"           => affected primary keys as strings (capped by
  #                      config.bulk_id_limit)
  #   "ids_truncated" => true when more ids matched than were stored
  #   "where_sql"     => the WHERE clause (per config.bulk_sql)
  #   "set_sql"       => for update_all with a SQL string
  #   "columns"       => for inserts, the columns written
  #
  # For update_all with a Hash, the values set are stored in object_changes as
  # [nil, value], redacted like any other change.
  module Bulk
    ITEM_ID = "*"

    module_function

    # Rails 7.2+ defines insert_all and friends on Relation; Rails 7.1 only on
    # the model class.
    def relation_inserts?
      ActiveRecord::Relation.method_defined?(:insert_all)
    end

    def track?(model)
      SealedTrail.config.track_bulk_operations &&
        SealedTrail.tracking? &&
        model.respond_to?(:sealed_trail?) && model.sealed_trail? &&
        model.sealed_trail_options.bulk
    end

    def update_all(relation, updates)
      model = relation.klass
      changes = nil
      set_sql = nil

      if updates.is_a?(Hash)
        changes = AttributeFilter.new(model).call(
          updates.to_h { |name, value| [ name.to_s.split(".").last, [ nil, sql_value(value) ] ] }
        )
        return yield if changes.empty? && updates.any?
      else
        set_sql = format_sql(model.sanitize_sql_for_assignment(updates))
      end

      ids, truncated = capture_ids(relation)
      where_sql = where_sql(relation)
      row_count = yield

      summary = { "operation" => "update_all", "row_count" => row_count, "ids" => ids, "ids_truncated" => truncated, "where_sql" => where_sql }
      summary["set_sql"] = set_sql if set_sql
      write(model, "bulk_update", changes, summary)
      row_count
    end

    def delete_all(relation)
      model = relation.klass
      ids, truncated = capture_ids(relation)
      where_sql = where_sql(relation)
      row_count = yield

      write(model, "bulk_delete", nil,
        "operation" => "delete_all", "row_count" => row_count, "ids" => ids, "ids_truncated" => truncated, "where_sql" => where_sql)
      row_count
    end

    def insert(model, operation, rows)
      result = yield
      rows = Array(rows)
      filter = AttributeFilter.new(model)
      columns = rows.flat_map { |row| row.to_h.keys.map(&:to_s) }.uniq.select { |name| filter.tracked?(name) }.sort

      pk = model.primary_key
      returned_ids = (result.columns.include?(pk) if pk.is_a?(String) && result.respond_to?(:columns))
      ids = returned_ids ? result.rows.map { |row| row[result.columns.index(pk)].to_s } : nil
      limit = SealedTrail.config.bulk_id_limit
      truncated = !!(ids && limit && ids.size > limit)
      ids = ids.first(limit) if ids && limit

      write(model, operation == :upsert_all ? "bulk_upsert" : "bulk_insert", nil,
        "operation" => operation.to_s,
        "row_count" => returned_ids ? result.rows.size : nil,
        "attempted_count" => rows.size,
        "ids" => ids,
        "ids_truncated" => truncated,
        "columns" => columns)
      result
    end

    def write(model, event, changes, summary)
      Writer.write(
        item_type: model.polymorphic_name,
        item_id: ITEM_ID,
        event: event,
        object_changes: changes,
        metadata: { "bulk" => summary.compact }
      )
    end

    def capture_ids(relation)
      pk = relation.klass.primary_key
      return [ nil, false ] unless pk.is_a?(String)

      cap = SealedTrail.config.bulk_id_limit
      scope = relation.except(:select, :includes, :preload, :eager_load)
      fetch = cap && cap + 1
      fetch = [ fetch, relation.limit_value ].compact.min if relation.limit_value
      scope = scope.limit(fetch) if fetch
      ids = scope.pluck(relation.klass.arel_table[pk]).map(&:to_s)
      truncated = !!(cap && ids.size > cap)
      [ cap ? ids.first(cap) : ids, truncated ]
    end

    def where_sql(relation)
      return nil if SealedTrail.config.bulk_sql == :none

      return nil if relation.where_clause.empty?

      connection = relation.klass.connection
      # Compile only the WHERE conditions, with bind values inlined.
      sql = connection.unprepared_statement do
        connection.visitor.compile(relation.where_clause.ast, connection.send(:collector))
      end
      format_sql(sql)
    rescue StandardError
      nil
    end

    def format_sql(sql)
      return nil if sql.blank?

      case SealedTrail.config.bulk_sql
      when :none then nil
      when :full then sql
      else sql.gsub(/'(?:[^'\\]|''|\\.)*'/, "'?'")
      end
    end

    def sql_value(value)
      value.respond_to?(:to_sql) ? value.to_sql : value
    end

    # Prepended to ActiveRecord::Relation.
    module RelationHooks
      def update_all(updates)
        return super unless SealedTrail::Bulk.track?(klass)

        SealedTrail::Bulk.update_all(self, updates) { super }
      end

      def delete_all
        return super unless SealedTrail::Bulk.track?(klass)

        SealedTrail::Bulk.delete_all(self) { super }
      end
    end

    # Prepended to ActiveRecord::Relation (Rails 7.2+) or to each tracked
    # model's singleton class (Rails 7.1).
    module InsertHooks
      %i[insert_all insert_all! upsert_all].each do |operation|
        define_method(operation) do |attributes, **options|
          model = is_a?(ActiveRecord::Relation) ? klass : self
          return super(attributes, **options) unless SealedTrail::Bulk.track?(model)

          SealedTrail::Bulk.insert(model, operation, attributes) { super(attributes, **options) }
        end
      end
    end
  end
end
