require "attr_deprecated/version"
require "notifiers/deprecation_logger"
require "active_model/deprecated_attribute_set"

require 'active_support/concern'
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
      attributes = DeprecatedAttributeSet.new(attributes.compact)
      self._deprecated_attributes ||= DeprecatedAttributeSet.new

      # Taking the difference of the two sets ensures we don't deprecate the same attribute more than once
      (attributes - _deprecated_attributes).each do |attribute|
        _set_attribute_as_deprecated attribute
      end

      self._deprecated_attributes += attributes
    end

    def attr_deprecated?(attribute)
      _deprecated_attributes.include?(attribute)
    end
    
    def deprecated_attributes
      _deprecated_attributes || DeprecatedAttributeSet.new
    end

    def clear_deprecated_attributes!
      self._deprecated_attributes = _deprecated_attributes.clear
    end

    def _set_attribute_as_deprecated(attribute)
      original_attribute = "__deprecated_#{attribute}".to_sym

      alias_method(original_attribute.to_sym, attribute.to_sym)
      klass = self

      define_method attribute.to_sym do |*args|
        klass._notify_deprecated_attribute_call(attribute)

        send(original_attribute.to_sym, *args)
      end
    end

    def _notify_deprecated_attribute_call(attribute)
      @_deprecation_logger ||= AttrDeprecated::DeprecatedAttributeLogger.new(self)

      @_deprecation_logger.log_deprecated_attribute_usage(self, attribute)
    end
  end
end

class ActiveRecord::Base
  include AttrDeprecated
end

