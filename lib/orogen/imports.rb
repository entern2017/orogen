module Orocos
    module Generation
        # Instances of this class represent a toolkit that has been imported
        # using Component#using_toolkit.
        class ImportedToolkit
            attr_reader :name
            attr_reader :pkg
            attr_reader :registry
            attr_reader :typelist

            def initialize(name, pkg, registry, typelist)
                @name, @pkg, @registry, @typelist = name, pkg, registry, typelist
            end
            def includes?(name)
                typelist.include?(name)
            end
        end

        # Instances of this class represent a task library loaded in a
        # component, i.e.  a set of TaskContext defined externally and imported
        # using #using_task_library.
        #
        # For the task contexts imported this way,
        # TaskContext#external_definition?  returns true.
        class TaskLibrary < Component
            # The component in which the library has been imported
            attr_reader :base_component
            # The pkg-config file defining this task library
            attr_reader :pkg

            # Import in the +base+ component the task library whose orogen
            # specification is included in +file+
            def self.load(base, pkg, file)
                new(base, pkg).load(file)
            end

            def initialize(component, pkg)
                @base_component, @pkg = component, pkg
                super()
            end

            def task_context(name, &block) # :nodoc:
                task = super
                task.external_definition = true
                task
            end

            # True if this task library defines a toolkit
            attr_predicate :has_toolkit?, true

            def import_types_from(name, *args)
                if Utilrb::PkgConfig.has_package?("#{name}-toolkit-#{orocos_target}")
                    using_toolkit name
                    base_component.using_toolkit name
                else
                    using_toolkit self.name
                    base_component.using_toolkit self.name
                end
                import_types_from(*args) unless args.empty?
            end

            def toolkit(create = nil, &block) # :nodoc:
                if !create && !block_given?
                    super
                else
                    using_toolkit name
                    base_component.using_toolkit name
                    self.has_toolkit = true
                    nil
                end
            end

            # Task library objects represent an import, and as such they cannot
            # be generated.  This method raises NotImplementedError
            def generate; raise NotImplementedError end
            # Task library objects represent an import, and as such they cannot
            # be generated.  This method raises NotImplementedError
            def generate_build_system; raise NotImplementedError end
        end
    end
end
