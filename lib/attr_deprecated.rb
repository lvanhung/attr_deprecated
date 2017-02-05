require 'active_support'

require "attr_deprecated/version"
require "attr_deprecated/configuration"

require "notifiers/rails_logger"
require "active_model/deprecated_attribute_set"

require 'active_record'
require 'active_model'

module AttrDeprecated
  extend ActiveSupport::Concern

  included do
    class_attribute :_deprecated_attributes, instance_writer: false
  end

  module ClassMethods
    ##
    # == attr_deprecated
    #
    # class macro definition to non-destructively mark an attribute as deprecated.
    #
    # The original method (i.e. the one marked as deprecated) is renamed and wrapped in an alias that dispatches the notification.
    # (See the `around_alias` pattern. [Paolo Perotta. Metaprogramming Ruby, p. 121])
    #
    def attr_deprecated(*attributes)
      attributes                  = DeprecatedAttributeSet.new(attributes.compact)
      self._deprecated_attributes ||= DeprecatedAttributeSet.new

      # Rails uses lazy initialization to wrap methods, so make sure we pre-initialize any deprecated attributes
      if defined?(ActiveRecord) && ancestors.include?(ActiveRecord::Base)

        # Initialize a new instance of our ActiveRecord model from `attributes`
        new(Hash[attributes.zip(attributes.map {})])
      end

      # Taking the difference of the two sets ensures we don't deprecate the same attribute more than once
      (attributes - _deprecated_attributes).each do |attribute|
        _set_attribute_as_deprecated attribute
      end

      self._deprecated_attributes += attributes
    end

    def deprecated_attribute?(attribute)
      _deprecated_attributes.include?(attribute)
    end

    def deprecated_attributes
      _deprecated_attributes || DeprecatedAttributeSet.new
    end

    def clear_deprecated_attributes!
      self._deprecated_attributes = _deprecated_attributes.clear
    end

    ##
    # Wrap the original attribute method with appropriate notification while leaving the functionality
    # of the original method unchanged.
    def _set_attribute_as_deprecated(attribute)
      original_method = instance_method(attribute.to_sym)

      klass = self
      define_method attribute.to_sym do |*args|
        backtrace_cleaner = ActiveSupport::BacktraceCleaner.new

        backtrace = backtrace_cleaner.clean(caller)

        klass._notify_deprecated_attribute_call({klass: self, attribute: attribute, args: args, backtrace: backtrace})

        # Call the original
        original_method.bind(self).call(*args)
      end
    end

    ##
    # Notify the logger notification observer(s)
    def _notify_deprecated_attribute_call(payload)
      ActiveSupport::Notifications.instrument("deprecated_attributes.active_record", payload)
    end
  end
end


if defined?(ActiveRecord::Base)
  class ActiveRecord::Base
    include AttrDeprecated
  end

  require 'attr_deprecated/railtie.rb' if defined?(Rails)
end
