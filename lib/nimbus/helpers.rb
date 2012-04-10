module Nimbus
  module Helpers

    def class_exists?(class_name)
      c = self.const_get(class_name)
      return c.is_a?(Class)
    rescue NameError
      return false
    end

    def get_class(class_name)
      self.const_get(class_name)
    end

    def create_class(class_name, superclass, &block)
      c = Class.new superclass, &block
      self.const_set class_name, c
      c
    end
  end
end