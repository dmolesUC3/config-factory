# frozen_string_literal: true

require 'config/factory/environments'

module Config
  module Factory

    def self.included(base)
      base.extend(AbstractFactory)
    end

    def env_name
      @env_name ||= Environments::DEFAULT_ENVIRONMENT
    end

    module AbstractFactory
      attr_reader :impl_key

      def key(k)
        @impl_key = k
        registry = impls_by_key
        define_singleton_method(k) do |v|
          registry[v] = self
        end
      end

      def self.extended(mod)
        filter_registry = {}
        mod.define_singleton_method(:can_build_if) do |&block|
          filter_registry[self] = block
        end
        mod.define_singleton_method(:filters_by_impl_class) { filter_registry }
      end

      def for_environment(env, config_name)
        arg_hash = env.args_for(config_name)
        raise ArgumentError, "no #{self} arguments found for config #{config_name} in environment #{env}" unless arg_hash
        build_from(arg_hash, nil, env.name)
      end

      def from_file(path, config_name)
        env = Environment.load_file(path)
        for_environment(env, config_name)
      end

      def build_from(arg_hash, section_name = nil, env_name = nil)
        raise ArgumentError, "nil argument hash passed to #{self}.build_from" unless arg_hash
        args = deep_symbolize_keys(arg_hash)
        args = args[section_name] if section_name
        impl_class = find_impl_class(args)
        begin
          return create_impl(impl_class, args, env_name)
        rescue StandardError => e
          raise ArgumentError, "Error instantiating #{impl_class} with arguments #{args}: #{e}"
        end
      end

      private

      def find_impl_class(args)
        pk = impl_key
        return impl_for_key(pk, args) if pk
        filters_by_impl_class.each_pair do |impl_class, filter|
          return impl_class if filter.call(args)
        end
        self
      end

      def impl_for_key(key_sym, args)
        raise ArgumentError, "implementation key #{key_sym} not found in argument hash #{args || 'nil'}" unless args&.key?(key_sym)
        key_value = args.delete(key_sym)
        impl_class = impls_by_key[key_value]
        raise ArgumentError, "No #{name} implementation found for #{key_sym}: #{key_value}" unless impl_class
        impl_class
      end

      def deep_symbolize_keys(val)
        return val unless val.is_a?(Hash)
        val.map do |k, v|
          [k.respond_to?(:to_sym) ? k.to_sym : k, deep_symbolize_keys(v)]
        end.to_h
      end

      def impls_by_key
        @impls_by_key ||= {}
      end

      def create_impl(impl_class, args, env_name)
        factory_impl = impl_class.new(args)
        factory_impl.instance_variable_set(:@env_name, env_name)
        factory_impl
      end
    end
  end
end
